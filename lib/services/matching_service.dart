import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/client_profile.dart';
import '../models/match_result.dart';
import '../models/property.dart';
import 'groq_client.dart';

/// MatchingService — scorea propiedades contra ClientProfile.
///
/// Demo path (default): usa property.compatibility (pre-computed) y property.aiNotes
/// para garantizar reproducibilidad. Cero latencia, cero costo, cero variabilidad.
/// Real LLM path: invoca Groq Llama 3.3 70B con prompt PRD §16.1.
///
/// Repository hook: cuando Phase 2 (Drift+Supabase) entre, este service consume
/// PropertyRepository en vez de rootBundle directamente — sin tocar el resto del flujo.
class MatchingService {
  final GroqClient _groqClient;

  MatchingService({GroqClient? groqClient})
      : _groqClient = groqClient ?? GroqClient();

  /// Carga 12 propiedades canónicas desde assets/seed/properties.json.
  /// TODO Phase 2: reemplazar por PropertyRepository (in-memory → Drift+Supabase sync).
  Future<List<Property>> loadProperties() async {
    final jsonString =
        await rootBundle.loadString('assets/seed/properties.json');
    final list = jsonDecode(jsonString) as List;
    return list
        .map((j) => Property.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Score property vía LLM real (Groq Llama 3.3 70B), prompt PRD §16.1.
  Future<MatchResult> scoreWithLlm({
    required ClientProfile profile,
    required Property property,
  }) async {
    const systemPrompt = '''
Eres un asistente experto en bienes raíces bolivianos. Tu trabajo es evaluar qué tan bien una propiedad coincide con las preferencias de un cliente boliviano.

Factores principales:
- Fit de presupuesto (BOB y USD paralelo).
- Distancia a ubicación deseada (oficina, colegios).
- Modalidad (compra, alquiler, anticretico) — si coincide o no.
- Características: dormitorios, área, parqueo, patio, año de construcción.
- Tags requeridos por el cliente (patio, familia_segura, cerca_recoleta, etc.).

Devuelve JSON estricto:
{
  "compatibility_percent": int 0-100,
  "explanation": string corta (max 60 palabras),
  "tags_matched": [strings],
  "tags_missing": [strings],
  "positive_factors": [strings],
  "negative_factors": [strings]
}
''';

    final userPrompt =
        'Perfil del cliente: ${jsonEncode(profile.toJson())}\n'
        'Propiedad a evaluar: ${jsonEncode(property.toJson())}';

    final response = await _groqClient.chat(
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      temperature: 0.3,
      responseFormat: {'type': 'json_object'},
    );

    final json = GroqClient.extractJson(response);
    if (json == null) {
      throw Exception('Failed to parse JSON from Groq response: $response');
    }

    return MatchResult.fromJson({
      ...json,
      'property_id': property.id,
      'client_profile_id': profile.id,
    });
  }

  /// Score property con valores hardcoded del seed — garantiza demo path.
  /// Compatibility y aiNotes provienen del Property mismo (claude-design canonical).
  MatchResult scoreHardcoded({
    required ClientProfile profile,
    required Property property,
  }) {
    final compatibility = property.compatibility ?? 30;
    final explanation = property.aiNotes.isNotEmpty
        ? property.aiNotes.join(' ')
        : 'Match basado en presupuesto, ubicación y características. '
            'Score: $compatibility%.';

    final positive = <String>[];
    final negative = <String>[];

    if (property.priceBob > 0 &&
        property.priceBob >= profile.budgetMin &&
        property.priceBob <= profile.budgetMax) {
      positive.add('Dentro de presupuesto');
    } else if (property.priceBob > profile.budgetMax) {
      negative.add('Excede presupuesto');
    } else if (property.priceBob > 0 && property.priceBob < profile.budgetMin) {
      positive.add('Por debajo de presupuesto');
    }

    if (property.bedrooms >= profile.minBedrooms) {
      positive.add('${property.bedrooms} dormitorios');
    } else {
      negative.add('Solo ${property.bedrooms} dormitorios');
    }

    if (property.areaM2 >= profile.minAreaM2) {
      positive.add('${property.areaM2} m² construidos');
    }

    if (property.parking >= 1) {
      positive.add('${property.parking} parqueo${property.parking > 1 ? "s" : ""}');
    } else {
      negative.add('Sin parqueo');
    }

    // Anticrético interest match
    if (profile.requiredTags.contains('acepta_anticretico') &&
        !property.supportsAnticretico) {
      negative.add('No admite anticrético');
    } else if (profile.requiredTags.contains('acepta_anticretico') &&
        property.supportsAnticretico) {
      positive.add('Disponible en anticrético');
    }

    return MatchResult(
      propertyId: property.id,
      clientProfileId: profile.id,
      compatibilityPercent: compatibility,
      explanation: explanation,
      positiveFactors: positive,
      negativeFactors: negative,
      tagsMatched: const [],
      tagsMissing: const [],
    );
  }

  /// API pública. Usa hardcoded path si property tiene compatibility pre-computed.
  Future<MatchResult> score({
    required ClientProfile profile,
    required Property property,
    bool useDemoPath = true,
  }) async {
    if (useDemoPath && property.compatibility != null) {
      return scoreHardcoded(profile: profile, property: property);
    }
    return scoreWithLlm(profile: profile, property: property);
  }

  /// Score todas las propiedades, retorna lista ordenada por compatibility desc.
  Future<List<MatchResult>> scoreAll({
    required ClientProfile profile,
    required List<Property> properties,
    bool useDemoPath = true,
  }) async {
    final results = await Future.wait(
      properties.map(
        (p) => score(profile: profile, property: p, useDemoPath: useDemoPath),
      ),
    );
    results.sort(
      (a, b) => b.compatibilityPercent.compareTo(a.compatibilityPercent),
    );
    return results;
  }

  /// Streaming de explanation token-by-token para UI tipo AI-typing.
  /// Demo path: simula streaming desde property.aiNotes (consistencia, sin red).
  /// LLM mode: usa Groq streaming real.
  Stream<String> explainStreaming({
    required ClientProfile profile,
    required Property property,
    bool useDemoPath = true,
  }) async* {
    if (useDemoPath && property.aiNotes.isNotEmpty) {
      final compat = property.compatibility ?? 0;
      final intro = '$compat% compatible contigo. ';
      final body = property.aiNotes.join(' ');
      final fullText = '$intro$body';
      // Stream char-by-char con delay 8ms — feel auténtico de LLM streaming
      for (var i = 0; i < fullText.length; i++) {
        await Future.delayed(const Duration(milliseconds: 8));
        yield fullText[i];
      }
      return;
    }

    const systemPrompt = '''
Eres un asistente inmobiliario boliviano. Explica en máximo 50 palabras por qué esta propiedad matchea (o no) con el cliente. Sé concreto y conversacional. Empieza con "X% compatible contigo:" donde X es el porcentaje.
''';

    final userPrompt =
        'Cliente: ${jsonEncode(profile.toJson())}\n'
        'Propiedad: ${jsonEncode(property.toJson())}';

    yield* _groqClient.chatStream(
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
    );
  }
}
