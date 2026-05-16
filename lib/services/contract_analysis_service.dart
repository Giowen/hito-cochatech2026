import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/contract_analysis.dart';
import '../models/property.dart';
import '../repositories/contract_analysis_cache_repository.dart';
import 'gravamen_mock.dart';
import 'groq_client.dart';

/// ContractAnalysisService — análisis legal AI de contratos bolivianos.
///
/// **No hay demo path hardcoded.** El LLM (Groq Llama 3.3 70B) analiza
/// CUALQUIER texto de contrato — anticrético, compra-venta, alquiler —
/// con conocimiento del Código Civil boliviano. Resultado cachea en
/// `contract_analyses` (Supabase) por (property_id, contract_type).
///
/// Gravamen check se mantiene mock (DDRR no expone API público — integración
/// real via partnership AETN está en Phase 2). El mock se pasa al LLM como
/// contexto para que cite específicamente Banco BISA y monto cuando aplica,
/// y el resultado final usa siempre el gravamen real del mock, no la
/// interpretación del LLM.
class ContractAnalysisService {
  final GroqClient _groqClient;
  final GravamenMockService _gravamenMock;
  final ContractAnalysisCacheRepository _cache;

  ContractAnalysisService({
    GroqClient? groqClient,
    GravamenMockService? gravamenMock,
    ContractAnalysisCacheRepository? cache,
  })  : _groqClient = groqClient ?? GroqClient(),
        _gravamenMock = gravamenMock ?? GravamenMockService(),
        _cache = cache ?? NoOpContractAnalysisCacheRepository();

  /// Carga el contrato anticrético canónico (13 cláusulas, gravamen Banco BISA).
  /// TODO R2: en producción cargar via signed URL desde Cloudflare R2.
  Future<String> loadAnticreticoSample() async {
    return rootBundle.loadString('assets/seed/anticretico_sample.txt');
  }

  /// Atajo: carga el sample anticrético y lo analiza para [property].
  Future<ContractAnalysis> analyzeAnticreticoFor(
    Property property, {
    bool useCache = true,
  }) async {
    final contractText = await loadAnticreticoSample();
    return analyzeContract(
      property: property,
      contractText: contractText,
      contractType: 'anticretico',
      useCache: useCache,
    );
  }

  /// API pública. Cache check → Groq → cache insert → return.
  /// Funciona para cualquier `contractType`: anticretico, compraventa, alquiler.
  Future<ContractAnalysis> analyzeContract({
    required Property property,
    required String contractText,
    required String contractType,
    bool useCache = true,
  }) async {
    if (useCache) {
      final cached = await _cache.getLatest(
        propertyId: property.id,
        contractType: contractType,
      );
      if (cached != null) {
        debugPrint(
          '[Hito.Contract] cache HIT id=${property.id} type=$contractType '
          'risk=${cached.overallRiskScore} clauses=${cached.analyzedClauses.length}',
        );
        return cached;
      }
    }

    debugPrint(
      '[Hito.Contract] cache MISS id=${property.id} type=$contractType '
      '→ Groq Llama 3.3',
    );

    final analysis =
        await _llmAnalysis(property, contractText, contractType);
    await _cache.insert(propertyId: property.id, analysis: analysis);
    return analysis;
  }

  // ── Internals ───────────────────────────────────────────────────────────

  static const _systemPrompt = '''
Eres un abogado boliviano senior, especializado en contratos inmobiliarios,
con conocimiento profundo del Código Civil boliviano. Trabajas con tres tipos:

1. COMPRA-VENTA (CC arts. 584-735): transferencia definitiva de propiedad.
2. ALQUILER (Ley General del Inquilinato): uso temporal con pago periódico.
3. ANTICRÉTICO (CC arts. 1429-1438): único en Bolivia — transferencia
   temporal del uso con entrega de capital, restituible al final del plazo.

Tu trabajo: analizar el contrato cláusula por cláusula y detectar:
- Cláusulas abusivas (rescisión unilateral sin reembolso, plazos abiertos,
  sin penalidades por incumplimiento del propietario, etc.).
- Contradicciones con el estado registral (gravámenes no declarados — el
  sistema te pasa un gravamen_check externo del registro DDRR).
- Patrones de fraude documental (devolución de capital condicionada a venta
  de OTRO inmueble, condiciones sólo verbales no escritas, monto en moneda
  no oficial sin tasa de cambio fijada, etc.).

ALERTAS EN ESPAÑOL CLARO Y ACCIONABLE para clientes bolivianos.

Devuelve JSON estricto (sin markdown):
{
  "contract_type": "compraventa" | "alquiler" | "anticretico",
  "overall_risk_score": int 0-100 (suma ponderada del riesgo de cada cláusula),
  "analyzed_clauses": [
    {
      "clause_text": string (cita literal del contrato),
      "risk_level": "high" | "medium" | "low",
      "issue": string (qué problema o conformidad detectaste, max 40 palabras),
      "suggestion": string (acción concreta recomendada, max 30 palabras)
    }
    // 5 a 15 cláusulas según el contrato
  ],
  "fraud_patterns_detected": [strings, máximo 5, vacío si no hay],
  "summary": string max 90 palabras, ejecutivo, con conteo de high/med/low,
  "recommendations": [strings, 3-7 items, accionables]
}

REGLAS:
- Si el contexto incluye gravamen flagged: la cláusula que declara la
  propiedad libre de gravámenes debe marcarse high y el fraud pattern debe
  citar específicamente el banco, monto y folio del gravamen externo.
- Cada cláusula con risk_level high debe tener una suggestion concreta.
- summary debe terminar con la decisión: "Firmar", "Firmar con cambios",
  o "NO firmar sin levantar X".
- recommendations ordenadas por urgencia descendiente.
- NO inventes datos. Si un campo del contrato no está claro, marca
  risk_level medium y pide la información en la suggestion.
''';

  Future<ContractAnalysis> _llmAnalysis(
    Property property,
    String contractText,
    String declaredType,
  ) async {
    final gravamen = _gravamenMock.check(property);

    final userPayload = {
      'property': {
        'id': property.id,
        'address': property.address,
        'neighborhood': property.neighborhood,
        'has_lien': property.hasLien,
      },
      'gravamen_check_externo': gravamen.toJson(),
      'declared_contract_type': declaredType,
      'contract_text': contractText,
    };

    final raw = await _groqClient.chat(
      messages: [
        const {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': jsonEncode(userPayload)},
      ],
      temperature: 0.2,
      responseFormat: {'type': 'json_object'},
    );

    final json = GroqClient.extractJson(raw);
    if (json == null) {
      throw FormatException('Groq returned non-JSON contract analysis: $raw');
    }

    // Override gravamen con el del mock (fuente de verdad — el LLM no debe
    // inventar el estado registral).
    return ContractAnalysis.fromJson({
      ...json,
      'contract_text': contractText,
      'gravamen_check': gravamen.toJson(),
      'contract_type': (json['contract_type'] as String?) ?? declaredType,
    });
  }
}
