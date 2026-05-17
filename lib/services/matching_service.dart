import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/client_profile.dart';
import '../models/match_result.dart';
import '../models/property.dart';
import '../repositories/match_cache_repository.dart';
import '../utils/distance.dart';
import '../utils/landmarks.dart';
import 'groq_client.dart';
import 'property_prefilter.dart';

/// MatchingService — scorea propiedades contra ClientProfile con Groq real.
///
/// **No hay demo path hardcoded**. Cada score sale de Llama 3.3 70B
/// vía Groq con cache layer en Supabase (`match_scoring_cache`).
///
/// Flow:
///   1. `score(profile, property)` calcula `profile.contentHash`
///   2. Lee cache: hit → retorna instant
///   3. Miss → llama Groq con contexto (perfil + propiedad + distancias)
///   4. Guarda resultado en cache
///   5. Retorna
///
/// Si Groq falla, `_heuristicFallback()` calcula un score básico desde
/// datos reales de la propiedad (no hardcoded), con `explanation` que
/// indica modo degradado. UI nunca crashea.
class MatchingService {
  final GroqClient _groqClient;
  final MatchCacheRepository _cache;
  final PropertyPreFilter _prefilter;

  MatchingService({
    GroqClient? groqClient,
    MatchCacheRepository? cache,
    PropertyPreFilter? prefilter,
  })  : _groqClient = groqClient ?? GroqClient(),
        _cache = cache ?? NoOpMatchCacheRepository(),
        _prefilter = prefilter ?? const PropertyPreFilter();

  // ── System prompt v2 — score caps duros + labels claros ───────────────
  static const _systemPrompt = '''
Eres un asistente experto en bienes raíces de Cochabamba, Bolivia.

Evalúa qué tan bien una propiedad coincide con las preferencias del cliente.

ESCALA DE PUNTAJE (0-100) — sé honesto, no infles:
- 85-100: Excelente fit. Cumple presupuesto, distancia y todos los criterios.
- 70-84: Buen fit. Concesiones menores (1 criterio borderline).
- 50-69: Fit parcial. Concesiones significativas (1 criterio claramente falla).
- 30-49: Fit pobre. Varios criterios incumplidos.
- 0-29: Mal fit. Excede presupuesto >50%, o distancia >2× radius,
  o modalidad incompatible.

CAPS DUROS DE PUNTAJE (techos máximos):
- Precio excede budget_max en 10-30%   → score máximo 65.
- Precio excede budget_max en 30-60%   → score máximo 50.
- Precio excede budget_max en 60%+     → score máximo 35.
- Distancia >2× el radius_km del cliente → score máximo 50.
- Modalidad no coincide (cliente pide compra, prop solo anticretico) → score máximo 30.
- Propiedad ofrece MENOS dormitorios que el mínimo del cliente → resta 25 puntos.

LEE el campo voice_input_transcript del cliente: contiene su query natural.
- Si menciona "departamento", "depto" o "edificio" → propiedad ideal type:departamento.
  Si la propiedad es type:casa → resta 12 puntos.
- Si menciona "casa" explícitamente → propiedad ideal type:casa.
  Si la propiedad es type:departamento → resta 12 puntos.
- Si no menciona tipo → no penalices.

REGLAS ANTI-ALUCINACIÓN (CRÍTICAS):
- NUNCA inventes hechos. Lee SOLO los HECHOS verificados que te paso.
- Si HECHOS dice "CUMPLE con dormitorios" → NO digas "no cumple dormitorios".
- Si HECHOS dice "Modalidades: venta, anticretico" y cliente quiere "venta" →
  NO digas "sólo anticrético". DI "soporta venta y anticrético".
- Si HECHOS dice "EXCEDE 23%" → cita 23%, NO inventes 48%.
- NUNCA menciones tags que el cliente NO pidió como negativos
  (ej. "no tiene patio" cuando el cliente no pidió patio → omitir).
- NUNCA menciones landmarks que el cliente no haya mencionado en su voice_input_transcript.
  Si pidió "centro" → cita distancia a Centro. NO digas "cerca de UMSS"
  a menos que UMSS aparezca en transcript.

PESOS DE EVALUACIÓN (después de aplicar caps):
- Presupuesto (35%): valor central.
- Distancia (25%): a landmarks y a ubicación deseada del cliente.
- Modalidad (15%): venta/alquiler/anticretico.
- Bedrooms y área (15%): si pide 10 dormitorios y hay 4, score 25-40%, NUNCA 80%.
- Tags + tipo (10%): patio, familia_segura, parqueo, departamento/casa.

LABELS DE FACTORES — usa texto CORTO Y CLARO en español, sin jerga:
  positivos OK: "Dentro de presupuesto", "Cerca de UMSS", "4 dormitorios",
                "Patio amplio", "Modalidad compra disponible"
  positivos MAL: "Modalidad de transacción coincide", "Bedroom count match"
  negativos OK: "Excede presupuesto 48%", "Lejos de UMSS (4 km)",
                "Sólo anticrético", "Es casa, no departamento", "Sin parqueo"
  negativos MAL: "Modalidad de transacción no aplica", "Distance over radius"

Devuelve JSON estricto en español (sin markdown):
{
  "compatibility_percent": int 0-100,
  "explanation": string conversacional max 60 palabras,
  "tags_matched": [string array],
  "tags_missing": [string array],
  "positive_factors": [string array, máximo 3, labels cortos y claros],
  "negative_factors": [string array, máximo 3, labels cortos y claros]
}
''';

