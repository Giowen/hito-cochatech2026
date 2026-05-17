import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/property.dart';
import '../models/valuation_report.dart';
import '../repositories/valuation_cache_repository.dart';
import '../utils/distance.dart';
import '../utils/tc_paralelo.dart';
import 'groq_client.dart';

/// ValuationService — valuación AI dinámica con Groq Llama 3.3 70B real.
///
/// **No hay demo path hardcoded.** Cada valuación se computa con LLM real
/// sobre comparables seleccionados live desde el repositorio de propiedades.
/// Resultado cachea en `valuation_reports` (Supabase) para responses instantáneos.
///
/// Flow:
///   1. `valuate(property, allProperties)` busca cache por property_id.
///   2. Cache HIT → retorna.
///   3. Cache MISS → selecciona 5 comparables (mismo tipo, ranked por distancia +
///      proximidad de precio + similitud de dormitorios) → llama Groq con
///      target + comparables + TC paralelo → parsea JSON → arma ValuationReport
///      con derived fields (USD, delta) → cachea → retorna.
///
/// Si Groq falla, lanza la excepción (la UI ya maneja AsyncError).
class ValuationService {
  final GroqClient _groqClient;
  final ValuationCacheRepository _cache;

  ValuationService({
    GroqClient? groqClient,
    ValuationCacheRepository? cache,
  })  : _groqClient = groqClient ?? GroqClient(),
        _cache = cache ?? NoOpValuationCacheRepository();

  static const _systemPrompt = '''
Eres un tasador inmobiliario senior en Cochabamba, Bolivia, con 20 años de
experiencia operando en 2025-2026.

CONTEXTO MACRO obligatorio:
- TC paralelo USD/BOB ~12.20 (vs oficial 6.96 — el oficial no aplica para
  inmobiliaria, todo se mueve en paralelo o dólares).
- Costos de construcción al alza por inflación de insumos importados.
- Plusvalía zonal típica anual: Cala Cala +6-8%, Recoleta +5%, Queru Queru
  +4-5%, Sarco +3%, periferia +2-3%.
- Antigüedad importa: año <5 → premium +5%, año >25 → -5% a -10%.

Te entregan una propiedad target + 5 comparables del mismo tipo. Estima
valor justo de mercado para 2026 considerando TC paralelo.

Devuelve JSON estricto (sin markdown):
{
  "estimated_value_bob": int (valor mid del rango, en BOB),
  "estimated_value_bob_low": int (mínimo del intervalo de confianza),
  "estimated_value_bob_high": int (máximo del intervalo),
  "confidence_score": float entre 0 y 1,
  "factors": [
    strings formateados como "+8.2% Ubicación (Cala Cala)" o
    "+3.0% Año 2021 (nueva)" o "-2.5% Año 2008 (antigua)" — máximo 6 ítems
  ],
  "recommendation_for_agent": string max 60 palabras, tono asesor al
    propietario/agente sobre estrategia de precio y timing,
  "recommendation_for_client": string max 60 palabras, tono asesor al
    comprador sobre margen de negociación,
  "reasoning": string max 70 palabras citando 2-3 comparables POR DIRECCIÓN
    O TÍTULO (NUNCA por id "p01"/"p03") y los ajustes aplicados.
}

REGLAS:
- Si el precio listado está dentro de ±5% del estimate, recomendación = "a precio".
- Si listed > estimate por más de 5%, recomendación enfatiza sobrevalor.
- Si listed < estimate por más de 5%, recomendación enfatiza oportunidad.
- Los valores en BOB son enteros, sin separadores.
- Para referirte a la antigüedad de las propiedades en factors y reasoning
  USA "año YYYY" (ej. "Año 2018"). PROHIBIDO usar "edad X años" o
  "X años de antigüedad" — siempre en formato año-de-construcción.
- En reasoning JAMÁS cites los IDs internos (p01, p02, etc). Usa SIEMPRE
  la dirección, título o calle del comparable (ej. "el comparable de
  Av. Pando", "la casa de Ladislao Cabrera"). El jurado/cliente NO debe
  ver nuestros IDs internos.
- No incluyas texto fuera del JSON.
''';

