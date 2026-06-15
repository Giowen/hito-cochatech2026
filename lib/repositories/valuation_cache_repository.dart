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

class NoOpValuationCacheRepository implements ValuationCacheRepository {
  @override
  Future<ValuationReport?> getLatest(String propertyId) async => null;

  @override
  Future<void> insert(ValuationReport report) async {}
}