  /// API pública. Cache check → Groq → cache write → return.
  Future<MatchResult> score({
    required ClientProfile profile,
    required Property property,
    bool useCache = true,
  }) async {
    final profileHash = profile.contentHash;

    if (useCache) {
      final cached = await _cache.get(
        propertyId: property.id,
        profileHash: profileHash,
      );
      if (cached != null) {
        debugPrint(
          '[Hito.Matching] cache HIT id=${property.id} hash=$profileHash '
          'compat=${cached.compatibilityPercent}%',
        );
        // Aplicar filter de alucinaciones también a resultados cacheados,
        // porque el cache puede tener factor strings ahalucinados desde runs
        // anteriores (antes de que metiéramos el filter).
        return _filterHallucinations(
          cached.copyWith(clientProfileId: profile.id),
          profile,
          property,
        );
      }
    }

    debugPrint(
      '[Hito.Matching] cache MISS id=${property.id} → Groq Llama 3.3',
    );

    try {
      final result = await _scoreWithLlm(profile: profile, property: property);
      await _cache.upsert(
        propertyId: property.id,
        profileHash: profileHash,
        profileJson: profile.toJson(),
        result: result,
      );
      return result;
    } catch (e, stack) {
      debugPrint('[Hito.Matching] Groq failed: $e\n$stack');
      return _heuristicFallback(profile: profile, property: property);
    }
  }

  /// Pre-filter + score top N. El pre-filter descarta property no-aptas
  /// (modalidad/tipo/bedrooms incompatibles) y rankea heurístico → solo
  /// top 6 van al LLM. Reduce calls Groq de 12 → 6 y evita 429s.
  ///
  /// Batches de 3 paralelos con 400ms entre batches.
  Future<List<MatchResult>> scoreAll({
    required ClientProfile profile,
    required List<Property> properties,
    bool useCache = true,
    int batchSize = 3,
    Duration batchDelay = const Duration(milliseconds: 400),
  }) async {
    final candidates = _prefilter.apply(profile, properties);
    debugPrint(
      '[Hito.Matching] prefilter: ${properties.length} → '
      '${candidates.length} candidates (${candidates.map((p) => p.id).join(",")})',
    );

    final results = <MatchResult>[];
    for (var i = 0; i < candidates.length; i += batchSize) {
      final end = math.min(i + batchSize, candidates.length);
      final batch = candidates.sublist(i, end);
      final batchResults = await Future.wait(
        batch.map(
          (p) => score(profile: profile, property: p, useCache: useCache),
        ),
      );
      results.addAll(batchResults);
      if (end < candidates.length) {
        await Future<void>.delayed(batchDelay);
      }
    }
    results.sort(
      (a, b) => b.compatibilityPercent.compareTo(a.compatibilityPercent),
    );
    return results;
  }

