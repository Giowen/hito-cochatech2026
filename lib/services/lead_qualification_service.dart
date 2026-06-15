import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../models/client_profile.dart';
import '../models/property.dart';
import '../utils/tc_paralelo.dart';
import 'groq_client.dart';

/// Resultado de calificar un lead. El agente lo ve en LeadDetailScreen para
/// decidir si invertir tiempo, qué pitch usar y con qué urgencia responder.
class LeadQualification {
  /// Score 0-100. >=75 caliente, 50-74 tibio, <50 frío. Drives `LeadBucket`.
  final int score;

  /// Razones específicas (3-5 bullets cortos) que el agente ve para entender
  /// el score. No genérico — debe citar hechos del profile.
  final List<String> reasoning;

  const LeadQualification({
    required this.score,
    required this.reasoning,
  });
}

/// LeadQualificationService — convierte un ClientProfile + contexto del mercado
/// en un score de viabilidad para que el agente sepa qué leads priorizar.
///
/// **Flow**: profile → Groq Llama 3.3 con prompt que conoce el mercado boliviano →
/// devuelve score 0-100 + reasoning bullets. Fallback heurístico si Groq falla.
///
/// **Por qué importa**: el desafío dice que los agentes "pierden decenas de horas
/// semanales calificando contactos no viables". Este servicio es el corazón de
/// la parte "calificación automática" del spec.
class LeadQualificationService {
  final GroqClient _groqClient;

  LeadQualificationService({GroqClient? groqClient})
      : _groqClient = groqClient ?? GroqClient();

  static const _systemPrompt = '''
Eres un evaluador de leads inmobiliarios en Oruro, Bolivia (2026). Tu
trabajo es darle al agente un score 0-100 de qué tan viable es un cliente
potencial para que sepa a quién llamar primero.

CONTEXTO DEL MERCADO ORURO 2026:
- TC paralelo 10.20 Bs/USD (oficial 6.96 — no aplica para inmobiliaria).
- Casa familiar 3-4 dorm en La Floresta / Agua de Castilla / Zona Norte: \$70-160k USD.
- Anticrético típico: 12-18% del valor de venta.
- Alquiler centro 1-2 dorm: \$200-450/mes.
- Departamento moderno 2-3 dorm La Floresta / Centro: \$50-110k.

CRITERIOS DE SCORING (suma 100 puntos máximo):

A. PRESUPUESTO REALISTA vs zona pedida (35 pts):
   - Cumple rangos típicos → 35 pts
   - 15-30% por debajo de mercado → 20-25 pts (negociable pero ajustado)
   - Más de 40% por debajo → 5-10 pts (irrealista)
   - Por encima del mercado → 35 pts (puede mejorar opciones)
   - Vago / sin presupuesto explícito → 15 pts

B. URGENCIA Y MOTIVACIÓN (25 pts):
   - Menciona timeline ("en enero", "para fin de mes", "urgente") → 25 pts
   - Razón clara ("hijos empiezan facultad", "mudanza por trabajo") → 25 pts
   - Sin timing pero contexto sólido → 15 pts
   - "Buscando opciones, no hay apuro" → 8 pts
   - Ninguna pista → 5 pts

C. CLARIDAD DE CRITERIOS (20 pts):
   - Tipo + modalidad + dorms + zona + tags específicos → 20 pts
   - Falta una o dos cosas → 12-15 pts
   - Vago / contradictorio / "lo que sea" → 5 pts

D. MODALIDAD vs comisión esperada del agente (10 pts):
   - Compra: 10 pts (mayor comisión)
   - Anticrético: 8 pts (decente, sobre todo si capital alto)
   - Alquiler corto: 4 pts (comisión chica, alta rotación)

E. SEÑALES PRO DE CONVERSIÓN (10 pts):
   - "Ya vimos X propiedades pero no nos convencieron" → comprador activo
   - Auto-presentación con nombre → 5 pts
   - Familia/contexto personal claro → 5 pts

REGLAS:
- NO invertir scores. Un lead claramente flojo (score 20) NO es "frío con
  potencial" — es frío y punto. El agente prefiere honestidad.
- Razones específicas, NO genéricas. Cita el presupuesto, la zona, el
  timeline del cliente.
- Si el profile es muy básico (voice query corto) baja el score por
  falta de claridad — el agente sabe que tiene que llamar para profundizar.

OUTPUT JSON estricto (sin markdown):
{
  "score": int 0-100,
  "reasoning": [
    string array de 3-5 bullets cortos (max 15 palabras cada uno),
    cada bullet cita un HECHO específico del profile
  ]
}
''';

