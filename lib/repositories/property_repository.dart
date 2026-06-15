import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import '../models/property.dart';

/// Contract repository de propiedades.
///
/// **MVP (hackathon)**: `InMemoryPropertyRepository` carga seed JSON desde assets.
/// Cero red, cero costo. Datos hardcoded canónicos del claude-design.
///
/// **Phase 2 (post-MVP, ver ARCHITECTURE.md)**: `DriftPropertyRepository` para
/// offline-first con sync incremental contra Supabase. La arquitectura permite:
///   - Lectura local-first (cero latencia)
///   - Sync incremental background (delta queries por updated_at)
///   - Conflict resolution last-write-wins por defecto, configurable per-field
///   - Queue de mutations offline → flush al recuperar conexión
///
/// Swap MVP → Phase 2 = 1 línea en `lib/providers.dart::propertyRepositoryProvider`.
/// Services (MatchingService/ValuationService/ContractAnalysisService) no se tocan.
abstract class PropertyRepository {
  /// Retorna todas las propiedades activas (status='activa').
  Future<List<Property>> getAll();

  /// Retorna la propiedad por id, o null si no existe.
  Future<Property?> getById(String id);

  /// Inserta una nueva propiedad. Si la implementación cachea (Drift), el
  /// cache se actualiza tras el insert remoto exitoso.
  Future<void> insert(Property property);
}

/// Impl para MVP: carga `assets/seed/properties.json` y cachea en memoria.
/// Cero red, determinístico, cero variabilidad — ideal para demo path.
class InMemoryPropertyRepository implements PropertyRepository {
  List<Property>? _cache;

  @override
  Future<List<Property>> getAll() async {
    if (_cache != null) return _cache!;
    final jsonString =
        await rootBundle.loadString('assets/seed/properties.json');
    final list = jsonDecode(jsonString) as List;
    _cache = list
        .map((j) => Property.fromJson(j as Map<String, dynamic>))
        .toList();
    return _cache!;
  }

  @override
  Future<Property?> getById(String id) async {
    final all = await getAll();
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<void> insert(Property property) async {
    final all = await getAll();
    _cache = [property, ...all];
  }

  /// Resetea el cache (útil para tests).
  void invalidate() => _cache = null;
}

/// FallbackPropertyRepository — wrap dos repos. Primary first; si falla (o
/// devuelve vacío en getAll), usa fallback. Útil para Appwrite + InMemory
/// safety net en demo.
class FallbackPropertyRepository implements PropertyRepository {
  final PropertyRepository primary;
  final PropertyRepository fallback;

  FallbackPropertyRepository({
    required this.primary,
    required this.fallback,
  });

  @override
  Future<List<Property>> getAll() async {
    try {
      final result = await primary.getAll();
      if (result.isEmpty) {
        debugPrint('[Hito] Primary repo returned empty, using fallback');
        return fallback.getAll();
      }
      return result;
    } catch (e, stack) {
      debugPrint('[Hito] Primary repo failed, falling back to seed JSON: $e');
      debugPrint(stack.toString());
      return fallback.getAll();
    }
  }

  @override
  Future<Property?> getById(String id) async {
    try {
      return await primary.getById(id);
    } catch (e) {
      debugPrint('[Hito] Primary repo.getById failed, falling back: $e');
      return fallback.getById(id);
    }
  }

  @override
  Future<void> insert(Property property) async {
    // Insert SIEMPRE va al primary (backend real). El fallback InMemory local
    // no debería recibir writes — si primary falla, el insert falla.
    await primary.insert(property);
  }
}

// ── Phase 2 sketch (no implementar en MVP) ────────────────────────
//
// class DriftPropertyRepository implements PropertyRepository {
//   final HitoDatabase _db;            // Drift-generated
//   final SupabaseClient _supabase;     // Auth + REST
//   final SyncQueue _syncQueue;         // Offline queue
//
//   @override
//   Future<List<Property>> getAll() async {
//     // 1. Lee de Drift local (instantáneo, funciona offline)
//     final local = await (_db.select(_db.properties)
//           ..where((p) => p.listingStatus.equals('activa')))
//         .get();
//
//     // 2. Background sync (no bloquea UI)
//     unawaited(_syncIncrementalInBackground());
//
//     return local.map((row) => row.toModel()).toList();
//   }
//
//   Future<void> _syncIncrementalInBackground() async {
//     final lastSync = await _db.metadataDao.getLastSync('properties');
//     final updates = await _supabase
//         .from('properties')
//         .select()
//         .gt('updated_at', lastSync.toIso8601String());
//     await _db.propertiesDao.upsertMany(updates);
//     await _db.metadataDao.setLastSync('properties', DateTime.now());
//   }
//   // ... etc
// }
//
// Escala a 10,000 agentes × 100,000 propiedades porque:
//   - Cada cliente solo lee/escribe SUS propias propiedades (RLS Supabase)
//   - Drift local-first = 0 round-trips a Supabase en hot path
//   - Sync incremental = O(delta) no O(N)
//   - R2 para fotos/PDFs = $0.015/GB/mes vs $0.023 S3
//   - Groq pay-per-call = $0.00006/property scoring × cache = ~$0/agent/month
//   - Total infra cost @ 10K agents / 100K props: <$500/mes
//   - $5/agente/mes × 10K = $50K/mes revenue
//   - Margin: 99%
