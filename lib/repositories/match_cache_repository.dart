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

/// Cache no-op para tests o cuando el backend no esté disponible. Siempre miss.
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
