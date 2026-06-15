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

/// Snapshot del progreso de `scoreAllStream`. La UI lo consume para pintar
/// el mapa con markers que aparecen progresivamente + un indicador de
/// "evaluando X de Y".
class MatchingBatch {
  /// Propiedades que pasaron el pre-filter — el conjunto que va a ser scoreado.
  final List<Property> candidates;

  /// MatchResults emitidos hasta el momento (acumulado a través de batches).
  final List<MatchResult> completed;

  /// IDs de propiedades aún pendientes de scoring.
  final List<String> pending;

  const MatchingBatch({
    required this.candidates,
    required this.completed,
    required this.pending,
  });

  bool get isComplete => pending.isEmpty;
  int get total => candidates.length;
  int get done => completed.length;
}

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
Eres un asistente experto en bienes raíces de Oruro, Bolivia.

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
- Si HECHOS dice "Parqueos: 3" y cliente pidió 2 → "3 parqueos (supera lo pedido)"
  en recommended. JAMÁS digas "no tiene garage" cuando el conteo es > 0.
- NUNCA menciones tags que el cliente NO pidió como negativos
  (ej. "no tiene patio" cuando el cliente no pidió patio → omitir).
- NUNCA menciones landmarks que el cliente no haya mencionado en su voice_input_transcript.
  Si pidió "centro" → cita distancia a Centro. NO digas "cerca de UMSS"
  a menos que UMSS aparezca en transcript.
- PROHIBIDO mencionar como considerations/risks cualquiera de estas
  características a menos que el cliente las haya pedido explícitamente
  en su transcript o en sus required_tags:
    * "familia segura" / "zona segura" / "seguridad" / "no es seguro"
    * "jardín" / "sin jardín"
    * "piscina" / "alberca"
    * "vista panorámica"
    * "quincho" / "parrilla"
    * "terraza" / "balcón"
    * "acepta mascotas"
  Si el cliente NO mencionó esto, ese factor es INVENTADO. Omitilo.
- PROHIBIDO usar como negative "no cumple con tags requeridos" / "no cumple
  con tags solicitados" si tags_matched + tags_missing está vacío.

REGLA CLAVE PARA considerations y risks:
- `considerations` debe estar VACÍA si no hay nada genuinamente neutro que
  el cliente debería verificar (no rellenes con strengths re-empaquetados).
- `risks` debe estar VACÍA si la propiedad no tiene problemas serios.
- Una propiedad que cumple TODO sin riesgos legítimos debe tener:
  `{"recommended": [...], "considerations": [], "risks": []}`.
- PROHIBIDO poner "Año 2018" o "Área 280m²" en considerations — eso son
  hechos de la property que si son favorables van a recommended, si no aplican
  no van a ningún lado. Considerations es solo para cosas a VERIFICAR.

PESOS DE EVALUACIÓN (después de aplicar caps):
- Presupuesto (35%): valor central.
- Distancia (25%): a landmarks y a ubicación deseada del cliente.
- Modalidad (15%): venta/alquiler/anticretico.
- Bedrooms y área (15%): si pide 10 dormitorios y hay 4, score 25-40%, NUNCA 80%.
- Tags + tipo (10%): patio, familia_segura, parqueo, departamento/casa.

CLASIFICACIÓN DE HALLAZGOS — usá 3 buckets según severidad/accionabilidad:

1. RECOMMENDED (fortalezas claras del fit — el agente las usa como pitch):
   Ejemplos OK: "Dentro de presupuesto", "4 dormitorios cumple", "Año 2021 muy nueva",
                "Lote 380m² amplio", "3 parqueos disponibles", "Cerca de UMSS"
   Ejemplos MAL: "Modalidad de transacción coincide", "Has bedrooms"

