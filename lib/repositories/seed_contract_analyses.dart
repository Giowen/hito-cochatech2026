import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

import '../models/contract_analysis.dart';

/// Repositorio in-memory de análisis de contratos pre-computados para las
/// propiedades del seed. **No hace red, no consulta LLM** — devuelve datos
/// estáticos diseñados para que el Copiloto Legal abra instantáneo durante
/// la demo y para uso real cuando el agente todavía no subió un PDF custom.
///
/// **Flow**:
///   1. `analyzeAnticreticoFor(property)` consulta primero este repo.
///   2. HIT → retorna en <50ms (load del asset es cacheado en memoria).
///   3. MISS → fallback a cache Supabase → LLM (el path lento de antes).
///
/// El JSON soporta:
///   - Entries específicas: clave `"{property_id}:{contract_type}"`
///   - Entry default: clave `"_default:{contract_type}"`
///     — usada cuando la propiedad no tiene análisis dedicado pero el
///       tipo de contrato sí (anticrético, compraventa, etc).
///
/// El gravamen_check del JSON se usa tal cual (no se hace cruce con
/// GravamenMockService) porque el JSON ya tiene la versión final del check.
class SeedContractAnalyses {
  static Map<String, ContractAnalysis>? _cache;

  /// Lee el JSON del seed bundle. Llamado lazy (primer get).
  static Future<void> _load() async {
    if (_cache != null) return;
    final raw = await rootBundle.loadString('assets/seed/contract_analyses.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final out = <String, ContractAnalysis>{};
    for (final entry in decoded.entries) {
      if (entry.key.startsWith('_description') ||
          entry.key.startsWith('_schema')) {
        continue;
      }
      final value = entry.value;
      if (value is! Map<String, dynamic>) continue;
      try {
        out[entry.key] = ContractAnalysis.fromJson({
          ...value,
          // El contract_text se inyecta desde el sample real cuando el
          // service responde — aquí queda vacío.
          'contract_text': '',
        });
      } catch (_) {
        // Entry malformada → la saltamos, no rompemos load.
      }
    }
    _cache = out;
  }

  /// Devuelve análisis pre-computado o null si no hay match.
  static Future<ContractAnalysis?> get({
    required String propertyId,
    required String contractType,
  }) async {
    await _load();
    final cache = _cache!;
    final specific = cache['$propertyId:$contractType'];
    if (specific != null) return specific;
    return cache['_default:$contractType'];
  }

  /// Invalida cache — útil para tests que mockean el JSON.
  static void invalidate() => _cache = null;
}
