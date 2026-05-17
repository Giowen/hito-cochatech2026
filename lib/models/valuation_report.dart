/// ValuationReport — output de valuation_service para una propiedad.
/// Spec en PRD §6, extendido con claude-design canonical fields (low/mid/high
/// range, factors ponderados, comparable details).
class ValuationReport {
  final String propertyId;
  final int estimatedValueBob;
  final int listedValueBob;
  final double deltaPercent; // negativo = sobrevalorado, positivo = subvalorado
  final int estimatedValueUsdParalelo;
  final double usdParaleloRateUsed; // BOB por USD paralelo
  final List<String> comparables; // property_ids (si están en listings activos)
  final double confidenceScore; // 0-1
  final String recommendationForAgent;
  final String recommendationForClient;
  final String reasoning;

  // ── Claude-design canonical fields ────────────────────────
  /// Estimación rango bajo (USD paralelo) — el mínimo del intervalo de confianza.
  final int? estimatedValueUsdLow;

  /// Estimación rango alto (USD paralelo) — el máximo del intervalo.
  final int? estimatedValueUsdHigh;

  /// Factores ponderados pre-formateados (e.g. "+8.2% Ubicación (Cala Cala)").
  final List<String> factors;

  /// Lista de comparables formateados para display
  /// (e.g. "A · Av. América 1842 · 265m² · $228K · Vendida Mar 2026").
  final List<String> comparableDetails;

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
    this.estimatedValueUsdLow,
    this.estimatedValueUsdHigh,
    this.factors = const [],
    this.comparableDetails = const [],
  });

  /// Etiqueta para la UI (PRD §3.2):
  /// delta < -5% sobrevalorada, > 5% subvalorada, en medio "a precio".
  String get label {
    if (deltaPercent < -5) return 'Sobrevalorada';
    if (deltaPercent > 5) return 'Subvalorada';
    return 'A precio';
  }

  factory ValuationReport.fromJson(Map<String, dynamic> json) {
    int? asInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return null;
    }

    return ValuationReport(
      propertyId: json['property_id'] as String? ?? '',
      estimatedValueBob: asInt(json['estimated_value_bob']) ?? 0,
      listedValueBob: asInt(json['listed_value_bob']) ?? 0,
      deltaPercent: (json['delta_percent'] as num? ?? 0).toDouble(),
      estimatedValueUsdParalelo:
          asInt(json['estimated_value_usd_paralelo']) ?? 0,
      usdParaleloRateUsed:
          (json['usd_paralelo_rate_used'] as num? ?? 12.5).toDouble(),
      comparables: (json['comparables'] as List? ?? const []).cast<String>(),
      confidenceScore: (json['confidence_score'] as num? ?? 0.7).toDouble(),
      recommendationForAgent:
          json['recommendation_for_agent'] as String? ?? '',
      recommendationForClient:
          json['recommendation_for_client'] as String? ?? '',
      reasoning: json['reasoning'] as String? ?? '',
      estimatedValueUsdLow: asInt(json['estimated_value_usd_low']),
      estimatedValueUsdHigh: asInt(json['estimated_value_usd_high']),
      factors: (json['factors'] as List? ?? const []).cast<String>(),
      comparableDetails:
          (json['comparable_details'] as List? ?? const []).cast<String>(),
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
        if (estimatedValueUsdLow != null)
          'estimated_value_usd_low': estimatedValueUsdLow,
        if (estimatedValueUsdHigh != null)
          'estimated_value_usd_high': estimatedValueUsdHigh,
        'factors': factors,
        'comparable_details': comparableDetails,
      };
}
