import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/property.dart';
import 'property_repository.dart';

/// SupabasePropertyRepository — repo real conectado a Supabase Postgres.
///
/// Tabla: `properties` en proyecto `ireqtgwedmlweufijzyl.supabase.co`.
/// RLS permisiva (anon read+write) en MVP. Phase 2: ownership por agent_id.
///
/// Para offline-first y fallback domingo si Supabase cae, wrap esta clase
/// con `FallbackPropertyRepository` o `DriftCachedSupabaseRepository` (Phase B.4).
class SupabasePropertyRepository implements PropertyRepository {
  final SupabaseClient _client;

  SupabasePropertyRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  @override
  Future<List<Property>> getAll() async {
    final rows = await _client
        .from('properties')
        .select()
        .eq('listing_status', 'activa')
        .order('compatibility', ascending: false, nullsFirst: false);

    return rows
        .map<Property>(
            (row) => Property.fromJson(_normalizeRow(row)))
        .toList(growable: false);
  }

  @override
  Future<Property?> getById(String id) async {
    final rows = await _client
        .from('properties')
        .select()
        .eq('id', id)
        .limit(1);
    if (rows.isEmpty) return null;
    return Property.fromJson(_normalizeRow(rows.first));
  }

  @override
  Future<void> insert(Property property) async {
    final row = property.toJson();
    // El schema espera int para listed_days; las listas como TEXT[] (Postgres
    // acepta JSON arrays). Limpiar campos derivados que la DB autopopula.
    row.remove('image'); // tiene default 'gradient-1'
    row['listing_status'] = 'activa';
    await _client.from('properties').insert(row);
  }

  /// Postgres BIGINT puede llegar como int o num; arrays como `List<dynamic>`.
  /// Normalizar a los tipos que Property.fromJson espera.
  Map<String, dynamic> _normalizeRow(Map<String, dynamic> row) {
    // Cast int-ish fields seguros
    int? asInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return {
      ...row,
      // Numerics defensive
      'price_bob': asInt(row['price_bob']) ?? 0,
      'price_usd_paralelo': asInt(row['price_usd_paralelo']) ?? 0,
      'area_m2': asInt(row['area_m2']) ?? 0,
      'lot_m2': asInt(row['lot_m2']),
      'bedrooms': asInt(row['bedrooms']) ?? 0,
      'bathrooms': asInt(row['bathrooms']) ?? 0,
      'parking': asInt(row['parking']) ?? 0,
      'anticretico_bob': asInt(row['anticretico_bob']),
      'year_built': asInt(row['year_built']),
      'age_years': asInt(row['age_years']) ?? 0,
      'compatibility': asInt(row['compatibility']),
      'listed_days': asInt(row['listed_days']) ?? 0,
    };
  }
}

/// FallbackPropertyRepository — wrap dos repos. Primary first; si falla, fallback.
/// Útil para Supabase + InMemory safety net en MVP demo.
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
    // Insert SIEMPRE va al primary (Supabase real). El fallback InMemory
    // local no debería recibir writes — si primary falla, el insert falla.
    await primary.insert(property);
  }
}
