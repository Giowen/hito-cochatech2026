import 'package:latlong2/latlong.dart';

/// ClientProfile — perfil del cliente final (Juan) usado para matching.
/// Spec en PRD §6.
class ClientProfile {
  final String id;
  final int budgetMin;
  final int budgetMax;
  final String transactionType; // compra | alquiler | anticretico
  final double desiredLat;
  final double desiredLng;
  final double radiusKm;
  final int minBedrooms;
  final int minAreaM2;
  final List<String> requiredTags;
  final String? voiceInputTranscript;

  const ClientProfile({
    required this.id,
    required this.budgetMin,
    required this.budgetMax,
    required this.transactionType,
    required this.desiredLat,
    required this.desiredLng,
    required this.radiusKm,
    required this.minBedrooms,
    required this.minAreaM2,
    required this.requiredTags,
    this.voiceInputTranscript,
  });

  LatLng get desiredLocation => LatLng(desiredLat, desiredLng);

  factory ClientProfile.fromJson(Map<String, dynamic> json) {
    return ClientProfile(
      id: json['id'] as String,
      budgetMin: json['budget_min'] as int,
      budgetMax: json['budget_max'] as int,
      transactionType: json['transaction_type'] as String,
      desiredLat: (json['desired_lat'] as num).toDouble(),
      desiredLng: (json['desired_lng'] as num).toDouble(),
      radiusKm: (json['radius_km'] as num).toDouble(),
      minBedrooms: json['min_bedrooms'] as int,
      minAreaM2: json['min_area_m2'] as int,
      requiredTags: (json['required_tags'] as List).cast<String>(),
      voiceInputTranscript: json['voice_input_transcript'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'budget_min': budgetMin,
        'budget_max': budgetMax,
        'transaction_type': transactionType,
        'desired_lat': desiredLat,
        'desired_lng': desiredLng,
        'radius_km': radiusKm,
        'min_bedrooms': minBedrooms,
        'min_area_m2': minAreaM2,
        'required_tags': requiredTags,
        if (voiceInputTranscript != null)
          'voice_input_transcript': voiceInputTranscript,
      };

  /// Perfil hardcoded de Juan para demo path (PITCH_PREP §2 + plan demo spec).
  /// Cuando se ejecute el demo, este es el perfil que produce Voice input.
  static const ClientProfile demoJuan = ClientProfile(
    id: 'demo-juan',
    budgetMin: 700000,
    budgetMax: 850000,
    transactionType: 'compra',
    desiredLat: -17.395,
    desiredLng: -66.140,
    radiusKm: 2.0,
    minBedrooms: 3,
    minAreaM2: 90,
    requiredTags: [
      'cerca_UMSS',
      'acepta_mascotas',
      'tiene_parqueo',
      'zona_segura',
    ],
    voiceInputTranscript:
        'Casa con jardín, cerca de UMSS, 800 mil bolivianos, acepta mascotas, dos hijos pequeños.',
  );
}
