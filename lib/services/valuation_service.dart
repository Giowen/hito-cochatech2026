import 'dart:convert';
import '../models/property.dart';
import '../models/valuation_report.dart';
import '../utils/tc_paralelo.dart';
import 'groq_client.dart';

/// ValuationService — valuación dinámica AI ajustada por TC paralelo.
///
/// Demo path: hardcoded canonical (Av. Pando $232K mid, subvalorada 7.9% vs $215K
/// listed). Factors ponderados + 5 comparables vendidos en 90 días.
/// LLM path: prompt PRD §16.2 con Groq Llama 3.3 70B.
///
/// Repository hook: cuando Drift+Supabase entre en Phase 2, los comparables se
/// fetchearán desde MLS+DDRR vía repository, no se hardcodearán.
class ValuationService {
  final GroqClient _groqClient;

  ValuationService({GroqClient? groqClient})
      : _groqClient = groqClient ?? GroqClient();

  /// Demo valuations alineadas con AI_VALUATION + COMPARABLES del claude-design.
  static const Map<String, _DemoValuation> _demoValuations = {
    // p01 — Casa familiar Av. Pando, Cala Cala (STAR del demo)
    'p01': _DemoValuation(
      estimatedUsdLow: 198000,
      estimatedUsdMid: 232000,
      estimatedUsdHigh: 248000,
      confidence: 0.87,
      // p03 (Casa con jardín Ladislao Cabrera) está en listings y matchea c4
      comparableListingIds: ['p03'],
      comparableDetails: [
        'A · Av. América #1842 · 265m² · 4d · \$228k · Vendida Mar 2026',
        'B · Calle Loa #34 · 290m² · 4d · \$245k · Vendida Feb 2026',
        'C · Av. Pando #220 · 270m² · 4d · \$219k · Vendida Ene 2026',
        'D · Ladislao Cabrera · 285m² · 5d · \$238k · Vendida Dic 2025',
        'E · Av. Heroínas #1502 · 250m² · 4d · \$224k · Activa 7 días',
      ],
      factors: [
        '+8.2% Ubicación (Cala Cala)',
        '+12.4% Área construida (280 m²)',
        '+4.1% Año 2018 (relativamente nuevo)',
        '+6.8% Lote 320 m² con patio',
        '−3.2% Acabados estándar (no premium)',
        '−1.9% Av. Pando — tráfico medio',
        '+5.1% Tendencia barrio +6.4% / 12m',
      ],
      forAgent:
          'Esta propiedad está \$17k USD por debajo del valor de mercado. El propietario muestra urgencia. Sugerimos no presionar precio; cerrar rápido antes de que se sume la plusvalía del barrio (+6.4%/año).',
      forClient:
          'Excelente oportunidad: estás comprando \$17k USD por debajo del mercado. Cala Cala sube 6.4%/año en promedio — esto es upside garantizado a 12 meses. Si tienes dudas, ofrece \$210k y consolidás el deal.',
      reasoning:
          'Mid de 5 comparables vendidos últimos 90 días en Cala Cala: \$230k USD. Ajustado por TC paralelo 12.20 Bs/USD. Confidence 87% (8 muestras válidas en radio 500m).',
    ),
    // p02 — Departamento Recoleta
    'p02': _DemoValuation(
      estimatedUsdLow: 165000,
      estimatedUsdMid: 184000,
      estimatedUsdHigh: 198000,
      confidence: 0.81,
      comparableListingIds: [],
      comparableDetails: [
        'F · Recoleta Tower piso 12 · 170m² · 3d · \$192k · Vendida Feb 2026',
        'G · Edif. Mirador · 160m² · 3d · \$178k · Vendida Ene 2026',
      ],
      factors: [
        '+6.5% Vista panorámica piso 8',
        '+4.2% Edificio 2022 (3 años)',
        '−2.1% Sin patio',
      ],
      forAgent:
          'Precio competitivo. Mantén en \$178k, está al precio de mercado.',
      forClient:
          'Precio justo. Margen de negociación bajo (3-4%) — el deal está bien para ti.',
      reasoning:
          'Departamentos similares en Recoleta promedian \$184k USD. Confidence 81%.',
    ),
    // p03 — Casa con jardín Queru Queru
    'p03': _DemoValuation(
      estimatedUsdLow: 188000,
      estimatedUsdMid: 205000,
      estimatedUsdHigh: 218000,
      confidence: 0.84,
      comparableListingIds: ['p11'],
      comparableDetails: [
        'H · Av. Lanza · 235m² · 4d · \$201k · Vendida Mar 2026',
        'I · Mariscal Sucre #45 · 245m² · 4d · \$210k · Vendida Feb 2026',
      ],
      factors: [
        '+5.4% Calle sin salida (tranquilo)',
        '+3.8% Lote 380 m² (sobre área de zona)',
        '−2.0% Año 2015 (no nuevo)',
      ],
      forAgent: 'Al precio. Justifica los \$195k con la calle privada y patio amplio.',
      forClient: 'Subvalorado ~5%. Margen para negociar \$5-10k abajo.',
      reasoning: 'Queru Queru comparables \$200-210k USD. Calle sin salida añade +5%.',
    ),
  };

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
    final estimatedBob = TcParalelo.usdToBob(demo.estimatedUsdMid);
    final listedBob = property.priceBob > 0
        ? property.priceBob
        : TcParalelo.usdToBob(property.priceUsdParalelo);
    final delta = listedBob > 0
        ? ((estimatedBob - listedBob) / listedBob) * 100
        : 0.0;

    return ValuationReport(
      propertyId: property.id,
      estimatedValueBob: estimatedBob,
      listedValueBob: listedBob,
      deltaPercent: delta,
      estimatedValueUsdParalelo: demo.estimatedUsdMid,
      usdParaleloRateUsed: TcParalelo.rate,
      comparables: demo.comparableListingIds,
      confidenceScore: demo.confidence,
      recommendationForAgent: demo.forAgent,
      recommendationForClient: demo.forClient,
      reasoning: demo.reasoning,
      estimatedValueUsdLow: demo.estimatedUsdLow,
      estimatedValueUsdHigh: demo.estimatedUsdHigh,
      factors: demo.factors,
      comparableDetails: demo.comparableDetails,
    );
  }

  Future<ValuationReport> _llmValuation(
    Property property,
    List<Property> allProperties,
  ) async {
    final comparables = _pickComparables(property, allProperties);

    const systemPrompt = '''
Eres un tasador inmobiliario boliviano con 20 años de experiencia en Cochabamba,
especializado en el mercado 2025-2026 con su crisis cambiaria.

Considera SIEMPRE:
- Tipo de cambio paralelo USD/Bs (asumir 12.20 Bs por USD vs 6.96 oficial)
- Tendencia de costos de construcción al alza
- Inflación zonal y plusvalía del barrio

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
  final int estimatedUsdLow;
  final int estimatedUsdMid;
  final int estimatedUsdHigh;
  final double confidence;
  final List<String> comparableListingIds;
  final List<String> comparableDetails;
  final List<String> factors;
  final String forAgent;
  final String forClient;
  final String reasoning;

  const _DemoValuation({
    required this.estimatedUsdLow,
    required this.estimatedUsdMid,
    required this.estimatedUsdHigh,
    required this.confidence,
    required this.comparableListingIds,
    required this.comparableDetails,
    required this.factors,
    required this.forAgent,
    required this.forClient,
    required this.reasoning,
  });
}
