import 'dart:convert';
import '../models/property.dart';
import '../models/valuation_report.dart';
import '../utils/tc_paralelo.dart';
import 'groq_client.dart';

/// ValuationService — calcula valuación dinámica con AI ajustada por TC paralelo.
///
/// Demo path: hardcoded para Sucre #234 (770K Bs, sobrevalorada 10.4%) y otras.
/// LLM path: prompt PRD §16.2 con Groq Llama 3.3 70B.
class ValuationService {
  final GroqClient _groqClient;

  ValuationService({GroqClient? groqClient})
      : _groqClient = groqClient ?? GroqClient();

  /// Hardcoded valuations para demo path.
  static const Map<String, _DemoValuation> _demoValuations = {
    'sucre-234': _DemoValuation(
      estimatedBob: 770000,
      comparableIds: ['jordan-560', 'tupuraya-75', 'america-1100', 'calacala-890'],
      forAgent:
          'Ajusta precio a 780-800K Bs para venta rápida. El mercado de la zona acepta hasta 800K, pero 850K espanta a buyers como Juan.',
      forClient:
          'Puedes negociar hasta 80 mil bolivianos sobre el precio listado. La propiedad está sobrevalorada 10.4% según comparables ajustados por TC paralelo.',
      reasoning:
          'Comparables en radio 500m promedian 780K Bs. Ajustado por TC paralelo 12.5 Bs/USD (vs 6.96 oficial).',
    ),
    'america-1100': _DemoValuation(
      estimatedBob: 720000,
      comparableIds: ['tupuraya-75', 'queruqueru-88', 'villagranado-15'],
      forAgent: 'Precio competitivo. Mantén en 750K Bs, está al precio de mercado.',
      forClient: 'Precio justo. Margen de negociación bajo (3-4%).',
      reasoning: 'Comparables en zona norte promedian 720K Bs.',
    ),
    'jordan-560': _DemoValuation(
      estimatedBob: 880000,
      comparableIds: ['queruqueru-88', 'sucre-234', 'tupuraya-75'],
      forAgent: 'Buen precio. Justifica el 920K con la ubicación premium.',
      forClient: 'Sobrevalorada ~4%. Pequeña negociación posible.',
      reasoning: 'Cerca de centro y UMSS, comparables similares 860-900K.',
    ),
  };

  /// Valuación pública. Usa hardcoded para demo path properties, LLM para el resto.
  Future<ValuationReport> valuate({
    required Property property,
    required List<Property> allProperties,
    bool useDemoPath = true,
  }) async {
    if (useDemoPath && _demoValuations.containsKey(property.id)) {
      return _hardcodedValuation(property);
    }
    return _llmValuation(property, allProperties);
  }

  ValuationReport _hardcodedValuation(Property property) {
    final demo = _demoValuations[property.id]!;
    final delta =
        ((demo.estimatedBob - property.priceBob) / property.priceBob) * 100;
    return ValuationReport(
      propertyId: property.id,
      estimatedValueBob: demo.estimatedBob,
      listedValueBob: property.priceBob,
      deltaPercent: delta,
      estimatedValueUsdParalelo: TcParalelo.bobToUsd(demo.estimatedBob),
      usdParaleloRateUsed: TcParalelo.rate,
      comparables: demo.comparableIds,
      confidenceScore: 0.82,
      recommendationForAgent: demo.forAgent,
      recommendationForClient: demo.forClient,
      reasoning: demo.reasoning,
    );
  }

  Future<ValuationReport> _llmValuation(
    Property property,
    List<Property> allProperties,
  ) async {
    // Comparables: 4-5 propiedades del mismo tipo en radio razonable
    final comparables = _pickComparables(property, allProperties);

    const systemPrompt = '''
Eres un tasador inmobiliario boliviano con 20 años de experiencia en Cochabamba,
especializado en el mercado 2025-2026 con su crisis cambiaria.

Considera SIEMPRE:
- Tipo de cambio paralelo USD/Bs (asumir 12.5 Bs por USD vs 6.96 oficial)
- Tendencia de costos de construcción al alza
- Inflación zonal

Devuelve JSON estricto:
{
  "estimated_value_bob": int,
  "confidence_score": float 0-1,
  "recommendation_for_agent": string,
  "recommendation_for_client": string,
  "reasoning": string corto
}

Estima valor justo de mercado considerando comparables, TC paralelo, y tendencias zonales típicas de Cochabamba 2026.
''';

    final userPrompt = 'Propiedad a valuar: ${jsonEncode(property.toJson())}\n'
        'Comparables en radio cercano: ${jsonEncode(comparables.map((p) => p.toJson()).toList())}\n'
        'TC paralelo asumido: ${TcParalelo.rate}';

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
      throw Exception('Failed to parse JSON from Groq valuation: $response');
    }

    final estimatedBob = json['estimated_value_bob'] as int;
    final delta =
        ((estimatedBob - property.priceBob) / property.priceBob) * 100;

    return ValuationReport(
      propertyId: property.id,
      estimatedValueBob: estimatedBob,
      listedValueBob: property.priceBob,
      deltaPercent: delta,
      estimatedValueUsdParalelo: TcParalelo.bobToUsd(estimatedBob),
      usdParaleloRateUsed: TcParalelo.rate,
      comparables: comparables.map((p) => p.id).toList(),
      confidenceScore: (json['confidence_score'] as num? ?? 0.7).toDouble(),
      recommendationForAgent: json['recommendation_for_agent'] as String,
      recommendationForClient: json['recommendation_for_client'] as String,
      reasoning: json['reasoning'] as String? ?? '',
    );
  }

  /// Selecciona ~4 comparables del mismo tipo más cercanos en precio.
  List<Property> _pickComparables(Property target, List<Property> all) {
    final sameType = all
        .where((p) => p.id != target.id && p.type == target.type)
        .toList();
    sameType.sort((a, b) =>
        (a.priceBob - target.priceBob).abs().compareTo(
              (b.priceBob - target.priceBob).abs(),
            ));
    return sameType.take(4).toList();
  }
}

class _DemoValuation {
  final int estimatedBob;
  final List<String> comparableIds;
  final String forAgent;
  final String forClient;
  final String reasoning;

  const _DemoValuation({
    required this.estimatedBob,
    required this.comparableIds,
    required this.forAgent,
    required this.forClient,
    required this.reasoning,
  });
}
