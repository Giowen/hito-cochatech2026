import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/contract_analysis.dart';
import '../models/property.dart';
import 'gravamen_mock.dart';
import 'groq_client.dart';

/// ContractAnalysisService — analiza contratos inmobiliarios bolivianos con AI.
///
/// Cobertura: compra-venta, alquiler, anticrético (KEY DIFFERENTIATOR).
/// Demo path: hardcoded análisis para anticretico_sample.txt + gravamen mock.
/// LLM path: prompt PRD §16.3 con Groq Llama 3.3 70B, few-shot multi-type.
class ContractAnalysisService {
  final GroqClient _groqClient;
  final GravamenMockService _gravamenMock;

  ContractAnalysisService({
    GroqClient? groqClient,
    GravamenMockService? gravamenMock,
  })  : _groqClient = groqClient ?? GroqClient(),
        _gravamenMock = gravamenMock ?? GravamenMockService();

  /// Carga el contrato anticrético sample desde assets.
  Future<String> loadAnticreticoSample() async {
    return rootBundle.loadString('assets/seed/anticretico_sample.txt');
  }

  /// Análisis para anticretico_sample.txt en contexto de [property].
  /// Demo path retorna hardcoded analysis con 3 cláusulas + gravamen
  /// según has_lien de la propiedad.
  Future<ContractAnalysis> analyzeAnticreticoFor(
    Property property, {
    bool useDemoPath = true,
  }) async {
    final contractText = await loadAnticreticoSample();
    if (useDemoPath) {
      return _hardcodedAnticreticoAnalysis(property, contractText);
    }
    return _llmAnalysis(property, contractText, 'anticretico');
  }

  ContractAnalysis _hardcodedAnticreticoAnalysis(
    Property property,
    String contractText,
  ) {
    final gravamen = _gravamenMock.check(property);
    return ContractAnalysis(
      contractType: 'anticretico',
      contractText: contractText,
      overallRiskScore: gravamen.isFlagged ? 78 : 52,
      analyzedClauses: const [
        AnalyzedClause(
          clauseText:
              'EL PROPIETARIO podrá rescindir el contrato sin reembolso del capital si EL ANTICRESISTA incumple cualquiera de las obligaciones aquí establecidas, lo cual será determinado a sola discreción de EL PROPIETARIO.',
          riskLevel: RiskLevel.high,
          issue:
              'Cláusula abusiva: permite rescisión unilateral sin reembolso a sola discreción del propietario.',
          suggestion:
              'Exigir definición objetiva de incumplimiento y proceso de notificación con plazo de subsanación (mínimo 15 días) antes de cualquier rescisión.',
        ),
        AnalyzedClause(
          clauseText:
              'La fecha exacta de restitución se acordará entre las partes al final del periodo, según las circunstancias económicas vigentes en ese momento.',
          riskLevel: RiskLevel.medium,
          issue:
              'Plazo de restitución del capital ambiguo, sin fecha cierta ni penalidad por mora.',
          suggestion:
              'Fijar fecha específica (e.g. 30 días tras fin del plazo) con penalidad del 5% mensual por demora en restitución.',
        ),
        AnalyzedClause(
          clauseText:
              'Las partes acuerdan que EL ANTICRESISTA realizará el mantenimiento estándar de la propiedad, incluyendo limpieza, reparaciones menores y conservación del jardín. Las reparaciones mayores serán cubiertas por EL PROPIETARIO.',
          riskLevel: RiskLevel.low,
          issue: 'Cláusula estándar de mantenimiento, conforme a la práctica del mercado.',
          suggestion: 'Sin cambios necesarios.',
        ),
      ],
      gravamenCheck: gravamen,
      fraudPatternsDetected: gravamen.isFlagged
          ? const [
              'Propietario declara bajo juramento que el inmueble está libre de gravámenes (Cláusula SÉPTIMA), pero el registro de Derechos Reales muestra una hipoteca activa con BCB.',
            ]
          : const [],
      summary: gravamen.isFlagged
          ? 'Detectamos 3 riesgos significativos: una cláusula abusiva de rescisión, plazo de restitución ambiguo, y CRÍTICAMENTE una contradicción entre la declaración del propietario y el registro real, que muestra una hipoteca activa con BCB. Recomendamos NO firmar sin renegociar estos puntos.'
          : 'Detectamos 2 cláusulas que requieren revisión antes de firmar. Una cláusula está conforme a estándares del mercado.',
      recommendations: [
        'Renegociar la Cláusula TERCERA para limitar la rescisión a causales objetivas con proceso de notificación previo.',
        'Especificar fecha cierta de restitución (e.g. 30 días post-plazo) con penalidad por mora del 5% mensual.',
        if (gravamen.isFlagged)
          'CRÍTICO: Exigir cancelación de la hipoteca con BCB o constitución de garantía adicional ANTES de entregar el capital.',
        'Solicitar certificado actualizado de Derechos Reales con fecha no mayor a 30 días antes de la firma.',
      ],
    );
  }

  Future<ContractAnalysis> _llmAnalysis(
    Property property,
    String contractText,
    String declaredType,
  ) async {
    const systemPrompt = '''
Eres un abogado boliviano especializado en contratos inmobiliarios con conocimiento profundo del Código Civil boliviano. Trabajas con tres tipos de contratos:

1. COMPRA-VENTA (CC arts. 584-735): transferencia definitiva de propiedad
2. ALQUILER (Ley General del Inquilinato): uso temporal con pago periódico
3. ANTICRÉTICO (CC arts. 1429-1438): único en Bolivia — transferencia temporal del uso con entrega de capital, restituible al final del plazo

Tu trabajo: detectar
- Cláusulas abusivas (cancelación unilateral, plazos ambiguos, sin penalidades)
- Posibles gravámenes no declarados
- Patrones de fraude documental

Genera alertas EN ESPAÑOL CLARO, accionables.

Devuelve JSON estricto:
{
  "contract_type": "compraventa"|"alquiler"|"anticretico",
  "overall_risk_score": int 0-100,
  "analyzed_clauses": [
    {"clause_text": string (texto literal del contrato), "risk_level": "high"|"medium"|"low", "issue": string, "suggestion": string}
  ],
  "fraud_patterns_detected": [strings],
  "summary": string,
  "recommendations": [strings]
}

Para has_lien=true: incluir en fraud_patterns_detected y recommendations.
''';

    final userPrompt = 'Contrato a analizar (tipo declarado: $declaredType):\n\n'
        '${jsonEncode({"property_has_lien": property.hasLien, "contract": contractText})}';

    final response = await _groqClient.chat(
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      temperature: 0.2,
      responseFormat: {'type': 'json_object'},
    );

    final json = GroqClient.extractJson(response);
    if (json == null) {
      throw Exception('Failed to parse contract analysis JSON: $response');
    }

    // El gravamen check viene de nuestro mock, no del LLM (LLM no puede consultar DDRR)
    final gravamen = _gravamenMock.check(property);

    return ContractAnalysis.fromJson({
      ...json,
      'contract_text': contractText,
      'gravamen_check': gravamen.toJson(),
    });
  }
}