  /// API pública. Cache check → Groq → cache insert → return.
  Future<ValuationReport> valuate({
    required Property property,
    required List<Property> allProperties,
    bool useCache = true,
  }) async {
    if (useCache) {
      final cached = await _cache.getLatest(property.id);
      if (cached != null) {
        debugPrint(
          '[Hito.Valuation] cache HIT id=${property.id} '
          'mid=${cached.estimatedValueBob} BOB delta=${cached.deltaPercent.toStringAsFixed(1)}%',
        );
        return cached;
      }
    }

    debugPrint(
      '[Hito.Valuation] cache MISS id=${property.id} → Groq Llama 3.3',
    );

    final comparables = _pickComparables(property, allProperties);
    final raw = await _groqClient.chat(
      messages: [
        const {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': _buildUserPrompt(property, comparables)},
      ],
      model: GroqModels.valuation,
      temperature: 0.2,
      responseFormat: {'type': 'json_object'},
    );

    final json = GroqClient.extractJson(raw);
    if (json == null) {
      throw FormatException('Groq returned non-JSON valuation: $raw');
    }

    final estimatedBob =
        (json['estimated_value_bob'] as num?)?.toInt() ?? property.priceBob;
    final lowBob = (json['estimated_value_bob_low'] as num?)?.toInt() ??
        (estimatedBob * 0.9).round();
    final highBob = (json['estimated_value_bob_high'] as num?)?.toInt() ??
        (estimatedBob * 1.1).round();
    final listedBob = property.priceBob > 0
        ? property.priceBob
        : TcParalelo.usdToBob(property.priceUsdParalelo);
    final delta = listedBob > 0
        ? ((estimatedBob - listedBob) / listedBob) * 100.0
        : 0.0;

    final report = ValuationReport(
      propertyId: property.id,
      estimatedValueBob: estimatedBob,
      listedValueBob: listedBob,
      deltaPercent: delta,
      estimatedValueUsdParalelo: TcParalelo.bobToUsd(estimatedBob),
      estimatedValueUsdLow: TcParalelo.bobToUsd(lowBob),
      estimatedValueUsdHigh: TcParalelo.bobToUsd(highBob),
      usdParaleloRateUsed: TcParalelo.rate,
      comparables: comparables.map((p) => p.id).toList(),
      comparableDetails: _formatComparableDetails(comparables, property),
      confidenceScore:
          (json['confidence_score'] as num? ?? 0.7).toDouble().clamp(0.0, 1.0),
      factors: ((json['factors'] as List?) ?? const []).cast<String>(),
      recommendationForAgent:
          (json['recommendation_for_agent'] as String? ?? '').trim(),
      recommendationForClient:
          (json['recommendation_for_client'] as String? ?? '').trim(),
      reasoning: (json['reasoning'] as String? ?? '').trim(),
    );

    await _cache.insert(report);
    return report;
  }

  // ── Internals ───────────────────────────────────────────────────────────

  String _buildUserPrompt(Property target, List<Property> comparables) {
    // OJO: NO incluimos el `id` interno de los comparables — el LLM no debe
    // verlo para que sea imposible que lo cite en el reasoning. En vez de id
    // usa address/title que son human-readable.
    final compsJson = comparables.map((c) {
      return {
        'titulo': c.title ?? c.address,
        'direccion': c.address,
        'neighborhood': c.neighborhood,
        'price_bob': c.priceBob,
        'price_usd_paralelo': c.priceUsdParalelo,
        'area_m2': c.areaM2,
        'lot_m2': c.lotM2,
        'bedrooms': c.bedrooms,
        'bathrooms': c.bathrooms,
        'year_built': c.yearBuilt,
        'distance_to_target_km':
            double.parse(c.distanceToKm(target.coords).toStringAsFixed(2)),
      };
    }).toList();

    // Tampoco enviamos el ID del target en la serialización completa — usamos
    // una versión limpia para el prompt.
    final targetClean = Map<String, dynamic>.from(target.toJson())
      ..remove('id');

    return 'PROPIEDAD TARGET:\n${jsonEncode(targetClean)}\n\n'
        'COMPARABLES (${comparables.length} propiedades similares):\n'
        '${jsonEncode(compsJson)}\n\n'
        'TC paralelo asumido: ${TcParalelo.rate} BOB/USD';
  }

  /// Selecciona top-5 comparables por mismo tipo + score compuesto.
  /// Score (menor = mejor):
  ///   distancia_km × 0.5 + |diff_precio_M_BOB| × 0.4 + |diff_dorm| × 0.1
  ///
  /// Si <2 comparables del mismo tipo, expande a cualquier tipo.
  List<Property> _pickComparables(Property target, List<Property> all) {
    Iterable<Property> pool =
        all.where((p) => p.id != target.id && p.type == target.type);
    if (pool.length < 2) {
      pool = all.where((p) => p.id != target.id);
    }

    double score(Property p) {
      final dKm = p.distanceToKm(target.coords);
      final priceDiffM =
          ((p.priceBob - target.priceBob).abs() / 1000000.0);
      final bedDiff = (p.bedrooms - target.bedrooms).abs().toDouble();
      return dKm * 0.5 + priceDiffM * 0.4 + bedDiff * 0.1;
    }

    final sorted = pool.toList()..sort((a, b) => score(a).compareTo(score(b)));
    return sorted.take(5).toList();
  }

  /// Pre-format comparable details para la UI (ej.:
  /// "Av. Pando · 280m² · 4d · $215k · 0.8km").
  List<String> _formatComparableDetails(
    List<Property> comps,
    Property target,
  ) {
    return comps.map((c) {
      final dKm = c.distanceToKm(target.coords);
      final addressShort = c.title ?? c.address.split(',').first;
      return '$addressShort · ${c.areaM2}m² · ${c.bedrooms}d · '
          '\$${c.priceUsdParalelo}k · ${formatDistance(dKm).split(' · ').first}';
    }).toList();
  }
}
