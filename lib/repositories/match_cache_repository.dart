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
      return MatchResult(
        propertyId: row['property_id'] as String,
        clientProfileId: '',
        compatibilityPercent: (row['compatibility_percent'] as num).toInt(),
        explanation: row['explanation'] as String? ?? '',
        positiveFactors:
            ((row['positive_factors'] as List?) ?? const []).cast<String>(),
        negativeFactors:
            ((row['negative_factors'] as List?) ?? const []).cast<String>(),
        tagsMatched: ((row['tags_matched'] as List?) ?? const []).cast<String>(),
        tagsMissing: ((row['tags_missing'] as List?) ?? const []).cast<String>(),
      );
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
          'positive_factors': result.positiveFactors,
          'negative_factors': result.negativeFactors,
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
