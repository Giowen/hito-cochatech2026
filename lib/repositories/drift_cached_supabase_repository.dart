import 'package:flutter/foundation.dart';
import '../db/hito_db.dart';
import '../models/property.dart';
import 'property_repository.dart';
import 'supabase_property_repository.dart';

/// DriftCachedSupabaseRepository — offline-first wrapper.
///
/// Strategy "Stale While Revalidate":
///   1. `getAll()` retorna Drift cache inmediato (fast UI, funciona offline).
///   2. Background fetch desde Supabase → upsert a Drift → no-op si datos iguales.
///   3. Si cache vacío (cold start), bloquea esperando Supabase → cachea → retorna.
///   4. Si Supabase falla y cache vacío → throw → FallbackPropertyRepository
///      arriba detecta y usa InMemoryPropertyRepository (seed JSON).
///
/// Esta arquitectura es CRÍTICA domingo: si el venue tiene WiFi inestable
/// o Supabase tiene latency alta durante el pitch, Drift sirve data en <50ms.
/// El refresh de Supabase ocurre async en background — no bloquea la demo.
class DriftCachedSupabaseRepository implements PropertyRepository {
  final SupabasePropertyRepository remote;
  final HitoDatabase db;

  /// TTL del cache antes de considerarlo "stale" y forzar revalidation.
  /// 5 min es OK para MVP — listings no cambian segundo a segundo.
  static const Duration cacheTtl = Duration(minutes: 5);

  DriftCachedSupabaseRepository({
    required this.remote,
    required this.db,
  });

  @override
  Future<List<Property>> getAll() async {
    final cached = await db.getAllProperties();
    final lastCachedAt = await db.getLastCachedAt();
    final isStale = lastCachedAt == null ||
        DateTime.now().difference(lastCachedAt) > cacheTtl;

    if (cached.isEmpty) {
      // Cold start: necesitamos data, esperamos Supabase
      try {
        final fromRemote = await remote.getAll();
        await db.replaceAll(fromRemote);
        return fromRemote;
      } catch (e) {
        debugPrint('[Hito] Cold-start Supabase fetch failed: $e');
        rethrow; // FallbackPropertyRepository arriba lo cacha
      }
    }

    // Tenemos cache. Si está stale, refresh en background — no bloqueamos UI.
    if (isStale) {
      // ignore: unawaited_futures
      _refreshInBackground();
    }

    return cached;
  }

  @override
  Future<Property?> getById(String id) async {
    final cached = await db.getPropertyById(id);
    if (cached != null) return cached;

    // No en cache → fetch remoto
    try {
      final fromRemote = await remote.getById(id);
      if (fromRemote != null) {
        await db.upsertProperties([fromRemote]);
      }
      return fromRemote;
    } catch (e) {
      debugPrint('[Hito] getById Supabase failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> insert(Property property) async {
    await remote.insert(property);
    // Optimistic local update: agrega a Drift inmediatamente para no esperar
    // un refresh completo. El próximo getAll lo retorna desde cache.
    await db.upsertProperties([property]);
  }

  /// Refresh cache desde Supabase sin bloquear UI.
  Future<void> _refreshInBackground() async {
    try {
      final fromRemote = await remote.getAll();
      await db.replaceAll(fromRemote);
      debugPrint('[Hito] Drift cache refreshed (${fromRemote.length} props)');
    } catch (e) {
      debugPrint('[Hito] Background refresh failed (cache sigue válido): $e');
    }
  }

  /// Trigger explícito de sync — útil pre-pitch para garantizar data fresca.
  Future<void> syncNow() async {
    await _refreshInBackground();
  }
}
