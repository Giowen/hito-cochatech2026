import 'client_profile.dart';

/// Bucket de temperatura del lead derivado del score de calificación AI.
/// El UI lo usa para colorear el badge y priorizar visualmente.
enum LeadBucket {
  /// Score >= 75: presupuesto realista, criterios claros, urgencia visible.
  hot,

  /// Score 50-74: viable pero requiere conversación para precisar criterios
  /// o validar presupuesto.
  warm,

  /// Score < 50: dudoso — presupuesto irreal, criterios contradictorios, o
  /// muy poca info para evaluar. No descartar pero priorizar último.
  cold,
}

extension LeadBucketX on LeadBucket {
  String get label => switch (this) {
        LeadBucket.hot => 'CALIENTE',
        LeadBucket.warm => 'TIBIO',
        LeadBucket.cold => 'FRÍO',
      };

  static LeadBucket fromScore(int score) {
    if (score >= 75) return LeadBucket.hot;
    if (score >= 50) return LeadBucket.warm;
    return LeadBucket.cold;
  }
}

/// Estado del lead en el pipeline del agente. Mutado por María desde
/// LeadDetailScreen.
enum LeadStatus {
  /// Recién entrado al inbox, María todavía no lo contactó.
  pending,

  /// María ya envió primer mensaje pero no hay respuesta confirmada.
  contacted,

  /// Hay visita agendada (vía AI sugerencia o manual).
  visiting,

  /// Cliente firmó / cerró la operación.
  closed,

  /// Cliente desistió / no contactable / dejó de responder.
  lost,
}

extension LeadStatusX on LeadStatus {
  String get label => switch (this) {
        LeadStatus.pending => 'Pendiente',
        LeadStatus.contacted => 'Contactado',
        LeadStatus.visiting => 'En visita',
        LeadStatus.closed => 'Cerrado',
        LeadStatus.lost => 'Perdido',
      };
}

/// Origen del lead — útil para que el agente entienda canal preferido y
/// para attribution analytics post-MVP.
enum LeadSource {
  /// El cliente abrió la app, eligió rol cliente, hizo voice query.
  /// Default cuando no hay link compartido.
  organic,

  /// Vino vía link compartido por María (ver `_shareLink` en top bar).
  /// Sugiere que ya conoce al agente y hay confianza pre-establecida.
  shareLink,

  /// Cargado manualmente por María desde "Capturar lead" (post-MVP).
  manual,
}

extension LeadSourceX on LeadSource {
  String get label => switch (this) {
        LeadSource.organic => 'App directa',
        LeadSource.shareLink => 'Link compartido',
        LeadSource.manual => 'Manual',
      };

  String get iconHint => switch (this) {
        LeadSource.organic => 'mic',
        LeadSource.shareLink => 'share',
        LeadSource.manual => 'pencil',
      };
}

/// Lead — un cliente potencial en el pipeline de un agente.
///
/// Carga la `ClientProfile` estructurada (output del voice→profile pipeline)
/// + metadatos de calificación AI + estado del agente. Persiste en
/// SharedPreferences durante la sesión y en SeedJSON los pre-creados.
class Lead {
  final String id;
  final String? clientName;
  final String? clientPhone;
  final ClientProfile profile;

  /// Score 0-100 de qué tan viable es este lead. Output del
  /// LeadQualificationService. Drives `LeadBucket`.
  final int qualificationScore;

  /// Bullets cortos explicando por qué tiene ese score. Mostrados al agente
  /// en LeadDetailScreen para que sepa qué hacer con el lead.
  final List<String> qualificationReasoning;

  final LeadStatus status;
  final LeadSource source;
  final DateTime createdAt;
  final DateTime? lastContactAt;

  /// Notas del agente (post-MVP — el agente podrá agregar texto libre).
  final String? notes;

  const Lead({
    required this.id,
    this.clientName,
    this.clientPhone,
    required this.profile,
    required this.qualificationScore,
    this.qualificationReasoning = const [],
    this.status = LeadStatus.pending,
    this.source = LeadSource.organic,
    required this.createdAt,
    this.lastContactAt,
    this.notes,
  });

  LeadBucket get bucket => LeadBucketX.fromScore(qualificationScore);

  /// Iniciales para el avatar (max 2 chars). Si no hay nombre devuelve "?".
  String get initials {
    final name = clientName?.trim() ?? '';
    if (name.isEmpty) return '?';
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  /// "hace 2h", "hace 3d", "hace minutos". Para UI.
  String get ageLabel {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    if (diff.inMinutes < 60) {
      return diff.inMinutes <= 1 ? 'hace un momento' : 'hace ${diff.inMinutes} min';
    }
    if (diff.inHours < 24) return 'hace ${diff.inHours}h';
    if (diff.inDays < 30) return 'hace ${diff.inDays}d';
    return 'hace ${(diff.inDays / 30).floor()} meses';
  }

  Lead copyWith({
    String? id,
    String? clientName,
    String? clientPhone,
    ClientProfile? profile,
    int? qualificationScore,
    List<String>? qualificationReasoning,
    LeadStatus? status,
    LeadSource? source,
    DateTime? createdAt,
    DateTime? lastContactAt,
    String? notes,
  }) {
    return Lead(
      id: id ?? this.id,
      clientName: clientName ?? this.clientName,
      clientPhone: clientPhone ?? this.clientPhone,
      profile: profile ?? this.profile,
      qualificationScore: qualificationScore ?? this.qualificationScore,
      qualificationReasoning:
          qualificationReasoning ?? this.qualificationReasoning,
      status: status ?? this.status,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      lastContactAt: lastContactAt ?? this.lastContactAt,
      notes: notes ?? this.notes,
    );
  }

  factory Lead.fromJson(Map<String, dynamic> json) {
    return Lead(
      id: json['id'] as String,
      clientName: json['client_name'] as String?,
      clientPhone: json['client_phone'] as String?,
      profile: ClientProfile.fromJson(json['profile'] as Map<String, dynamic>),
      qualificationScore:
          (json['qualification_score'] as num?)?.toInt().clamp(0, 100) ?? 0,
      qualificationReasoning:
          ((json['qualification_reasoning'] as List?) ?? const [])
              .cast<String>(),
      status: LeadStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => LeadStatus.pending,
      ),
      source: LeadSource.values.firstWhere(
        (s) => s.name == json['source'],
        orElse: () => LeadSource.organic,
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      lastContactAt: json['last_contact_at'] == null
          ? null
          : DateTime.parse(json['last_contact_at'] as String),
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (clientName != null) 'client_name': clientName,
        if (clientPhone != null) 'client_phone': clientPhone,
        'profile': profile.toJson(),
        'qualification_score': qualificationScore,
        'qualification_reasoning': qualificationReasoning,
        'status': status.name,
        'source': source.name,
        'created_at': createdAt.toIso8601String(),
        if (lastContactAt != null)
          'last_contact_at': lastContactAt!.toIso8601String(),
        if (notes != null) 'notes': notes,
      };
}
