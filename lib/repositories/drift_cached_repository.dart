import 'package:flutter/foundation.dart';
import '../db/hito_db.dart';
import '../models/property.dart';
import 'property_repository.dart';

/// DriftCachedRepository — offline-first wrapper sobre cualquier
/// `PropertyRepository` remoto (Appwrite en producción).
///
/// Strategy "Stale While Revalidate":
///   1. `getAll()` retorna Drift cache inmediato (fast UI, funciona offline).
///   2. Background fetch desde el remoto → replaceAll a Drift.
///   3. Si cache vacío (cold start), bloquea esperando el remoto → cachea → retorna.
///   4. Si el remoto falla y cache vacío → throw → FallbackPropertyRepository
///      arriba detecta y usa InMemoryPropertyRepository (seed JSON).
///
/// Esta arquitectura es CRÍTICA en demo: si el venue tiene WiFi inestable o el
/// backend tiene latencia alta, Drift sirve data en <50ms. El refresh ocurre
/// async en background — no bloquea.
class DriftCachedRepository implements PropertyRepository {
  final PropertyRepository remote;
  final HitoDatabase db;

  /// TTL del cache antes de considerarlo "stale" y forzar revalidation.
  static const Duration cacheTtl = Duration(minutes: 5);

  DriftCachedRepository({
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
      // Cold start: necesitamos data, esperamos el remoto.
      try {
        final fromRemote = await remote.getAll();
        await db.replaceAll(fromRemote);
        return fromRemote;
      } catch (e) {
        debugPrint('[Hito] Cold-start remote fetch failed: $e');
        rethrow; // FallbackPropertyRepository arriba lo cacha.
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

    try {
      final fromRemote = await remote.getById(id);
      if (fromRemote != null) {
        await db.upsertProperties([fromRemote]);
      }
      return fromRemote;
    } catch (e) {
      debugPrint('[Hito] getById remote failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> insert(Property property) async {
    await remote.insert(property);
    // Optimistic local update: agrega a Drift inmediatamente.
    await db.upsertProperties([property]);
  }

  /// Refresh cache desde el remoto sin bloquear UI.
  Future<void> _refreshInBackground() async {
    try {
      final fromRemote = await remote.getAll();
      await db.replaceAll(fromRemote);
      debugPrint('[Hito] Drift cache refreshed (${fromRemote.length} props)');
    } catch (e) {
      debugPrint('[Hito] Background refresh failed (cache sigue válido): $e');
    }
  }

  /// Trigger explícito de sync — útil pre-demo para garantizar data fresca.
  Future<void> syncNow() async {
    await _refreshInBackground();
  }
}
