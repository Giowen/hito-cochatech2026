import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lead.dart';

/// LeadsRepository — inbox de leads del agente.
///
/// **Storage**:
///   - **Seed**: `assets/seed/leads.json` con 4 leads pre-creados que dan
///     contexto al demo (pipeline poblado mix hot/warm/cold).
///   - **Runtime**: SharedPreferences con la lista mutada (incluye seed +
///     leads creados durante la sesión por voice queries del cliente).
///
/// El SharedPreferences se hidrata desde el seed en el primer load y queda
/// como source-of-truth para mutaciones (markContacted, addLead, etc).
///
/// **Phase 2**: swap a Supabase con realtime subscriptions para que el agente
/// vea leads nuevos en vivo sin refresh. Por ahora el provider se invalida
/// manualmente cuando hay cambios.
class LeadsRepository {
  /// Bumpea esta versión cuando cambia el shape del Lead o el contenido del
  /// seed JSON — invalida el cache de SharedPrefs y fuerza re-hidratación
  /// desde el seed fresco. Sin esto, los leads viejos persistidos en el
  /// device se mantienen aunque cambiemos el JSON.
  static const _storageKey = 'hito.leads.v2';

  /// Lee leads desde SharedPreferences. Si vacío, hidrata desde seed y persiste.
  Future<List<Lead>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        return list
            .map((j) => Lead.fromJson(j as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('[Hito.Leads] failed to decode stored leads: $e');
        // Cae al seed si el formato está corrupto.
      }
    }
    final seed = await _loadFromSeed();
    await _persist(seed);
    return seed;
  }

  Future<List<Lead>> _loadFromSeed() async {
    try {
      final raw = await rootBundle.loadString('assets/seed/leads.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final list = (decoded['leads'] as List?) ?? const [];
      return list
          .map((j) => Lead.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[Hito.Leads] seed load failed: $e');
      return const [];
    }
  }

  Future<void> _persist(List<Lead> leads) async {
    final prefs = await SharedPreferences.getInstance();
    final list = leads.map((l) => l.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(list));
  }

  /// Agrega un lead nuevo al tope de la lista (el más reciente arriba).
  Future<List<Lead>> add(Lead lead) async {
    final current = await getAll();
    // Si ya existe un lead con mismo profile (ej. user duplicó voice query),
    // reemplazar el existente en vez de duplicar.
    final filtered =
        current.where((l) => l.id != lead.id).toList(growable: false);
    final updated = [lead, ...filtered];
    await _persist(updated);
    return updated;
  }

  /// Update status / lastContactAt / notes de un lead existente.
  Future<List<Lead>> update(Lead lead) async {
    final current = await getAll();
    final updated = current.map((l) => l.id == lead.id ? lead : l).toList();
    await _persist(updated);
    return updated;
  }

  /// Reset al seed — útil para "limpiar demo" desde un menú admin.
  Future<List<Lead>> resetToSeed() async {
    final seed = await _loadFromSeed();
    await _persist(seed);
    return seed;
  }
}