  /// Streaming token-by-token de la explicación. Usa el cache si existe
  /// (texto real generado por LLM, "replayed" char-by-char para UX); si
  /// no, hace streaming directo de Groq.
  Stream<String> explainStreaming({
    required ClientProfile profile,
    required Property property,
  }) async* {
    final profileHash = profile.contentHash;
    final cached = await _cache.get(
      propertyId: property.id,
      profileHash: profileHash,
    );

    if (cached != null) {
      final text =
          '${cached.compatibilityPercent}% compatible contigo. ${cached.explanation}';
      for (var i = 0; i < text.length; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        yield text[i];
      }
      return;
    }

    // Cache miss → real Groq streaming, con contexto enriquecido.
    final propertyContext = _buildPropertyContext(profile, property);
    final userPrompt =
        'Perfil cliente:\n${jsonEncode(profile.toJson())}\n\n'
        'Propiedad:\n$propertyContext\n\n'
        'Da en máximo 50 palabras una explicación conversacional, '
        'empezando con "X% compatible contigo:" donde X es tu estimación.';

    yield* _groqClient.chatStream(
      messages: [
        const {'role': 'system', 'content': _systemPromptForStreaming},
        {'role': 'user', 'content': userPrompt},
      ],
    );
  }

  static const _systemPromptForStreaming = '''
Eres un asistente inmobiliario boliviano. Explicas en español, máximo 50
palabras, por qué una propiedad matchea con el cliente. Sé concreto,
conversacional. Empiezas con "X% compatible contigo:" donde X es el
porcentaje. Mencionas factores clave: distancia, presupuesto, bedrooms.
''';

  // ── Internals ───────────────────────────────────────────────────────────

