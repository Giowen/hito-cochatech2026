/// ValuationReport — output de valuation_service para una propiedad.
/// Spec en PRD §6.
class ValuationReport {
  final String propertyId;
  final int estimatedValueBob;
  final int listedValueBob;
  final double deltaPercent; // negativo = sobrevalorado, positivo = subvalorado
  final int estimatedValueUsdParalelo;
  final double usdParaleloRateUsed; // BOB por USD paralelo
  final List<String> comparables; // property_ids
  final double confidenceScore; // 0-1
  final String recommendationForAgent;
  final String recommendationForClient;
  final String reasoning;

  const ValuationReport({
    required this.propertyId,
    required this.estimatedValueBob,
    required this.listedValueBob,
    required this.deltaPercent,
    required this.estimatedValueUsdParalelo,
    required this.usdParaleloRateUsed,
    required this.comparables,
    required this.confidenceScore,
    required this.recommendationForAgent,
    required this.recommendationForClient,
    required this.reasoning,
  });

  /// Etiqueta para la UI (PRD §3.2):
  /// delta < -5% sobrevalorada, > 5% subvalorada, en medio "a precio".
  String get label {
    if (deltaPercent < -5) return 'Sobrevalorada';
    if (deltaPercent > 5) return 'Subvalorada';
    return 'A precio';
  }

  factory ValuationReport.fromJson(Map<String, dynamic> json) {
    return ValuationReport(
      propertyId: json['property_id'] as String? ?? '',
      estimatedValueBob: json['estimated_value_bob'] as int,
      listedValueBob: json['listed_value_bob'] as int? ?? 0,
      deltaPercent: (json['delta_percent'] as num? ?? 0).toDouble(),
      estimatedValueUsdParalelo:
          json['estimated_value_usd_paralelo'] as int? ?? 0,
      usdParaleloRateUsed:
          (json['usd_paralelo_rate_used'] as num? ?? 12.5).toDouble(),
      comparables: (json['comparables'] as List? ?? []).cast<String>(),
      confidenceScore: (json['confidence_score'] as num? ?? 0.7).toDouble(),
      recommendationForAgent: json['recommendation_for_agent'] as String? ?? '',
      recommendationForClient: json['recommendation_for_client'] as String? ?? '',
      reasoning: json['reasoning'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'property_id': propertyId,
        'estimated_value_bob': estimatedValueBob,
        'listed_value_bob': listedValueBob,
        'delta_percent': deltaPercent,
        'estimated_value_usd_paralelo': estimatedValueUsdParalelo,
        'usd_paralelo_rate_used': usdParaleloRateUsed,
        'comparables': comparables,
        'confidence_score': confidenceScore,
        'recommendation_for_agent': recommendationForAgent,
        'recommendation_for_client': recommendationForClient,
        'reasoning': reasoning,
      };
}
