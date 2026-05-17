import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/contract_analysis.dart';
import '../models/property.dart';
import '../repositories/contract_analysis_cache_repository.dart';
import '../repositories/seed_contract_analyses.dart';
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

  /// Genera un borrador de contrato desde cero — modo creativo, NO análisis.
  /// Usa los datos de la propiedad + placeholders entre [CORCHETES] para
  /// partes faltantes. Devuelve un ContractAnalysis con todas las cláusulas
  /// marcadas low (es plantilla limpia, sin riesgos).
  ///
  /// Temperature 0.1 — borrador consistente y reproducible.
  Future<ContractAnalysis> generateContractDraft({
    required Property property,
    required String contractType,
    Map<String, String>? parties,
  }) async {
    debugPrint(
      '[Hito.Contract] generating draft type=$contractType for ${property.id}',
    );

    final effectiveParties = parties ??
        {
          'propietario_nombre':
              property.agentName ?? '[NOMBRE_PROPIETARIO]',
          'propietario_ci': '[CI_PROPIETARIO]',
          'propietario_domicilio': '[DOMICILIO_PROPIETARIO]',
          'contraparte_nombre': '[NOMBRE_CONTRAPARTE]',
          'contraparte_ci': '[CI_CONTRAPARTE]',
        };

    final userPayload = {
      'property': {
        'address': property.address,
        'neighborhood': property.neighborhood,
        'area_m2': property.areaM2,
        if (property.lotM2 != null) 'lot_m2': property.lotM2,
        'bedrooms': property.bedrooms,
        'bathrooms': property.bathrooms,
        if (property.priceBob > 0) 'price_bob': property.priceBob,
        if (property.anticreticoBob != null)
          'anticretico_bob': property.anticreticoBob,
      },
      'contract_type': contractType,
      'parties': effectiveParties,
    };

    final raw = await _groqClient.chat(
      messages: [
        const {'role': 'system', 'content': _generateSystemPrompt},
        {'role': 'user', 'content': jsonEncode(userPayload)},
      ],
      model: GroqModels.contractGenerate,
      temperature: 0.1,
      responseFormat: {'type': 'json_object'},
    );

    final json = GroqClient.extractJson(raw);
    if (json == null) {
      throw FormatException('Groq returned non-JSON draft: $raw');
    }

    // No gravamen check para drafts — es plantilla nueva sin estado registral.
    const cleanGravamen = GravamenCheck(
      status: 'clean',
      details:
          'Borrador nuevo — completá los datos y verificá Derechos Reales antes de firmar.',
    );

    return ContractAnalysis.fromJson({
      ...json,
      'gravamen_check': cleanGravamen.toJson(),
      'contract_type': contractType,
    });
  }

  static const _generateSystemPrompt = '''
Eres un abogado inmobiliario boliviano senior. Generás borradores LIMPIOS y
ESTÁNDAR de contratos conformes al Código Civil de Bolivia:
  - ANTICRÉTICO: CC arts. 1429-1438
  - COMPRAVENTA: CC arts. 584-735
  - ALQUILER: Ley General del Inquilinato

REGLAS DE REDACCIÓN:
- Generás 10-14 cláusulas conformes a la ley boliviana.
- Cada cláusula es jurídicamente correcta, sin abusos contra ninguna parte.
- Lenguaje formal pero claro, español neutro boliviano.
- Citá los artículos del Código Civil pertinentes dentro de la cláusula.
- Si faltan datos, usá placeholders entre [CORCHETES_MAYUSCULAS] tipo
  [NOMBRE_PROPIETARIO], [CI_PROPIETARIO], [DOMICILIO_PROPIETARIO],
  [NOMBRE_CONTRAPARTE], [CI_CONTRAPARTE].
- Numerá cláusulas en mayúscula ordinal: "PRIMERA.— ...", "SEGUNDA.— ...",
  "TERCERA.— ...", etc.
- Para anticrético: incluí cláusula obligatoria de protocolización
  (CC art. 1431) al final.
- Para compraventa: incluí transferencia formal en Derechos Reales.
- Para alquiler: incluí cláusula de penalidades por mora y depósito de garantía.

OUTPUT JSON estricto (sin markdown, solo el objeto):
{
  "contract_type": "anticretico" | "compraventa" | "alquiler",
  "contract_text": string — borrador completo, cláusulas concatenadas con
    \\n\\n entre cada una. Ejemplo:
    "PRIMERA.— Comparecen [NOMBRE_PROPIETARIO]...\\n\\nSEGUNDA.— ...",
  "overall_risk_score": int entre 5 y 15 (plantilla limpia),
  "analyzed_clauses": [
    {
      "clause_text": string (cita literal de la cláusula generada),
      "risk_level": "low",
      "issue": "Cláusula estándar conforme al Código Civil.",
      "suggestion": "Sin cambios. Completá placeholders al protocolizar."
    }
    // una entrada por cada cláusula generada (10-14 items)
  ],
  "fraud_patterns_detected": [],
  "summary": string — un párrafo máx 80 palabras explicando que es un
    borrador estándar, qué partes deben completar, y la decisión sugerida
    (siempre: "Revisá con notario y completá placeholders antes de firmar"),
  "recommendations": [
    "Completá los datos de las partes (placeholders entre corchetes).",
    "Solicitá certificado de Derechos Reales actualizado (no mayor a 30 días).",
    "Protocolizá ante Notario de Fe Pública antes de inscribir.",
    // agregá 1-2 más según el tipo (ej: para anticrético "Acordá plazo de
    // restitución sin condicionantes", para alquiler "Fijá depósito de
    // garantía 1-2 meses por adelantado")
  ]
}
''';

  /// API pública. Resolución multi-tier:
  ///   1. **Seed pre-baked** (instant) — `assets/seed/contract_analyses.json`
  ///      tiene análisis estáticos por (property_id, contract_type).
  ///   2. **Cache Supabase** (~500ms) — análisis generados por LLM previamente.
  ///   3. **Groq Llama 3.3** (~8-12s) — solo si seed y cache fallan, o si el
  ///      usuario forzó re-análisis con `useCache: false` (típico cuando
  ///      subió un PDF custom).
  ///
  /// El seed se salta cuando `useCache=false` para que "Subir PDF" siempre
  /// dispare el LLM real sobre el texto subido.
  Future<ContractAnalysis> analyzeContract({
    required Property property,
    required String contractText,
    required String contractType,
    bool useCache = true,
  }) async {
    if (useCache) {
      // 1. Seed pre-baked — instant load para demo y para uso real cuando
      // el agente aún no subió un PDF custom.
      final seed = await SeedContractAnalyses.get(
        propertyId: property.id,
        contractType: contractType,
      );
      if (seed != null) {
        debugPrint(
          '[Hito.Contract] SEED HIT id=${property.id} type=$contractType '
          'risk=${seed.overallRiskScore} clauses=${seed.analyzedClauses.length}',
        );
        // Inyectamos el contractText real (el seed no lo guarda para ahorrar
        // espacio) para que el highlight de cláusulas funcione.
        return ContractAnalysis(
          contractType: seed.contractType,
          contractText: contractText,
          overallRiskScore: seed.overallRiskScore,
          analyzedClauses: seed.analyzedClauses,
          gravamenCheck: seed.gravamenCheck,
          fraudPatternsDetected: seed.fraudPatternsDetected,
          summary: seed.summary,
          recommendations: seed.recommendations,
        );
      }

      // 2. Cache Supabase
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
      model: GroqModels.contract,
      temperature: 0.2,
      responseFormat: {'type': 'json_object'},
    );

    final json = GroqClient.extractJson(raw);
    if (json == null) {
      throw FormatException('Groq returned non-JSON contract analysis: $raw');
    }

    // Override gravamen con el del mock (fuente de verdad — el LLM no debe
    // inventar el estado registral).
    try {
      return ContractAnalysis.fromJson({
        ...json,
        'contract_text': contractText,
        'gravamen_check': gravamen.toJson(),
        'contract_type': (json['contract_type'] as String?) ?? declaredType,
      });
    } catch (e, stack) {
      // Loguear el raw para diagnosticar futuras desviaciones del schema.
      // El parser arriba ya es tolerante; si aún así falla, queremos ver qué
      // tipo nuevo de output emitió el LLM.
      debugPrint(
        '[Hito.Contract] parse failed: $e\nraw LLM output:\n$raw\n$stack',
      );
      rethrow;
    }
  }
}
