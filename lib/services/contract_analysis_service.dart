import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/contract_analysis.dart';
import '../models/property.dart';
import 'gravamen_mock.dart';
import 'groq_client.dart';

/// ContractAnalysisService — analiza contratos inmobiliarios bolivianos con AI.
///
/// Cobertura: compra-venta, alquiler, anticrético (KEY DIFFERENTIATOR — único en Bolivia).
/// Demo path: hardcoded canonical para anticretico_sample.txt (13 cláusulas,
/// gravamen Banco BISA $42K folio 3.01.4.99.0034521, decisión "no firmar").
/// LLM path: prompt PRD §16.3 con Groq Llama 3.3 70B (few-shot multi-type).
///
/// Repository hook: cuando Drift+Supabase entren, contratos se cargan vía
/// ContractRepository (que sincroniza con R2 + Supabase). Stubs marcados con // TODO R2.
class ContractAnalysisService {
  final GroqClient _groqClient;
  final GravamenMockService _gravamenMock;

  ContractAnalysisService({
    GroqClient? groqClient,
    GravamenMockService? gravamenMock,
  })  : _groqClient = groqClient ?? GroqClient(),
        _gravamenMock = gravamenMock ?? GravamenMockService();

  /// Carga el contrato anticrético canónico (13 cláusulas Banco BISA).
  /// TODO R2: en producción este texto vendría del bucket Cloudflare R2 vía
  /// signed URL, no de assets locales.
  Future<String> loadAnticreticoSample() async {
    return rootBundle.loadString('assets/seed/anticretico_sample.txt');
  }

