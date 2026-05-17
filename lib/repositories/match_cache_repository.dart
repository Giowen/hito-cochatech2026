import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/match_result.dart';

/// Cache de scoring AI por (property_id, profile_hash).
///
/// El primer score de una propiedad para un perfil dado llama a Groq y
/// guarda aquí. Subsiguientes calls del mismo perfil retornan el cache
/// hit en una sola query a Supabase.
///
/// Si Supabase falla (cold cache + network down), get retorna null y el
/// caller cae al LLM directo. Write errors se loggean y swallowen — el
/// próximo run reintentará.
abstract class MatchCacheRepository {
  Future<MatchResult?> get({
    required String propertyId,
    required String profileHash,
  });

  Future<void> upsert({
    required String propertyId,
    required String profileHash,
    required Map<String, dynamic> profileJson,
    required MatchResult result,
    String llmModel = 'llama-3.3-70b-versatile',
  });
}

class SupabaseMatchCacheRepository implements MatchCacheRepository {
  final SupabaseClient _client;

  SupabaseMatchCacheRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  @override
  Future<MatchResult?> get({
    required String propertyId,
    required String profileHash,
  }) async {
    try {
      final rows = await _client
          .from('match_scoring_cache')
          .select()
          .eq('property_id', propertyId)
          .eq('profile_hash', profileHash)
          .limit(1);
      if (rows.isEmpty) return null;
      final row = rows.first;
      List<String> readList(dynamic v) =>
          ((v as List?) ?? const []).cast<String>();

      // v9 schema: el cache puede tener filas con considerations/risks
      // (columnas nuevas) o filas viejas con positive_factors/negative_factors.
      // MatchResult.fromJson hace el backward compat — usamos esa misma lógica.
      return MatchResult.fromJson({
        'property_id': row['property_id'],
        'client_profile_id': '',
        'compatibility_percent':
            (row['compatibility_percent'] as num?)?.toInt() ?? 0,
        'explanation': row['explanation'] as String? ?? '',
        // Columnas nuevas (post v9) si existen, si no fallback a las viejas
        // vía fromJson.
        'recommended': readList(row['recommended']),
        'considerations': readList(row['considerations']),
        'risks': readList(row['risks']),
        'positive_factors': readList(row['positive_factors']),
        'negative_factors': readList(row['negative_factors']),
        'tags_matched': readList(row['tags_matched']),
        'tags_missing': readList(row['tags_missing']),
      });
    } catch (e) {
      debugPrint('[Hito.MatchCache] get failed: $e');
      return null;
    }
  }

  @override
  Future<void> upsert({
    required String propertyId,
    required String profileHash,
    required Map<String, dynamic> profileJson,
    required MatchResult result,
    String llmModel = 'llama-3.3-70b-versatile',
  }) async {
    try {
      await _client.from('match_scoring_cache').upsert(
        {
          'property_id': propertyId,
          'profile_hash': profileHash,
          'profile_json': profileJson,
          'compatibility_percent': result.compatibilityPercent,
          'explanation': result.explanation,
          // Escribimos también las viejas para que filas v9 puedan ser leídas
          // por código v8 si rolleamos. recommended/risks como
          // positive_factors/negative_factors para back-compat; considerations
          // va aparte (si la columna existe; si no, Supabase la ignora con
          // schema mismatch — pero Postgres NO la ignora, tira error. Mejor
          // omitir esa columna nueva en escritura hasta que esté en schema).
          'positive_factors': result.recommended,
          'negative_factors': result.risks,
          'tags_matched': result.tagsMatched,
          'tags_missing': result.tagsMissing,
          'llm_model': llmModel,
        },
        onConflict: 'property_id,profile_hash',
      );
    } catch (e) {
      debugPrint('[Hito.MatchCache] upsert failed: $e');
    }
  }
}

/// Cache no-op para tests o cuando Supabase no esté disponible. Siempre miss.
class NoOpMatchCacheRepository implements MatchCacheRepository {
  @override
  Future<MatchResult?> get({
    required String propertyId,
    required String profileHash,
  }) async =>
      null;

  @override
  Future<void> upsert({
    required String propertyId,
    required String profileHash,
    required Map<String, dynamic> profileJson,
    required MatchResult result,
    String llmModel = 'llama-3.3-70b-versatile',
  }) async {}
}