  Future<MatchResult> _scoreWithLlm({
    required ClientProfile profile,
    required Property property,
  }) async {
    final userPrompt =
        'Perfil cliente:\n${jsonEncode(profile.toJson())}\n\n'
        'Propiedad:\n${_buildPropertyContext(profile, property)}';

    final raw = await _chatWithRetry(
      messages: [
        const {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
    );

    final json = GroqClient.extractJson(raw);
    if (json == null) {
      throw FormatException('Groq returned non-JSON: $raw');
    }

    final llmResult = MatchResult.fromJson({
      ...json,
      'property_id': property.id,
      'client_profile_id': profile.id,
    });

    final shortExpl = llmResult.explanation.length > 90
        ? '${llmResult.explanation.substring(0, 90)}...'
        : llmResult.explanation;
    debugPrint(
      '[Hito.Matching] llm id=${property.id} raw=${llmResult.compatibilityPercent}% '
      '+[${llmResult.positiveFactors.join(", ")}] '
      '-[${llmResult.negativeFactors.join(", ")}] '
      '"$shortExpl"',
    );

    final filtered = _filterHallucinations(llmResult, profile, property);
    return _applyCaps(filtered, profile, property);
  }

  /// Elimina factor strings del LLM que contradicen HECHOS verificados.
  /// El LLM tiende a "Sin garaje" cuando hay parqueos, "Es casa, no
  /// departamento" cuando user no pidió depto, "No tiene patio" cuando user
  /// no pidió patio, etc. Aquí los pinchamos antes de que lleguen al UI.
  MatchResult _filterHallucinations(
    MatchResult result,
    ClientProfile profile,
    Property property,
  ) {
    final transcriptLower =
        (profile.voiceInputTranscript ?? '').toLowerCase();
    final userWantsDepto = transcriptLower.contains('depto') ||
        transcriptLower.contains('departamento') ||
        transcriptLower.contains('edificio');
    final userWantsCasa =
        !userWantsDepto && transcriptLower.contains('casa');
    final userWantsPatio = transcriptLower.contains('patio');

    bool isHallucination(String factor) {
      final f = factor.toLowerCase();

      // "Sin garaje/parqueo/cochera" cuando property tiene parking
      if (property.parking > 0 &&
          (f.contains('sin garaje') ||
              f.contains('sin parqueo') ||
              f.contains('sin cochera') ||
              f.contains('no tiene garaje') ||
              f.contains('no tiene parqueo') ||
              f.contains('falta de garaje') ||
              f.contains('falta de parqueo'))) {
        debugPrint(
          '[Hito.Matching] dropped halluc factor for ${property.id}: '
          '"$factor" (parking=${property.parking})',
        );
        return true;
      }

      // "Es casa, no departamento" cuando user NO pidió depto
      if (!userWantsDepto &&
          (f.contains('no departamento') ||
              f.contains('no es departamento') ||
              f.contains('es casa, no'))) {
        debugPrint(
          '[Hito.Matching] dropped halluc factor for ${property.id}: '
          '"$factor" (user did not request depto)',
        );
        return true;
      }

      // "Es departamento, no casa" cuando user NO pidió casa
      if (!userWantsCasa &&
          (f.contains('no es casa') || f.contains('es departamento, no'))) {
        debugPrint(
          '[Hito.Matching] dropped halluc factor for ${property.id}: '
          '"$factor" (user did not request casa)',
        );
        return true;
      }

      // "No tiene patio" cuando user no pidió patio
      if (!userWantsPatio &&
          (f.contains('sin patio') || f.contains('no tiene patio'))) {
        debugPrint(
          '[Hito.Matching] dropped halluc factor for ${property.id}: '
          '"$factor" (user did not request patio)',
        );
        return true;
      }

      // "Modalidad de transacción" — label feo del LLM
      if (f.contains('modalidad de transacción')) {
        return true;
      }

      // Si user no especificó ubicación (radius >= 50 = sentinel), drop
      // cualquier factor que mencione distancia/ubicación.
      if (profile.radiusKm >= 50 &&
          (f.contains('lejos de ubicación') ||
              f.contains('cerca de ubicación') ||
              f.contains('lejos de la ubicación') ||
              f.contains('fuera del radio') ||
              f.contains('dentro del radio'))) {
        debugPrint(
          '[Hito.Matching] dropped halluc factor for ${property.id}: '
          '"$factor" (user did not specify location)',
        );
        return true;
      }

      // Mención de landmark específico que user no pidió
      const landmarkKeywords = [
        'umss',
        'upb',
        'ucb',
        'univalle',
        'recoleta',
        'centro',
        'cala cala',
        'queru',
        'sarco',
        'tupuraya',
      ];
      for (final lm in landmarkKeywords) {
        if (f.contains(lm) && !transcriptLower.contains(lm)) {
          // Excepción: si la propiedad está en ese barrio y el factor es
          // positivo neutro ("Excelente ubicación en X"), permitir.
          if (property.neighborhood
                  ?.toLowerCase()
                  .contains(lm.replaceAll(' ', '_')) ==
              true) {
            continue;
          }
          debugPrint(
            '[Hito.Matching] dropped halluc factor for ${property.id}: '
            '"$factor" (user did not mention $lm)',
          );
          return true;
        }
      }

      return false;
    }

    return result.copyWith(
      positiveFactors:
          result.positiveFactors.where((f) => !isHallucination(f)).toList(),
      negativeFactors: result.negativeFactors
          .where((f) => !isHallucination(f))
          .toList(),
    );
  }

  /// Aplica caps duros al score del LLM. El LLM a veces es lenient con
  /// budget overruns ("este tiene buen patio así que 85"), pero queremos
  /// scores honestos. Esto es la verdad determinística que el LLM debería
  /// emitir, y la enforced aquí.
  MatchResult _applyCaps(
    MatchResult result,
    ClientProfile profile,
    Property property,
  ) {
    var capped = result.compatibilityPercent;
    final reasons = <String>[];

    // Budget excess cap — usa effectivePriceBob según modalidad
    final effectivePrice =
        property.effectivePriceBob(profile.transactionType);
    if (profile.budgetMax > 0 && effectivePrice > 0) {
      final excess =
          (effectivePrice - profile.budgetMax) / profile.budgetMax;
      if (excess > 0.6) {
        capped = math.min(capped, 35);
        reasons.add('budget +${(excess * 100).round()}% → cap 35');
      } else if (excess > 0.3) {
        capped = math.min(capped, 50);
        reasons.add('budget +${(excess * 100).round()}% → cap 50');
      } else if (excess > 0.1) {
        capped = math.min(capped, 65);
        reasons.add('budget +${(excess * 100).round()}% → cap 65');
      }
    }

    // Distance cap — beyond 2× radius is unreasonable.
    // Si radius >= 50 → user no especificó ubicación, no aplicamos cap.
    final dKm = property.distanceToKm(profile.desiredLocation);
    if (profile.radiusKm > 0 &&
        profile.radiusKm < 50 &&
        dKm > profile.radiusKm * 2) {
      capped = math.min(capped, 50);
      reasons.add(
        'distance ${dKm.toStringAsFixed(1)}km > 2× radius ${profile.radiusKm}km → cap 50',
      );
    }

    // Modality cap — compra y venta son la misma operación (buyer vs seller
    // perspective). Normalizamos antes de comparar para no falsear caps.
    final supports = property.supportedTransactions.isNotEmpty
        ? property.supportedTransactions
        : [property.listingMode];
    final wantedNormalized = profile.transactionType == 'compra'
        ? 'venta'
        : profile.transactionType;
    final matches = supports.any(
      (s) => s == wantedNormalized || (s == 'venta' && wantedNormalized == 'compra'),
    );
    if (!matches) {
      capped = math.min(capped, 30);
      reasons.add(
        '${profile.transactionType} no soportada (${supports.join(",")}) → cap 30',
      );
    }

    if (capped == result.compatibilityPercent) return result;

    debugPrint(
      '[Hito.Matching] cap ${property.id}: '
      '${result.compatibilityPercent}% → $capped% (${reasons.join("; ")})',
    );
    return result.copyWith(compatibilityPercent: capped);
  }

  /// Chain de modelos. En OpenRouter (sin rate limits), solo usamos 70b.
  /// En Groq (con rate limits), 70b primary + 8b fallback.
  /// Resuelto dinámicamente porque los IDs de modelo cambian según provider.
  static List<String> get _modelChain {
    final primary = GroqModels.matchingPrimary;
    final fallback = GroqModels.matchingFallback;
    if (primary == fallback) return [primary];
    return [primary, fallback];
  }

  /// Chat con fallback chain + retry en 429/400.
  /// Para cada modelo: 2 intentos (inmediato + 1s) en 429. Si 400 (modelo
  /// no soporta json_object, o request inválido), pasa al next sin retry.
  /// Si fallan todos los modelos → propaga error → _heuristicFallback.
  Future<String> _chatWithRetry({
    required List<Map<String, String>> messages,
  }) async {
    Object? lastError;
    for (final model in _modelChain) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          return await _groqClient.chat(
            messages: messages,
            model: model,
            temperature: 0.2,
            responseFormat: {'type': 'json_object'},
          );
        } on DioException catch (e) {
          lastError = e;
          final code = e.response?.statusCode;
          if (code == 429) {
            if (attempt == 0) {
              debugPrint('[Hito.Matching] $model 429, retry in 1s');
              await Future<void>.delayed(const Duration(seconds: 1));
            } else {
              debugPrint('[Hito.Matching] $model exhausted, fallback');
            }
            continue;
          }
          if (code == 400) {
            debugPrint(
              '[Hito.Matching] $model 400 (likely json_object unsupported), fallback',
            );
            break; // next model
          }
          rethrow;
        }
      }
    }
    throw lastError ?? Exception('All models in chain failed');
  }

  /// Construye el bloque de contexto con HECHOS explícitos y verificados,
  /// + comparaciones con el perfil del cliente. Evita que el LLM invente
  /// (ej. decir "no cumple dormitorios" cuando los supera).
  String _buildPropertyContext(ClientProfile profile, Property property) {
    final distanceToDesired =
        property.distanceToKm(profile.desiredLocation);
    final landmarkDistances = property.distancesToLandmarks;

    final supports = property.supportedTransactions.isNotEmpty
        ? property.supportedTransactions
        : [property.listingMode];
    final wantedTx = profile.transactionType == 'compra'
        ? 'venta'
        : profile.transactionType;
    final modalityMatch = supports.contains(wantedTx);

    final bedroomsDiff = property.bedrooms - profile.minBedrooms;
    final bedroomsLine = bedroomsDiff >= 0
        ? '  - Dormitorios: ${property.bedrooms} (cliente pidió mínimo ${profile.minBedrooms} → CUMPLE${bedroomsDiff > 0 ? " con $bedroomsDiff extra" : ""})'
        : '  - Dormitorios: ${property.bedrooms} (cliente pidió mínimo ${profile.minBedrooms} → NO CUMPLE, faltan ${-bedroomsDiff})';

    final budgetMaxBob = profile.budgetMax;
    final effectivePrice =
        property.effectivePriceBob(profile.transactionType);
    final priceLabel = profile.transactionType == 'anticretico'
        ? 'Capital anticrético'
        : 'Precio venta';
    final budgetExcessPct = (budgetMaxBob > 0 && effectivePrice > 0)
        ? ((effectivePrice - budgetMaxBob) / budgetMaxBob * 100).round()
        : 0;
    final budgetLine = budgetExcessPct > 0
        ? '  - $priceLabel: $effectivePrice BOB (cliente max $budgetMaxBob → EXCEDE $budgetExcessPct%)'
        : effectivePrice > 0
            ? '  - $priceLabel: $effectivePrice BOB (cliente max $budgetMaxBob → DENTRO de rango)'
            : '  - $priceLabel: no aplicable a esta propiedad en modalidad ${profile.transactionType}';

    final modalityLine = modalityMatch
        ? '  - Modalidades: ${supports.join(", ")} (cliente quiere $wantedTx → SOPORTADA)'
        : '  - Modalidades: ${supports.join(", ")} (cliente quiere $wantedTx → NO SOPORTADA)';

    final tagsOverlap = profile.requiredTags
        .where((t) => property.cochabambaTags.contains(t))
        .toList();
    final tagsMissing = profile.requiredTags
        .where((t) => !property.cochabambaTags.contains(t))
        .toList();

    final hasSpecificLocation = profile.radiusKm < 50;
    final landmarkLines = hasSpecificLocation
        ? Landmarks.matchingContext.map((l) {
            final km = landmarkDistances[l.slug]!;
            return '  - ${l.displayName}: ${formatDistance(km)}';
          }).join('\n')
        : '  (cliente no especificó ubicación — no penalices distancia)';

    return 'HECHOS verificados de la propiedad ${property.id} '
        '"${property.title ?? property.address}":\n'
        '  - Tipo: ${property.type}\n'
        '  - Neighborhood: ${property.neighborhood ?? "n/a"}\n'
        '$budgetLine\n'
        '$bedroomsLine\n'
        '  - Área construida: ${property.areaM2} m²\n'
        '  - Parqueos: ${property.parking}\n'
        '$modalityLine\n'
        '  - Año construcción: ${property.yearBuilt ?? "n/a"}\n'
        '  - Tags cliente cumplidos: ${tagsOverlap.isEmpty ? "ninguno" : tagsOverlap.join(", ")}\n'
        '  - Tags cliente faltantes: ${tagsMissing.isEmpty ? "ninguno" : tagsMissing.join(", ")}\n'
        '  - Has lien: ${property.hasLien}\n\n'
        '${hasSpecificLocation ? "UBICACIÓN deseada del cliente: "
            "lat=${profile.desiredLat}, lng=${profile.desiredLng}, "
            "radius=${profile.radiusKm} km\n"
            "Distancia propiedad → ubicación deseada del cliente: "
            "${formatDistance(distanceToDesired)}\n\n"
            "Distancias a landmarks principales (referencia):\n$landmarkLines" : "El cliente NO especificó preferencia de ubicación — "
            "NO incluyas distancia/ubicación en positive_factors ni negative_factors."}';
  }

  /// Score de emergencia cuando Groq no responde. Usa datos REALES de la
  /// propiedad (no hardcoded), comunica abiertamente "AI offline".
  MatchResult _heuristicFallback({
    required ClientProfile profile,
    required Property property,
  }) {
    var score = 50;
    final positive = <String>[];
    final negative = <String>[];

    // Budget fit (35 puntos)
    if (property.priceBob >= profile.budgetMin &&
        property.priceBob <= profile.budgetMax) {
      score += 25;
      positive.add('Dentro de presupuesto');
    } else if (property.priceBob > profile.budgetMax) {
      score -= 30;
      negative.add('Excede presupuesto');
    } else {
      positive.add('Por debajo de presupuesto');
    }

    // Bedrooms fit (15 puntos)
    if (property.bedrooms >= profile.minBedrooms) {
      score += 10;
      positive.add('${property.bedrooms} dormitorios');
    } else {
      score -= 25;
      negative.add('Solo ${property.bedrooms} dormitorios');
    }

    // Distance to desired location (25 puntos)
    final dKm = property.distanceToKm(profile.desiredLocation);
    if (dKm <= profile.radiusKm) {
      score += 15;
      positive.add('A ${formatDistance(dKm)} de ubicación deseada');
    } else {
      score -= ((dKm - profile.radiusKm) * 5).round().clamp(0, 25);
      negative.add('Lejos de ubicación deseada (${formatDistance(dKm)})');
    }

    // Transaction type (15 puntos)
    final supports = property.supportedTransactions.isNotEmpty
        ? property.supportedTransactions
        : [property.listingMode];
    if (supports.contains(profile.transactionType)) {
      score += 10;
    } else {
      score -= 20;
      negative.add('Modalidad no coincide');
    }

    // Tags (10 puntos)
    final tagsMatched = <String>[];
    final tagsMissing = <String>[];
    for (final tag in profile.requiredTags) {
      if (property.cochabambaTags.contains(tag) ||
          (tag == 'acepta_anticretico' && property.supportsAnticretico)) {
        tagsMatched.add(tag);
      } else {
        tagsMissing.add(tag);
      }
    }
    if (profile.requiredTags.isNotEmpty) {
      score += ((tagsMatched.length / profile.requiredTags.length) * 10)
          .round();
    }

    score = score.clamp(5, 95);

    return MatchResult(
      propertyId: property.id,
      clientProfileId: profile.id,
      compatibilityPercent: score,
      explanation: '$score% compatible (modo offline — IA no disponible). '
          'Score basado en presupuesto, dormitorios y distancia real a tu '
          'ubicación deseada (${formatDistance(dKm)}).',
      positiveFactors: positive.take(3).toList(),
      negativeFactors: negative.take(3).toList(),
      tagsMatched: tagsMatched,
      tagsMissing: tagsMissing,
    );
  }
}
