/// MatchResult — output de matching_service para un (propiedad, cliente).
///
/// **3-bucket categorization** (v8+): en vez de `positive_factors` y
/// `negative_factors` el LLM ahora clasifica los hallazgos en tres niveles
/// de severidad y accionabilidad:
///
///   - `recommended`: fortalezas claras de la propiedad para este cliente.
///     Cosas que el agente puede usar como argumento de venta.
///   - `considerations`: hechos neutros que el cliente debería verificar
///     antes de cerrar (año de construcción medio, distancia a un colegio,
///     mantenimiento, etc). Verde-ámbar.
///   - `risks`: problemas serios que afectan la decisión (excede budget,
///     muy lejos de la zona, sin parqueo cuando lo pidió, etc).
///
/// El backward compat con `positive_factors`/`negative_factors` se mantiene
/// solo en el reader: si llega data vieja se mapea como recommended/risks.
class MatchResult {
  final String propertyId;
  final String clientProfileId;
  final int compatibilityPercent; // 0-100, UI muestra "X% compatible"
  final String explanation;
  final List<String> recommended;
  final List<String> considerations;
  final List<String> risks;
  final List<String> tagsMatched;
  final List<String> tagsMissing;

  const MatchResult({
    required this.propertyId,
    required this.clientProfileId,
    required this.compatibilityPercent,
    required this.explanation,
    this.recommended = const [],
    this.considerations = const [],
    this.risks = const [],
    this.tagsMatched = const [],
    this.tagsMissing = const [],
  });

  factory MatchResult.fromJson(Map<String, dynamic> json) {
    final rawCompat = json['compatibility_percent'];
    final compat = rawCompat is num ? rawCompat.toInt().clamp(0, 100) : 0;

    List<String> readList(dynamic v) =>
        ((v as List?) ?? const []).cast<String>();

    // Backward compat: si llega la data vieja (positive_factors/negative_factors),
    // mapeamos como recommended/risks para que el render funcione mientras
    // se invalida el cache (bump de _promptVersion).
    final recommended = readList(json['recommended']).isNotEmpty
        ? readList(json['recommended'])
        : readList(json['positive_factors']);
    final risks = readList(json['risks']).isNotEmpty
        ? readList(json['risks'])
        : readList(json['negative_factors']);
    final considerations = readList(json['considerations']);

    return MatchResult(
      propertyId: json['property_id'] as String? ?? '',
      clientProfileId: json['client_profile_id'] as String? ?? '',
      compatibilityPercent: compat,
      explanation: json['explanation'] as String? ?? '',
      recommended: recommended,
      considerations: considerations,
      risks: risks,
      tagsMatched: readList(json['tags_matched']),
      tagsMissing: readList(json['tags_missing']),
    );
  }

  MatchResult copyWith({
    String? propertyId,
    String? clientProfileId,
    int? compatibilityPercent,
    String? explanation,
    List<String>? recommended,
    List<String>? considerations,
    List<String>? risks,
    List<String>? tagsMatched,
    List<String>? tagsMissing,
  }) {
    return MatchResult(
      propertyId: propertyId ?? this.propertyId,
      clientProfileId: clientProfileId ?? this.clientProfileId,
      compatibilityPercent: compatibilityPercent ?? this.compatibilityPercent,
      explanation: explanation ?? this.explanation,
      recommended: recommended ?? this.recommended,
      considerations: considerations ?? this.considerations,
      risks: risks ?? this.risks,
      tagsMatched: tagsMatched ?? this.tagsMatched,
      tagsMissing: tagsMissing ?? this.tagsMissing,
    );
  }

  Map<String, dynamic> toJson() => {
        'property_id': propertyId,
        'client_profile_id': clientProfileId,
        'compatibility_percent': compatibilityPercent,
        'explanation': explanation,
        'recommended': recommended,
        'considerations': considerations,
        'risks': risks,
        'tags_matched': tagsMatched,
        'tags_missing': tagsMissing,
      };
}
