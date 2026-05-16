import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/client_profile.dart';
import '../models/match_result.dart';
import '../models/property.dart';
import '../repositories/match_cache_repository.dart';
import '../utils/distance.dart';
import '../utils/landmarks.dart';
import 'groq_client.dart';

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

  MatchingService({
    GroqClient? groqClient,
    MatchCacheRepository? cache,
  })  : _groqClient = groqClient ?? GroqClient(),
        _cache = cache ?? NoOpMatchCacheRepository();

  // ── System prompt PRD §16.1 ampliado con distancias reales ─────────────
  static const _systemPrompt = '''
Eres un asistente experto en bienes raíces de Cochabamba, Bolivia.

Evalúa qué tan bien una propiedad coincide con las preferencias del cliente.

PESOS (suma ~100):
- Presupuesto (35%): si el precio excede el budget_max → penaliza fuerte (-30 a -50 puntos).
- Distancia (25%): usa los km a landmarks (UMSS, UPB, UCB, Recoleta, Centro).
  Si el cliente menciona "cerca de X" o tiene oficina en X, valora <2 km.
- Modalidad de transacción (15%): si pide "compra" y la propiedad solo es
  "anticretico" → -40 puntos. Si soporta múltiples modalidades coincidentes → +.
- Bedrooms + área m² (15%): si pide 10 dormitorios y hay 4, el score debe
  ser 25-40%, NUNCA 80%. Sé honesto.
- Tags (10%): patio, familia_segura, cerca_recoleta, parqueo, etc.

REGLAS DE HONESTIDAD:
- Si la propiedad no cumple un requisito fundamental, el score debe bajar
  consistentemente. Nunca infles para mostrar opciones.
- Si excede el inventario disponible (ej. cliente pide características
  irrealistas para Cochabamba), refleja esa realidad en `explanation`.

Devuelve JSON estricto en español:
{
  "compatibility_percent": int 0-100,
  "explanation": string conversacional max 60 palabras,
  "tags_matched": [string array],
  "tags_missing": [string array],
  "positive_factors": [string array, máximo 3],
  "negative_factors": [string array, máximo 3]
}

NO incluyas markdown ni texto fuera del JSON.
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
        return cached.copyWith(clientProfileId: profile.id);
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

  /// Score N propiedades en paralelo, ordenadas por compatibility desc.
  Future<List<MatchResult>> scoreAll({
    required ClientProfile profile,
    required List<Property> properties,
    bool useCache = true,
  }) async {
    final results = await Future.wait(
      properties.map(
        (p) => score(profile: profile, property: p, useCache: useCache),
      ),
    );
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

    final raw = await _groqClient.chat(
      messages: [
        const {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      temperature: 0.2,
      responseFormat: {'type': 'json_object'},
    );

    final json = GroqClient.extractJson(raw);
    if (json == null) {
      throw FormatException('Groq returned non-JSON: $raw');
    }

    return MatchResult.fromJson({
      ...json,
      'property_id': property.id,
      'client_profile_id': profile.id,
    });
  }

  /// Construye el bloque de contexto de la propiedad incluyendo distancias
  /// reales (Haversine) a landmarks principales + distancia a la ubicación
  /// deseada del cliente. El LLM razona sobre esos números explícitos.
  String _buildPropertyContext(ClientProfile profile, Property property) {
    final propJson = property.toJson();
    final landmarkDistances = property.distancesToLandmarks;
    final distanceToDesired =
        property.distanceToKm(profile.desiredLocation);

    final landmarkLines = Landmarks.matchingContext.map((l) {
      final km = landmarkDistances[l.slug]!;
      return '  - ${l.displayName}: ${formatDistance(km)}';
    }).join('\n');

    return '${jsonEncode(propJson)}\n\n'
        'Distancia a ubicación deseada del cliente: '
        '${formatDistance(distanceToDesired)}\n'
        'Distancias a landmarks principales:\n$landmarkLines';
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