2. CONSIDERATIONS (hechos a verificar antes de cerrar — info neutra/ámbar):
   Ejemplos OK: "Año 2015 — pedir registro de mantenimiento",
                "Lote chico (290m²) vs alternativas del mismo bucket",
                "Sin descripción de cocina/dormitorios en listing",
                "Distancia 2.8km al colegio del barrio (verificar)"
   Ejemplos MAL: cualquier cosa inventada que el cliente no pidió.

3. RISKS (problemas serios que afectan la decisión — rojo):
   Ejemplos OK: "Excede presupuesto 22%", "Lejos del radio pedido (5km)",
                "Solo soporta anticrético", "Cliente pidió 4 dorm, propiedad tiene 3",
                "Tiene gravamen activo declarado"
   Ejemplos MAL: "Sin patio" cuando user no pidió patio (eso ni siquiera entra).

REGLA: Si el factor sería PROHIBIDO por las reglas anti-alucinación
(menciona algo que el cliente no pidió, o contradice los HECHOS),
NO lo emitas en ningún bucket. Mejor 1 hallazgo real que 3 inventados.

Devuelve JSON estricto en español (sin markdown):
{
  "compatibility_percent": int 0-100,
  "explanation": string conversacional max 60 palabras,
  "tags_matched": [string array],
  "tags_missing": [string array],
  "recommended": [string array, máximo 4, labels cortos y claros],
  "considerations": [string array, máximo 3, opcional — vacío si no aplica],
  "risks": [string array, máximo 3, opcional — vacío si no aplica]
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
    final results = <MatchResult>[];
    await for (final batchResult in scoreAllStream(
      profile: profile,
      properties: properties,
      useCache: useCache,
      batchSize: batchSize,
      batchDelay: batchDelay,
    )) {
      results.addAll(batchResult.completed);
    }
    results.sort(
      (a, b) => b.compatibilityPercent.compareTo(a.compatibilityPercent),
    );
    return results;
  }

  /// Versión streaming de `scoreAll`. Emite eventos `MatchingBatch` cada vez
  /// que termina un batch — la UI puede pintar markers progresivamente y
  /// mostrar un indicador "evaluando p07…" en vivo.
  ///
  /// El primer evento se emite con la lista de candidates pre-filter
  /// (sin scores aún, `completed` vacío) para que la UI pueda dibujar el
  /// estado inicial. Eventos subsiguientes traen resultados acumulados.
  Stream<MatchingBatch> scoreAllStream({
    required ClientProfile profile,
    required List<Property> properties,
    bool useCache = true,
    int batchSize = 3,
    Duration batchDelay = const Duration(milliseconds: 400),
  }) async* {
    final candidates = _prefilter.apply(profile, properties);
    debugPrint(
      '[Hito.Matching] prefilter: ${properties.length} → '
      '${candidates.length} candidates (${candidates.map((p) => p.id).join(",")})',
    );

    // Evento inicial: sabemos qué propiedades vamos a evaluar pero no hay
    // scores aún. La UI lo usa para empezar el radar/spinner.
    yield MatchingBatch(
      candidates: candidates,
      completed: const [],
      pending: candidates.map((p) => p.id).toList(),
    );

    final completed = <MatchResult>[];
    final pending = candidates.map((p) => p.id).toList();
    for (var i = 0; i < candidates.length; i += batchSize) {
      final end = math.min(i + batchSize, candidates.length);
      final batch = candidates.sublist(i, end);
      final batchResults = await Future.wait(
        batch.map(
          (p) => score(profile: profile, property: p, useCache: useCache),
        ),
      );
      completed.addAll(batchResults);
      for (final r in batchResults) {
        pending.remove(r.propertyId);
      }
      yield MatchingBatch(
        candidates: candidates,
        completed: List.unmodifiable(completed),
        pending: List.unmodifiable(pending),
      );
      if (end < candidates.length) {
        await Future<void>.delayed(batchDelay);
      }
    }

    // Tiebreaker final: cuando varias propiedades comparten el mismo set de
    // factores (ej. todas "Dentro presupuesto, 4 dorm, Compra OK") el LLM
    // les da scores 70/75/80 sin criterio claro — es ruido. Acá normalizamos:
    // base = median del grupo, +bonus determinístico por superioridad real
    // (año más nuevo, área mayor, más parqueo si pidió garaje, mejor precio).
    if (completed.length > 1) {
      final propMap = {for (final p in candidates) p.id: p};
      final adjusted = _applyTiebreakers(completed, profile, propMap);
      yield MatchingBatch(
        candidates: candidates,
        completed: List.unmodifiable(adjusted),
        pending: const [],
      );
    }
  }

  /// Normaliza scores cuando hay grupos de propiedades con factores
  /// equivalentes. Algoritmo:
  ///   1. Agrupa por "fingerprint" de positive+negative factors.
  ///   2. Para grupos de >=2: usa el median del LLM como score base + bonus
  ///      determinístico [-5, +6] basado en superioridad objetiva vs peers.
  ///   3. Grupos de 1 propiedad pasan tal cual (no hay con qué compararlos).
  ///
  /// Resultado: propiedades equivalentes se diferencian por hechos del seed
  /// (año, área, parqueos, precio) en vez del muestreo del LLM.
  List<MatchResult> _applyTiebreakers(
    List<MatchResult> results,
    ClientProfile profile,
    Map<String, Property> propertiesById,
  ) {
    /// Fingerprint COARSE: agrupa por compatibilidad estructural, no por el
    /// texto literal del LLM. Dos propiedades caen en el mismo grupo si:
    ///   - Ambas están dentro/fuera de budget igual
    ///   - Ambas cumplen/no cumplen modalidad
    ///   - Ambas cumplen/no cumplen bedrooms mínimos
    ///   - Su score LLM cae en el mismo bucket de 10 puntos (60s, 70s, 80s)
    ///
    /// Antes el fingerprint era el texto literal de los factores → el LLM
    /// genera variaciones leves por property ("Año 2018, Área 280m²") y cada
    /// una caía en su propio grupo de 1 → tiebreaker no se disparaba nunca.
    String fingerprint(MatchResult r) {
      final p = propertiesById[r.propertyId];
      if (p == null) return 'orphan-${r.propertyId}';
      final effectivePrice =
          p.effectivePriceBob(profile.transactionType);
      final inBudget = profile.budgetMax <= 0 ||
          effectivePrice == 0 ||
          effectivePrice <= profile.budgetMax;
      final supports = p.supportedTransactions.isNotEmpty
          ? p.supportedTransactions
          : [p.listingMode];
      final wantedNorm = profile.transactionType == 'compra'
          ? 'venta'
          : profile.transactionType;
      final modalityOK = supports.contains(wantedNorm);
      final bedroomsOK = p.bedrooms >= profile.minBedrooms;
      final bucket = (r.compatibilityPercent ~/ 10) * 10;
      return 'b:$inBudget|m:$modalityOK|d:$bedroomsOK|s:$bucket';
    }

    final groups = <String, List<MatchResult>>{};
    for (final r in results) {
      groups.putIfAbsent(fingerprint(r), () => []).add(r);
    }

    final transcript = (profile.voiceInputTranscript ?? '').toLowerCase();
    final userWantsParking =
        transcript.contains('garaje') || transcript.contains('garage') ||
        transcript.contains('parqueo') || transcript.contains('cochera');

    final adjusted = <MatchResult>[];
    for (final group in groups.values) {
      if (group.length == 1) {
        adjusted.add(group.first);
        continue;
      }

      final peers = group
          .map((r) => propertiesById[r.propertyId])
          .whereType<Property>()
          .toList();
      if (peers.length < 2) {
        adjusted.addAll(group);
        continue;
      }

      // Base = median (más estable que mean ante outliers del LLM)
      final scores = group.map((r) => r.compatibilityPercent).toList()
        ..sort();
      final median = scores[scores.length ~/ 2];

      // Pre-cálculo de extremos del grupo para el bonus
      final years = peers
          .map((p) => p.yearBuilt ?? 0)
          .where((y) => y > 0)
          .toList();
      final maxYear =
          years.isEmpty ? 0 : years.reduce((a, b) => a > b ? a : b);
      final minYear =
          years.isEmpty ? 0 : years.reduce((a, b) => a < b ? a : b);

      final areas = peers.map((p) => p.areaM2).where((a) => a > 0).toList();
      final maxArea =
          areas.isEmpty ? 0 : areas.reduce((a, b) => a > b ? a : b);
      final minArea =
          areas.isEmpty ? 0 : areas.reduce((a, b) => a < b ? a : b);

      final parkings = peers.map((p) => p.parking).toList();
      final maxParking =
          parkings.isEmpty ? 0 : parkings.reduce((a, b) => a > b ? a : b);

      final prices = peers
          .map((p) => p.priceUsdParalelo)
          .where((p) => p > 0)
          .toList();
      final minPrice =
          prices.isEmpty ? 0 : prices.reduce((a, b) => a < b ? a : b);

      for (final r in group) {
        final p = propertiesById[r.propertyId];
        if (p == null) {
          adjusted.add(r);
          continue;
        }
        var bonus = 0;
        final reasons = <String>[];

        // Año: el más nuevo +3, el más viejo -2 (si el grupo tiene rango).
        if (maxYear > minYear && p.yearBuilt != null) {
          if (p.yearBuilt == maxYear) {
            bonus += 3;
            reasons.add('newest(${p.yearBuilt})');
          } else if (p.yearBuilt == minYear) {
            bonus -= 2;
            reasons.add('oldest(${p.yearBuilt})');
          }
        }

        // Área: la más grande +2, la más chica -1.
        if (maxArea > minArea) {
          if (p.areaM2 == maxArea) {
            bonus += 2;
            reasons.add('biggest(${p.areaM2}m²)');
          } else if (p.areaM2 == minArea) {
            bonus -= 1;
            reasons.add('smallest(${p.areaM2}m²)');
          }
        }

        // Parqueo: si user pidió garaje y este tiene más que el resto del grupo +2.
        if (userWantsParking && maxParking > 0 && p.parking == maxParking) {
          // Solo bonificar si NO todos tienen el mismo número (sería irrelevante)
          if (parkings.any((x) => x < maxParking)) {
            bonus += 2;
            reasons.add('most-parking(${p.parking})');
          }
        }

        // Mejor precio (más barato dentro del mismo bucket) +1.
        if (minPrice > 0 && p.priceUsdParalelo == minPrice) {
          if (prices.any((x) => x > minPrice)) {
            bonus += 1;
            reasons.add('cheapest(\$${p.priceUsdParalelo})');
          }
        }

        final newScore = (median + bonus).clamp(5, 95);
        if (newScore != r.compatibilityPercent) {
          debugPrint(
            '[Hito.Matching] tiebreaker ${r.propertyId}: '
            '${r.compatibilityPercent}% → $newScore% '
            '(median=$median bonus=$bonus ${reasons.join(",")})',
          );
        }
        adjusted.add(r.copyWith(compatibilityPercent: newScore));
      }
    }
    return adjusted;
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
      '✓[${llmResult.recommended.join(", ")}] '
      '⚠[${llmResult.considerations.join(", ")}] '
      '✗[${llmResult.risks.join(", ")}] '
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
    bool transcriptHas(String token) => transcriptLower.contains(token);

    final userWantsDepto = transcriptHas('depto') ||
        transcriptHas('departamento') ||
        transcriptHas('edificio');
    final userWantsCasa = !userWantsDepto && transcriptHas('casa');
    final userWantsPatio = transcriptHas('patio');

    // Tag-keys que el LLM tiende a inventar como "negativos" cuando no fueron
    // pedidos. Cada entry: el slug del tag → tokens que validarían que el
    // usuario sí los pidió (en voz o en requiredTags) y patrones de texto que
    // delatan al factor como referido a ese tag.
    //
    // Lambdas explícitas (no tear-offs) para evitar quirks de Dart→JS en web.
    final userTags = profile.requiredTags.map((t) => t.toLowerCase()).toSet();
    bool userRequested(String tagKey, List<String> userSignals) {
      if (userTags.contains(tagKey)) return true;
      for (final s in userSignals) {
        if (transcriptHas(s)) return true;
      }
      return false;
    }

    // Cada tagRule: (label, userSignals, factorPatterns)
    // Si el factor contiene cualquier factorPattern Y el usuario no pidió
    // tagKey (ni vía requiredTags ni vía userSignals en transcript) → drop.
    final tagRules = <({
      String tag,
      List<String> userSignals,
      List<String> factorPatterns,
    })>[
      (
        tag: 'familia_segura',
        userSignals: [
          'familia',
          'segur',
          'hijos',
          'niños',
          'esposa',
          'zona segura',
          'zona tranquila',
          'seguridad'
        ],
        factorPatterns: [
          'familia segura',
          'familia_segura',
          'zona segura',
          'no es segur',
          'sin seguridad',
          'inseguro',
          'inseguridad',
          // Variantes "no cumple/se menciona/confirma" + token
          'no cumple con seguridad',
          'no cumple con familia',
          'no cumple con zona segura',
          'no cumple seguridad',
          'no se menciona seguridad',
          'no se menciona zona',
          'no confirma seguridad',
          'no confirma zona segura',
          'no confirma familia',
        ],
      ),
      (
        tag: 'jardin',
        userSignals: ['jardin', 'jardín'],
        factorPatterns: ['jardín', 'jardin', 'sin jardín', 'sin jardin'],
      ),
      (
        tag: 'piscina',
        userSignals: ['piscina', 'alberca'],
        factorPatterns: ['piscina', 'alberca', 'sin piscina'],
      ),
      (
        tag: 'vista',
        userSignals: ['vista', 'panorámica', 'panoramica'],
        factorPatterns: ['vista panorámica', 'vista panoramica', 'sin vista'],
      ),
      (
        tag: 'quincho',
        userSignals: ['quincho', 'parrilla', 'asador'],
        factorPatterns: ['quincho', 'sin quincho', 'parrilla', 'sin parrilla'],
      ),
      (
        tag: 'terraza',
        userSignals: ['terraza'],
        factorPatterns: ['terraza', 'sin terraza'],
      ),
      (
        tag: 'balcon',
        userSignals: ['balcon', 'balcón'],
        factorPatterns: ['balcón', 'balcon', 'sin balcón', 'sin balcon'],
      ),
      (
        tag: 'mascotas',
        userSignals: ['mascot', 'perro', 'gato'],
        factorPatterns: ['no acepta mascot', 'sin mascot', 'no mascot'],
      ),
    ];

    bool isHallucination(String factor) {
      final f = factor.toLowerCase();

      // "Sin/falta/no cumple/no se menciona... garaje/garage/parqueo/cochera"
      // cuando la property SÍ tiene parking. Cubre múltiples patrones que el
      // LLM usa intercambiables.
      const parkingTokens = ['garaje', 'garage', 'parqueo', 'cochera'];
      const parkingNegatives = [
        'sin ',
        'no tiene ',
        'falta ',
        'falta de ',
        'no cumple con ',
        'no cumple ',
        'no se menciona ',
        'no confirma ',
        'no hay ',
      ];
      if (property.parking > 0) {
        for (final tok in parkingTokens) {
          for (final neg in parkingNegatives) {
            if (f.contains('$neg$tok')) {
              debugPrint(
                '[Hito.Matching] dropped halluc factor for ${property.id}: '
                '"$factor" (parking=${property.parking})',
              );
              return true;
            }
          }
        }
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

      // Tags hallucinations — si el factor menciona un tag concreto y el
      // user no lo pidió, drop.
      for (final rule in tagRules) {
        var matchedPattern = false;
        for (final p in rule.factorPatterns) {
          if (f.contains(p)) {
            matchedPattern = true;
            break;
          }
        }
        if (matchedPattern && !userRequested(rule.tag, rule.userSignals)) {
          debugPrint(
            '[Hito.Matching] dropped halluc factor for ${property.id}: '
            '"$factor" (user did not request ${rule.tag})',
          );
          return true;
        }
      }

      // "Modalidad de transacción" — label feo del LLM
      if (f.contains('modalidad de transacción')) {
        return true;
      }

      // "No cumple con tags requeridos" / "no tiene tags solicitados" cuando
      // requiredTags está vacío — invención pura.
      if (profile.requiredTags.isEmpty &&
          (f.contains('tags requeridos') ||
              f.contains('tags solicitados') ||
              f.contains('tags pedidos'))) {
        debugPrint(
          '[Hito.Matching] dropped halluc factor for ${property.id}: '
          '"$factor" (user did not specify required tags)',
        );
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

    List<String> filter(List<String> xs) =>
        xs.where((f) => !isHallucination(f)).toList();

    return result.copyWith(
      recommended: filter(result.recommended),
      considerations: filter(result.considerations),
      risks: filter(result.risks),
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
    final matches = supports.contains(wantedNormalized);
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
            // 0.0 → la salida es lo más determinística posible para que dos
            // propiedades equivalentes reciban el mismo score base del LLM,
            // y el tiebreaker post-LLM se encargue de diferenciarlas por
            // hechos objetivos (año, área, parqueo, precio).
            temperature: 0.0,
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

  /// True si la propiedad satisface un required_tag del cliente. Mira
  /// `amenities` (slug real del listing) + atributos físicos (parking),
  /// no solo `cochabamba_tags` — que en el seed actual va vacío. Sin esto
  /// todo tag pedido ("garage", "patio") salía como faltante y hundía el
  /// score, y el LLM no veía el garaje (solo el conteo de parqueos).
  bool _propertySatisfiesTag(Property property, String tag) {
    if (tag == 'acepta_anticretico') return property.supportsAnticretico;
    if (property.cochabambaTags.contains(tag)) return true;
    final am = property.amenities;
    bool has(String s) => am.any((a) => a.contains(s));
    switch (tag) {
      case 'garage':
      case 'cochera':
        return property.parking > 0 || has('garage') || has('garaje');
      case 'patio':
      case 'jardin':
        return has('patio') || has('jardin');
      case 'vigilancia':
      case 'familia_segura':
      case 'zona_tranquila':
        return has('vigilancia');
      case 'piscina':
        return has('piscina');
      case 'terraza':
      case 'balcon':
        return has('terraza') || has('balcon');
      case 'quincho':
        return has('quincho') || has('parrillero');
      case 'vista_panoramica':
        return has('vista');
      default:
        return has(tag);
    }
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
    final priceLabel = switch (profile.transactionType) {
      'anticretico' => 'Capital anticrético',
      'alquiler' => 'Renta mensual',
      _ => 'Precio venta',
    };
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
        .where((t) => _propertySatisfiesTag(property, t))
        .toList();
    final tagsMissing = profile.requiredTags
        .where((t) => !_propertySatisfiesTag(property, t))
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
        '  - Baños: ${property.bathrooms}\n'
        '  - Parqueos: ${property.parking}${property.parking > 0 ? " (tiene garage/cochera)" : ""}\n'
        '  - Amenidades: ${property.amenities.isEmpty ? "n/a" : property.amenities.join(", ")}\n'
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
  ///
  /// Reglas alineadas con el LLM path:
  ///   - `radiusKm >= 50` es sentinel "sin preferencia de ubicación" → no
  ///     mencionamos distancia en factors ni penalizamos.
  ///   - 'compra' del cliente se normaliza a 'venta' antes de comparar con
  ///     supportedTransactions (son la misma operación buyer↔seller).
  ///   - effectivePriceBob se usa según la modalidad (sale/alquiler/anti).
  MatchResult _heuristicFallback({
    required ClientProfile profile,
    required Property property,
  }) {
    var score = 50;
    final positive = <String>[];
    final negative = <String>[];

    // Budget fit (35 puntos) — usa el precio efectivo según modalidad
    // (capital anticrético, renta mensual, o precio de venta).
    final effectivePrice =
        property.effectivePriceBob(profile.transactionType);
    if (effectivePrice > 0 && profile.budgetMax > 0) {
      if (effectivePrice >= profile.budgetMin &&
          effectivePrice <= profile.budgetMax) {
        score += 25;
        positive.add('Dentro de presupuesto');
      } else if (effectivePrice > profile.budgetMax) {
        final excessPct =
            ((effectivePrice - profile.budgetMax) / profile.budgetMax * 100)
                .round();
        score -= 30;
        negative.add('Excede presupuesto $excessPct%');
      } else {
        positive.add('Por debajo de presupuesto');
      }
    }

    // Bedrooms fit (15 puntos)
    if (property.bedrooms >= profile.minBedrooms) {
      score += 10;
      positive.add('${property.bedrooms} dormitorios');
    } else {
      score -= 25;
      negative.add('Solo ${property.bedrooms} dormitorios');
    }

    // Distance to desired location (25 puntos) — solo si user especificó zona
    final hasSpecificLocation = profile.radiusKm < 50;
    final dKm = hasSpecificLocation
        ? property.distanceToKm(profile.desiredLocation)
        : 0.0;
    if (hasSpecificLocation) {
      if (dKm <= profile.radiusKm) {
        score += 15;
        positive.add('A ${formatDistance(dKm)} de tu zona');
      } else {
        score -= ((dKm - profile.radiusKm) * 5).round().clamp(0, 25);
        negative.add('Lejos de tu zona (${formatDistance(dKm)})');
      }
    }

    // Transaction type (15 puntos) — normalizar compra↔venta antes de comparar
    final supports = property.supportedTransactions.isNotEmpty
        ? property.supportedTransactions
        : [property.listingMode];
    final wantedNormalized = profile.transactionType == 'compra'
        ? 'venta'
        : profile.transactionType;
    if (supports.contains(wantedNormalized)) {
      score += 10;
    } else {
      score -= 20;
      negative.add(
        'Modalidad ${profile.transactionType} no soportada',
      );
    }

    // Tags (10 puntos)
    final tagsMatched = <String>[];
    final tagsMissing = <String>[];
    for (final tag in profile.requiredTags) {
      if (_propertySatisfiesTag(property, tag)) {
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

    // Explicación honesta: cita la métrica relevante (distancia solo si hay).
    final explanation = hasSpecificLocation
        ? '$score% compatible (modo offline — IA no disponible). '
            'Score basado en presupuesto, dormitorios y distancia real '
            '(${formatDistance(dKm)}).'
        : '$score% compatible (modo offline — IA no disponible). '
            'Score basado en presupuesto y dormitorios.';

    // Heuristic fallback emite solo recommended + risks (sin considerations,
    // que requieren juicio del LLM). El "+ A 2km de zona" va en recommended,
    // "Excede presupuesto" en risks, etc.
    return MatchResult(
      propertyId: property.id,
      clientProfileId: profile.id,
      compatibilityPercent: score,
      explanation: explanation,
      recommended: positive.take(3).toList(),
      considerations: const [],
      risks: negative.take(3).toList(),
      tagsMatched: tagsMatched,
      tagsMissing: tagsMissing,
    );
  }
}