  /// Califica el profile. Si Groq falla, usa fallback heurístico.
  Future<LeadQualification> qualify({
    required ClientProfile profile,
    List<Property> inventory = const [],
  }) async {
    final userPrompt = _buildUserPrompt(profile, inventory);

    try {
      final raw = await _groqClient.chat(
        messages: [
          const {'role': 'system', 'content': _systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        model: GroqModels.voiceExtract,
        temperature: 0.1,
        responseFormat: {'type': 'json_object'},
      );

      final json = GroqClient.extractJson(raw);
      if (json == null) {
        throw FormatException('Groq returned non-JSON for lead qualification');
      }

      final score = (json['score'] as num?)?.toInt().clamp(0, 100) ?? 50;
      final reasoning =
          ((json['reasoning'] as List?) ?? const []).cast<String>();
      debugPrint(
        '[Hito.Lead] qualified score=$score reasons=${reasoning.length}',
      );
      return LeadQualification(score: score, reasoning: reasoning);
    } catch (e) {
      debugPrint('[Hito.Lead] qualification fallback (groq failed): $e');
      return _heuristicFallback(profile);
    }
  }

  String _buildUserPrompt(
      ClientProfile profile, List<Property> inventory) {
    final budgetUsd =
        '\$${TcParalelo.bobToUsd(profile.budgetMin)} - \$${TcParalelo.bobToUsd(profile.budgetMax)} USD';
    final inventorySnapshot = inventory.isEmpty
        ? 'Sin inventario disponible'
        : inventory.take(8).map((p) {
            final priceK = (p.priceUsdParalelo / 1000).toStringAsFixed(0);
            return '${p.neighborhood ?? "n/a"} · ${p.type} · '
                '${p.bedrooms}d · \$${priceK}k';
          }).join('\n  - ');

    return 'PERFIL DEL LEAD:\n${jsonEncode(profile.toJson())}\n\n'
        'PRESUPUESTO EN USD PARALELO: $budgetUsd\n\n'
        'INVENTARIO ACTUAL DEL AGENTE (referencia para comparar realismo):\n'
        '  - $inventorySnapshot\n\n'
        'TRANSCRIPT ORIGINAL DE VOZ:\n${profile.voiceInputTranscript ?? "(vacío)"}\n\n'
        'Califica el lead 0-100 y da 3-5 razones específicas citando '
        'el HECHO concreto del profile que las justifica.';
  }

  /// Fallback determinístico cuando Groq no responde. Score basado en
  /// señales obvias del profile.
  LeadQualification _heuristicFallback(ClientProfile profile) {
    var score = 50;
    final reasons = <String>[];

    // Presupuesto
    final budgetUsd = TcParalelo.bobToUsd(profile.budgetMax);
    if (budgetUsd >= 100000) {
      score += 15;
      reasons.add('Presupuesto \$${budgetUsd ~/ 1000}k USD — viable para compra.');
    } else if (budgetUsd >= 30000) {
      score += 8;
      reasons.add('Presupuesto \$${budgetUsd ~/ 1000}k — alcance acotado.');
    } else {
      reasons.add('Presupuesto bajo — validar tipo de operación.');
    }

    // Modalidad
    if (profile.transactionType == 'compra') {
      score += 10;
      reasons.add('Modalidad compra — comisión completa.');
    } else if (profile.transactionType == 'anticretico') {
      score += 6;
      reasons.add('Anticrético — modalidad decente.');
    } else {
      reasons.add('Alquiler — comisión menor.');
    }

    // Transcript length / claridad
    final transcript = profile.voiceInputTranscript ?? '';
    if (transcript.length > 80) {
      score += 8;
      reasons.add('Voice query detallada — criterios claros.');
    } else if (transcript.length > 30) {
      score += 3;
    } else {
      score -= 5;
      reasons.add('Query muy corta — confirmar criterios por teléfono.');
    }

    // Urgencia textual
    final urgencyTokens = ['urgente', 'enero', 'para ya', 'fin de mes', 'mudanza'];
    if (urgencyTokens.any(transcript.toLowerCase().contains)) {
      score += 12;
      reasons.add('Urgencia explícita en su mensaje.');
    }

    // Tags
    if (profile.requiredTags.isNotEmpty) {
      score += 5;
      reasons.add('Criterios específicos (${profile.requiredTags.length} tags).');
    }

    score = score.clamp(5, 95);
    return LeadQualification(
      score: score,
      reasoning: reasons.take(5).toList(),
    );
  }
}
