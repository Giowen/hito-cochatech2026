import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/valuation_report.dart';

/// Cache de valuaciones AI por property_id.
///
/// Estrategia: insert-only (no upsert). Cada nueva valuación es un row con
/// timestamp. `get()` retorna el más reciente. Esto preserva historial para
/// análisis posterior (cómo evolucionó la valoración de una propiedad) sin
/// complicar el flujo del MVP.
///
/// Para invalidación manual (agent fuerza nuevo cómputo después de un cambio
/// de mercado): pasar `useCache: false` a `ValuationService.valuate()`.
abstract class ValuationCacheRepository {
  Future<ValuationReport?> getLatest(String propertyId);
  Future<void> insert(ValuationReport report);
}

class SupabaseValuationCacheRepository implements ValuationCacheRepository {
  final SupabaseClient _client;

  SupabaseValuationCacheRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  @override
  Future<ValuationReport?> getLatest(String propertyId) async {
    try {
      final rows = await _client
          .from('valuation_reports')
          .select()
          .eq('property_id', propertyId)
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) return null;
      final row = rows.first;
      return ValuationReport(
        propertyId: row['property_id'] as String,
        estimatedValueBob: (row['estimated_value_bob'] as num).toInt(),
        listedValueBob: (row['listed_value_bob'] as num? ?? 0).toInt(),
        deltaPercent: (row['delta_percent'] as num? ?? 0).toDouble(),
        estimatedValueUsdParalelo:
            (row['estimated_value_usd_paralelo'] as num? ?? 0).toInt(),
        usdParaleloRateUsed:
            (row['usd_paralelo_rate_used'] as num? ?? 10.20).toDouble(),
        comparables:
            ((row['comparables'] as List?) ?? const []).cast<String>(),
        confidenceScore:
            (row['confidence_score'] as num? ?? 0.7).toDouble(),
        recommendationForAgent:
            row['recommendation_for_agent'] as String? ?? '',
        recommendationForClient:
            row['recommendation_for_client'] as String? ?? '',
        reasoning: row['reasoning'] as String? ?? '',
        estimatedValueUsdLow:
            (row['estimated_value_usd_low'] as num?)?.toInt(),
        estimatedValueUsdHigh:
            (row['estimated_value_usd_high'] as num?)?.toInt(),
        factors: ((row['factors'] as List?) ?? const []).cast<String>(),
        comparableDetails:
            ((row['comparable_details'] as List?) ?? const []).cast<String>(),
      );
    } catch (e) {
      debugPrint('[Hito.ValuationCache] getLatest failed: $e');
      return null;
    }
  }

  @override
  Future<void> insert(ValuationReport report) async {
    try {
      await _client.from('valuation_reports').insert({
        'property_id': report.propertyId,
        'estimated_value_bob': report.estimatedValueBob,
        'estimated_value_usd_paralelo': report.estimatedValueUsdParalelo,
        if (report.estimatedValueUsdLow != null)
          'estimated_value_usd_low': report.estimatedValueUsdLow,
        if (report.estimatedValueUsdHigh != null)
          'estimated_value_usd_high': report.estimatedValueUsdHigh,
        'listed_value_bob': report.listedValueBob,
        'delta_percent': report.deltaPercent,
        'usd_paralelo_rate_used': report.usdParaleloRateUsed,
        'comparables': report.comparables,
        'comparable_details': report.comparableDetails,
        'factors': report.factors,
        'confidence_score': report.confidenceScore,
        'recommendation_for_agent': report.recommendationForAgent,
        'recommendation_for_client': report.recommendationForClient,
        'reasoning': report.reasoning,
      });
    } catch (e) {
      debugPrint('[Hito.ValuationCache] insert failed: $e');
    }
  }
}

class NoOpValuationCacheRepository implements ValuationCacheRepository {
  @override
  Future<ValuationReport?> getLatest(String propertyId) async => null;

  @override
  Future<void> insert(ValuationReport report) async {}
}
