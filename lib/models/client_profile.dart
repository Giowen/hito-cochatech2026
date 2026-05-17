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

  /// Versión del prompt de matching. Bump para invalidar cache global cuando
  /// el system prompt en MatchingService cambia (cambios de criterios, caps,
  /// labels, etc). Cada bump → todos los profile hashes cambian → cache miss
  /// global → Groq vuelve a calcular con el nuevo prompt.
  ///
  /// History:
  ///   v1: prompt inicial (C.1)
  ///   v2: caps duros + labels claros + lectura transcript
  ///   v3: caps duros enforced client-side post-LLM
  ///   v4: compra↔venta normalization + budget extraction fixes
  ///   v5: HECHOS verificados en user prompt + anti-hallucination rules
  ///   v6: effectivePriceBob para anticretico (no usar priceBob de venta)
  static const _promptVersion = 'v6';

  /// Hash determinístico de los campos que afectan la decisión de matching.
  /// Incluye `_promptVersion` para invalidar cache cuando cambia el prompt.
  /// Cambios en `voiceInputTranscript` también se incluyen porque el LLM
  /// lee el transcript para detectar preferencias de tipo (depto/casa).
  String get contentHash {
    final canonical = [
      'pv:$_promptVersion',
      'b:$budgetMin-$budgetMax',
      't:$transactionType',
      'l:${desiredLat.toStringAsFixed(4)},${desiredLng.toStringAsFixed(4)}',
      'r:${radiusKm.toStringAsFixed(1)}',
      'bd:$minBedrooms',
      'a:$minAreaM2',
      'tags:${(List<String>.from(requiredTags)..sort()).join(",")}',
      'vt:${voiceInputTranscript ?? ""}',
    ].join('|');
    return _djb2Hex64(canonical);
  }

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

  /// Perfil hardcoded de Juan para demo path (canonical claude-design data).
  /// Voice query rica: presupuesto USD $220k, familia con 2 hijos pequeños,
  /// oficina en Recoleta, considera anticrético.
  static const ClientProfile demoJuan = ClientProfile(
    id: 'demo-juan',
    // $200k-$220k USD via TC paralelo 12.20 → 2,440K-2,684K BOB
    budgetMin: 2440000,
    budgetMax: 2684000,
    transactionType: 'compra',
    // Recoleta (oficina del usuario) — ≤20 min commute target
    desiredLat: -17.376,
    desiredLng: -66.140,
    radiusKm: 3.0,
    minBedrooms: 3,
    minAreaM2: 150,
    requiredTags: [
      'patio',
      'familia_segura',
      'cerca_recoleta',
      'acepta_anticretico',
    ],
    voiceInputTranscript:
        'Busco casa para mi familia, tenemos dos hijos pequeños, presupuesto hasta doscientos veinte mil dólares, queremos tres o cuatro dormitorios y patio. La oficina queda en la Recoleta, idealmente menos de 20 minutos. También nos interesa anticrético.',
  );
}

/// djb2 64-bit como concat de dos djb2 32-bit con seeds distintos.
/// Stable, Web-safe (`& 0xFFFFFFFF`), 16 hex chars de salida.
String _djb2Hex64(String s) {
  int h1 = 5381;
  int h2 = 0x1505 ^ 0xC0FFEE;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    h1 = ((h1 * 33) ^ c) & 0xFFFFFFFF;
    h2 = ((h2 * 31) ^ c) & 0xFFFFFFFF;
  }
  return h1.toRadixString(16).padLeft(8, '0') +
      h2.toRadixString(16).padLeft(8, '0');
}
