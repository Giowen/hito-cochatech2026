import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import '../models/property.dart';

part 'hito_db.g.dart';

/// Drift schema: cached_properties — store Property como JSON serializado.
/// Diseño simple para MVP: 1 columna data_json, no normalization.
/// Phase 3 (post-Series A) podría normalizar columnas si necesitamos SQL queries
/// estructurados sobre cientos de miles de rows.
@DataClassName('CachedPropertyRow')
class CachedProperties extends Table {
  TextColumn get id => text()();
  TextColumn get dataJson => text()();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// HitoDatabase — Drift local DB para offline-first cache.
///
/// Cross-platform vía drift_flutter:
///   - Android/iOS: sqlite3 nativo (sqlite3_flutter_libs)
///   - Web: sqlite3 WASM (auto-fetched de CDN)
///   - Desktop: sqlite3 nativo
///
/// Schema version 1. Phase B.5+ migrations:
///   - Add valuation_reports_cache
///   - Add contract_analyses_cache
///   - Add sync_queue para writes offline
@DriftDatabase(tables: [CachedProperties])
class HitoDatabase extends _$HitoDatabase {
  HitoDatabase() : super(driftDatabase(name: 'hito_db'));

  @override
  int get schemaVersion => 1;

  /// Read all cached properties (decoded from JSON).
  Future<List<Property>> getAllProperties() async {
    final rows = await select(cachedProperties).get();
    return rows.map(_rowToProperty).toList(growable: false);
  }

  Future<Property?> getPropertyById(String id) async {
    final row = await (select(cachedProperties)
          ..where((p) => p.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    return _rowToProperty(row);
  }

  /// Upsert (insert or replace) batch de properties — usado por sync incremental.
  Future<void> upsertProperties(List<Property> properties) async {
    if (properties.isEmpty) return;
    await batch((batch) {
      for (final p in properties) {
        batch.insert(
          cachedProperties,
          CachedPropertiesCompanion(
            id: Value(p.id),
            dataJson: Value(jsonEncode(p.toJson())),
            cachedAt: Value(DateTime.now()),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// Replace full cache — uses transaction para atomicidad (clear+insert).
  Future<void> replaceAll(List<Property> properties) async {
    await transaction(() async {
      await delete(cachedProperties).go();
      await upsertProperties(properties);
    });
  }

  Future<void> clearAll() async {
    await delete(cachedProperties).go();
  }

  /// Última vez que se cacheó algo — usado para decidir si refrescar de Supabase.
  Future<DateTime?> getLastCachedAt() async {
    final query = selectOnly(cachedProperties)
      ..addColumns([cachedProperties.cachedAt.max()]);
    final row = await query.getSingleOrNull();
    return row?.read(cachedProperties.cachedAt.max());
  }

  Property _rowToProperty(CachedPropertyRow row) {
    return Property.fromJson(jsonDecode(row.dataJson) as Map<String, dynamic>);
  }
}