  /// Análisis para anticretico_sample.txt en contexto de [property].
  /// Demo path retorna hardcoded analysis con 13 cláusulas (1 red, 1 red gravamen,
  /// 3 yellow, 8 green) + Banco BISA gravamen según has_lien.
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
      overallRiskScore: gravamen.isFlagged ? 74 : 48,
      analyzedClauses: [
        const AnalyzedClause(
          clauseText:
              'Comparecen Sr. Carlos Mendoza R., con CI 4.231.876 Cbba, mayor de edad, domiciliado en calle Aniceto Arce N° 421, en calidad de PROPIETARIO; y los esposos Juan García y Ana López, con CI 8.421.190 y 9.102.554 respectivamente, en calidad de ANTICRESISTAS.',
          riskLevel: RiskLevel.low,
          issue: 'Identificación completa. Validado contra padrón electoral.',
          suggestion: 'Sin cambios necesarios.',
        ),
        const AnalyzedClause(
          clauseText:
              'El propietario entrega a los anticresistas el inmueble ubicado en Av. Pando N° 1842, zona Cala Cala, Cochabamba, registrado en Derechos Reales bajo Folio Real 3.01.4.99.0034521, con superficie de terreno de 320 m² y construcción de 280 m².',
          riskLevel: RiskLevel.low,
          issue: 'Datos coinciden con Derechos Reales.',
          suggestion: 'Sin cambios necesarios.',
        ),
        const AnalyzedClause(
          clauseText:
              'El monto total del anticrético es de Bs 320.000 (TRESCIENTOS VEINTE MIL BOLIVIANOS), que serán entregados en su totalidad al momento de la firma del presente contrato y consignación notarial.',
          riskLevel: RiskLevel.low,
          issue:
              'Monto dentro del rango de mercado para la zona (Bs 280k–360k).',
          suggestion: 'Sin cambios.',
        ),
        const AnalyzedClause(
          clauseText:
              'El plazo del presente contrato es de VEINTICUATRO (24) meses calendario, contados a partir de la firma. Renovable por acuerdo escrito de ambas partes.',
          riskLevel: RiskLevel.low,
          issue: 'Plazo dentro del marco del Código Civil art. 1430.',
          suggestion: 'Sin cambios.',
        ),
        AnalyzedClause(
          clauseText:
              'EL PROPIETARIO declara bajo juramento que el inmueble se encuentra libre de todo gravamen, hipoteca, embargo o cualquier afectación que pudiera limitar el derecho del anticresista.',
          riskLevel: RiskLevel.high,
          issue: gravamen.isFlagged
              ? 'FALSO. El inmueble figura con hipoteca activa Banco BISA \$42,000 USD (folio 3.01.4.99.0034521). Verificado en DD.RR. minutos atrás.'
              : 'Declaración estándar. Verificada conforme.',
          suggestion: gravamen.isFlagged
              ? 'Exigir declaración corregida + carta del banco autorizando el anticrético + protocolización inmediata.'
              : 'Sin cambios.',
        ),
        const AnalyzedClause(
          clauseText:
              'Los anticresistas podrán ocupar y usar el inmueble como vivienda familiar, debiendo conservarlo en buen estado y devolverlo en las condiciones recibidas, salvo el desgaste natural.',
          riskLevel: RiskLevel.low,
          issue: 'Cláusula estándar.',
          suggestion: 'Sin cambios.',
        ),
        const AnalyzedClause(
          clauseText:
              'Al término del contrato el PROPIETARIO se compromete a devolver el monto total del anticrético dentro de los treinta (30) días siguientes, condicionado a la venta de otra propiedad de su titularidad ubicada en zona Sacaba.',
          riskLevel: RiskLevel.high,
          issue:
              'No estándar. La devolución del capital NO puede estar condicionada a la venta de un tercer inmueble. Es ejecutable contra la propiedad anticresada (CC art. 1432).',
          suggestion:
              'Renegociar: plazo cierto de devolución (30 días) sin condicionante. Si el propietario insiste, retirarse del deal.',
        ),
        const AnalyzedClause(
          clauseText:
              'Los servicios de agua, luz, gas y mantenimiento ordinario correrán por cuenta de los anticresistas durante todo el plazo del contrato.',
          riskLevel: RiskLevel.medium,
          issue: 'Estándar, pero las deudas previas pueden traspasarse silenciosamente.',
          suggestion:
              'Solicitar último estado de cuenta de cada servicio (no mayor a 30 días) antes de la firma.',
        ),
        const AnalyzedClause(
          clauseText:
              'Toda mejora introducida por los anticresistas pasará a beneficio del propietario sin derecho a indemnización ni compensación alguna.',
          riskLevel: RiskLevel.medium,
          issue:
              'Estándar pero abusiva para mejoras estructurales mayores. La familia García-López puede invertir en patio/cocina.',
          suggestion:
              'Modificar: mejoras estructurales mayores a Bs 10.000 con factura serán reembolsadas al término.',
        ),
        const AnalyzedClause(
          clauseText:
              'El contrato podrá resolverse antes del plazo por mutuo acuerdo o por incumplimiento grave de cualquiera de las partes, previa notificación notarial con treinta (30) días de anticipación.',
          riskLevel: RiskLevel.low,
          issue: 'Estándar.',
          suggestion: 'Sin cambios.',
        ),
        const AnalyzedClause(
          clauseText:
              'En caso de incumplimiento del propietario, el anticresista podrá retener el inmueble hasta la devolución total del monto, sin que ello configure ocupación indebida.',
          riskLevel: RiskLevel.medium,
          issue:
              'Cláusula favorable para los anticresistas. Sin embargo, su oponibilidad a terceros depende de la protocolización.',
          suggestion:
              'Asegúrese de protocolizar el contrato (Cláusula DECIMOTERCERA) para que esta retención sea oponible si el propietario vende o transfiere.',
        ),
        const AnalyzedClause(
          clauseText:
              'Para cualquier controversia derivada del presente contrato, las partes se someten a la jurisdicción ordinaria de Cochabamba, renunciando expresamente a cualquier otro fuero.',
          riskLevel: RiskLevel.low,
          issue: 'Cláusula estándar.',
          suggestion: 'Sin cambios.',
        ),
        const AnalyzedClause(
          clauseText:
              'El presente contrato será elevado a Escritura Pública y registrado en Derechos Reales dentro de los quince (15) días siguientes a su suscripción.',
          riskLevel: RiskLevel.low,
          issue:
              'Esencial — sin protocolización, el anticrético no es oponible a terceros (CC art. 1431).',
          suggestion:
              'Verificar que se cumpla efectivamente en el plazo de 15 días. Pedir copia del Folio Real actualizado tras la inscripción.',
        ),
      ],
      gravamenCheck: gravamen,
      fraudPatternsDetected: gravamen.isFlagged
          ? const [
              'Cláusula QUINTA contradice información del registro de Derechos Reales: declara propiedad libre, pero figura hipoteca activa Banco BISA \$42,000 USD (folio 3.01.4.99.0034521).',
              'Cláusula SÉPTIMA condiciona devolución del anticrético a venta de OTRO inmueble en Sacaba — patrón usado para diferir reembolso indefinidamente.',
            ]
          : const [],
      summary: gravamen.isFlagged
          ? 'Detectamos 2 riesgos críticos: (1) gravamen hipotecario no declarado con Banco BISA por \$42k USD (Cláusula QUINTA es FALSA — verificado en DD.RR.), (2) devolución del capital condicionada a venta de un tercer inmueble (Cláusula SÉPTIMA, no estándar). Más 3 cláusulas que requieren revisión. NO firmar sin levantamiento del gravamen y modificación de la Cláusula 7.'
          : 'Detectamos 1 cláusula crítica (devolución condicionada) y 3 cláusulas a revisar. 8 cláusulas conforme a estándar.',
      recommendations: [
        if (gravamen.isFlagged)
          'CRÍTICO: Exigir que el propietario levante la hipoteca con BISA o obtenga autorización escrita del banco antes de firmar. Sin esto, el capital del anticrético podría perderse en remate.',
        'Modificar Cláusula SÉPTIMA: devolución del capital en plazo cierto (30 días) sin condicionante de venta de otro inmueble.',
        'Solicitar certificado actualizado de Derechos Reales con fecha no mayor a 30 días antes de la firma.',
        'Pedir últimos estados de cuenta de agua, luz, gas (Cláusula OCTAVA) para evitar transferencia de deudas previas.',
        'Modificar Cláusula NOVENA: mejoras estructurales mayores a Bs 10.000 con factura serán reembolsadas al término.',
        'Protocolizar inmediatamente tras la firma (Cláusula DECIMOTERCERA) para asegurar oponibilidad a terceros.',
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

    final userPrompt =
        'Contrato a analizar (tipo declarado: $declaredType):\n\n'
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

    final gravamen = _gravamenMock.check(property);

    return ContractAnalysis.fromJson({
      ...json,
      'contract_text': contractText,
      'gravamen_check': gravamen.toJson(),
    });
  }
}
