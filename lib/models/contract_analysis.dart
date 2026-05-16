// ContractAnalysis y modelos relacionados — output de contract_analysis_service.
// Spec en PRD §6 y §3.3.

enum RiskLevel { high, medium, low }

/// Una cláusula individual analizada por el AI.
class AnalyzedClause {
  final String clauseText;
  final RiskLevel riskLevel;
  final String issue;
  final String suggestion;

  const AnalyzedClause({
    required this.clauseText,
    required this.riskLevel,
    required this.issue,
    required this.suggestion,
  });

  factory AnalyzedClause.fromJson(Map<String, dynamic> json) {
    return AnalyzedClause(
      clauseText: json['clause_text'] as String,
      riskLevel: _parseRiskLevel(json['risk_level'] as String? ?? 'low'),
      issue: json['issue'] as String? ?? '',
      suggestion: json['suggestion'] as String? ?? '',
    );
  }

  static RiskLevel _parseRiskLevel(String value) {
    switch (value.toLowerCase()) {
      case 'high':
        return RiskLevel.high;
      case 'medium':
        return RiskLevel.medium;
      default:
        return RiskLevel.low;
    }
  }

  Map<String, dynamic> toJson() => {
        'clause_text': clauseText,
        'risk_level': riskLevel.name,
        'issue': issue,
        'suggestion': suggestion,
      };
}

/// Resultado del check de gravamen (mock para MVP, integración real en roadmap).
class GravamenCheck {
  final String status; // clean | flagged
  final String details;

  const GravamenCheck({required this.status, required this.details});

  bool get isFlagged => status == 'flagged';

  factory GravamenCheck.fromJson(Map<String, dynamic> json) {
    return GravamenCheck(
      status: json['status'] as String,
      details: json['details'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'status': status, 'details': details};
}

/// Análisis completo de un contrato inmobiliario.
class ContractAnalysis {
  final String contractType; // compraventa | alquiler | anticretico
  final String contractText;
  final int overallRiskScore; // 0-100
  final List<AnalyzedClause> analyzedClauses;
  final GravamenCheck gravamenCheck;
  final List<String> fraudPatternsDetected;
  final String summary;
  final List<String> recommendations;

  const ContractAnalysis({
    required this.contractType,
    required this.contractText,
    required this.overallRiskScore,
    required this.analyzedClauses,
    required this.gravamenCheck,
    required this.fraudPatternsDetected,
    required this.summary,
    required this.recommendations,
  });

  factory ContractAnalysis.fromJson(Map<String, dynamic> json) {
    return ContractAnalysis(
      contractType: json['contract_type'] as String,
      contractText: json['contract_text'] as String? ?? '',
      overallRiskScore: json['overall_risk_score'] as int? ?? 0,
      analyzedClauses: (json['analyzed_clauses'] as List? ?? [])
          .map((c) => AnalyzedClause.fromJson(c as Map<String, dynamic>))
          .toList(),
      gravamenCheck: GravamenCheck.fromJson(
        (json['gravamen_check'] as Map<String, dynamic>?) ??
            {'status': 'clean', 'details': ''},
      ),
      fraudPatternsDetected:
          (json['fraud_patterns_detected'] as List? ?? []).cast<String>(),
      summary: json['summary'] as String? ?? '',
      recommendations:
          (json['recommendations'] as List? ?? []).cast<String>(),
    );
  }

  Map<String, dynamic> toJson() => {
        'contract_type': contractType,
        'contract_text': contractText,
        'overall_risk_score': overallRiskScore,
        'analyzed_clauses':
            analyzedClauses.map((c) => c.toJson()).toList(),
        'gravamen_check': gravamenCheck.toJson(),
        'fraud_patterns_detected': fraudPatternsDetected,
        'summary': summary,
        'recommendations': recommendations,
      };
}
