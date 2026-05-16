/// MatchResult — output de matching_service para un (propiedad, cliente).
/// Spec en PRD §6.
class MatchResult {
  final String propertyId;
  final String clientProfileId;
  final int compatibilityPercent; // 0-100, UI muestra "X% compatible"
  final String explanation;
  final List<String> positiveFactors;
  final List<String> negativeFactors;
  final List<String> tagsMatched;
  final List<String> tagsMissing;

  const MatchResult({
    required this.propertyId,
    required this.clientProfileId,
    required this.compatibilityPercent,
    required this.explanation,
    required this.positiveFactors,
    required this.negativeFactors,
    required this.tagsMatched,
    required this.tagsMissing,
  });

  /// Bucket de color para el marker del mapa (PRD §3.1):
  /// >= 80 verde, 50-80 amarillo, < 50 gris.
  String get colorBucket {
    if (compatibilityPercent >= 80) return 'green';
    if (compatibilityPercent >= 50) return 'amber';
    return 'grey';
  }

  factory MatchResult.fromJson(Map<String, dynamic> json) {
    return MatchResult(
      propertyId: json['property_id'] as String? ?? '',
      clientProfileId: json['client_profile_id'] as String? ?? '',
      compatibilityPercent: json['compatibility_percent'] as int,
      explanation: json['explanation'] as String? ?? '',
      positiveFactors:
          (json['positive_factors'] as List? ?? []).cast<String>(),
      negativeFactors:
          (json['negative_factors'] as List? ?? []).cast<String>(),
      tagsMatched: (json['tags_matched'] as List? ?? []).cast<String>(),
      tagsMissing: (json['tags_missing'] as List? ?? []).cast<String>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'property_id': propertyId,
        'client_profile_id': clientProfileId,
        'compatibility_percent': compatibilityPercent,
        'explanation': explanation,
        'positive_factors': positiveFactors,
        'negative_factors': negativeFactors,
        'tags_matched': tagsMatched,
        'tags_missing': tagsMissing,
      };
}
