import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/client_profile.dart';
import '../models/match_result.dart';
import '../models/property.dart';
import 'groq_client.dart';

/// MatchingService — scorea propiedades contra ClientProfile.
///
/// Modo "demo path" (default): retorna hardcoded compatibility para garantizar
/// reproducibilidad del demo (Sucre #234 siempre 92%, etc.).
/// Modo "real LLM": llama Groq Llama 3.3 70B con prompt PRD §16.1.
class MatchingService {
  final GroqClient _groqClient;

  MatchingService({GroqClient? groqClient})
      : _groqClient = groqClient ?? GroqClient();

  /// Compatibility hardcoded por property_id para demo path.
  /// Distribución alineada con PITCH_PREP §3 — Sucre #234 estrella 92%.
  static const Map<String, int> demoCompatibility = {
    'sucre-234': 92,
    'america-1100': 78,
    'jordan-560': 65,
    'sanpedro-45': 54,
    'calatayud-210': 47,
    'calacala-890': 45,
    'villagranado-15': 42,
    'pacataalta-501': 40,
    'queruqueru-88': 38,
    'pacatabaja-340': 36,
    'tupuraya-75': 35,
    'sacaba-100': 30,
    'tiquipaya-45': 28,
    'quillacollo-200': 27,
    'sipesipe-5': 25,
  };

  /// Explanations hardcoded para top properties del demo path.
  /// Garantiza que el streaming siempre dice lo mismo, alineado con PITCH_PREP §2.
  static const Map<String, String> demoExplanations = {
    'sucre-234':
        '92% compatible contigo. Cumple presupuesto, a 8 minutos caminando de UMSS, acepta mascotas, en zona con vigilancia 24 horas. Tiene jardín y garage para un auto. El match más fuerte con tu perfil.',
    'america-1100':
        '78% compatible. Buena casa con tu presupuesto, acepta mascotas y tiene parqueo. Sin embargo, está lejos de UMSS (más de 4 kilómetros) lo que aumenta el tiempo de transporte.',
    'jordan-560':
        '65% compatible. Ubicación excelente: cerca de UMSS y centro. Tiene cochera para dos autos. Sobre tu presupuesto en aproximadamente 80 mil bolivianos.',
    'sanpedro-45':
        '54% compatible. Casa económica en zona segura. Sin parqueo y sin acepta_mascotas explícito. Solo dos dormitorios, bajo el mínimo de tres que pediste.',
  };

  /// Carga 15 propiedades hardcoded desde assets/seed/properties.json.
  Future<List<Property>> loadProperties() async {
    final jsonString =
        await rootBundle.loadString('assets/seed/properties.json');
    final list = jsonDecode(jsonString) as List;
    return list
        .map((j) => Property.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Score property con LLM real (Groq Llama 3.3 70B).
  /// Spec del prompt en PRD §16.1.
  Future<MatchResult> scoreWithLlm({
    required ClientProfile profile,
    required Property property,
  }) async {
    const systemPrompt = '''
Eres un asistente experto en bienes raíces bolivianos. Tu trabajo es evaluar qué tan bien una propiedad coincide con las preferencias de un cliente.

Considera los siguientes tags Cochabamba como factores de match:
- Proximidad a universidades (UMSS, UMSFX, UPB, UCB)
- Mascotas (acepta_mascotas)
- Parqueo (tiene_parqueo, cochera_2_autos)
- Seguridad (zona_segura, vigilancia_24h)
- Transporte (transporte_publico_5min, cerca_centro)
- Servicios (escuela_publica_cerca, hospital_cerca, mercado_cerca)

Devuelve JSON estricto:
{
  "compatibility_percent": int 0-100,
  "explanation": string corta (max 60 palabras),
  "tags_matched": [strings],
  "tags_missing": [strings],
  "positive_factors": [strings],
  "negative_factors": [strings]
}

Calcula match basándote en: fit presupuesto, distancia a ubicación deseada, tags cumplidos, fit features.
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

  /// Score property con hardcoded values — usado en demo path para consistencia.
  MatchResult scoreHardcoded({
    required ClientProfile profile,
    required Property property,
  }) {
    final compatibility = demoCompatibility[property.id] ?? 30;
    final explanation = demoExplanations[property.id] ??
        'Match basado en presupuesto, ubicación y tags. Score: $compatibility%.';

    final tagsMatched = property.cochabambaTags
        .where((t) => profile.requiredTags.contains(t))
        .toList();
    final tagsMissing = profile.requiredTags
        .where((t) => !property.cochabambaTags.contains(t))
        .toList();

    final positive = <String>[];
    final negative = <String>[];

    if (property.priceBob >= profile.budgetMin &&
        property.priceBob <= profile.budgetMax) {
      positive.add('Dentro de presupuesto');
    } else if (property.priceBob > profile.budgetMax) {
      negative.add('Sobre presupuesto');
    } else {
      positive.add('Bajo presupuesto');
    }

    if (property.bedrooms >= profile.minBedrooms) {
      positive.add('${property.bedrooms} dormitorios');
    } else {
      negative.add('Solo ${property.bedrooms} dormitorios');
    }

    if (property.listingMode != profile.transactionType) {
      negative.add('Modalidad ${property.listingMode} vs ${profile.transactionType}');
    }

    return MatchResult(
      propertyId: property.id,
      clientProfileId: profile.id,
      compatibilityPercent: compatibility,
      explanation: explanation,
      positiveFactors: positive,
      negativeFactors: negative,
      tagsMatched: tagsMatched,
      tagsMissing: tagsMissing,
    );
  }

  /// API pública. Usa hardcoded para demo path properties, LLM para el resto.
  Future<MatchResult> score({
    required ClientProfile profile,
    required Property property,
    bool useDemoPath = true,
  }) async {
    if (useDemoPath && demoCompatibility.containsKey(property.id)) {
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
  /// En demo path simula streaming desde texto hardcoded (consistencia).
  /// En LLM mode usa Groq streaming real.
  Stream<String> explainStreaming({
    required ClientProfile profile,
    required Property property,
    bool useDemoPath = true,
  }) async* {
    if (useDemoPath && demoExplanations.containsKey(property.id)) {
      final explanation = demoExplanations[property.id]!;
      // Stream char-by-char con delay 8ms — feel auténtico de LLM streaming
      for (var i = 0; i < explanation.length; i++) {
        await Future.delayed(const Duration(milliseconds: 8));
        yield explanation[i];
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
