import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';

import '../models/match_result.dart';
import 'match_cache_repository.dart';

/// Cache de scoring AI por (property_id, profile_hash) sobre Appwrite.
///
/// Appwrite no tiene `upsert` por clave compuesta como Supabase
/// (`onConflict`). Lo emulamos con un **documentId determinístico** derivado de
/// `(propertyId, profileHash)`: crear→si existe (409) actualizar. Así el mismo
/// par siempre mapea al mismo documento y no se duplican filas.
///
/// `profile_json` se guarda como String (JSON) porque Appwrite no tiene un tipo
/// JSON nativo; en lectura no se necesita para reconstruir el `MatchResult`.
class AppwriteMatchCacheRepository implements MatchCacheRepository {
  final Databases _db;
  final String _databaseId;
  final String collectionId;

  AppwriteMatchCacheRepository({
    required Databases databases,
    required String databaseId,
    this.collectionId = 'match_scoring_cache',
  })  : _db = databases,
        _databaseId = databaseId;

  @override
  Future<MatchResult?> get({
    required String propertyId,
    required String profileHash,
  }) async {
    try {
      final res = await _db.listDocuments(
        databaseId: _databaseId,
        collectionId: collectionId,
        queries: [
          Query.equal('property_id', propertyId),
          Query.equal('profile_hash', profileHash),
          Query.limit(1),
        ],
      );
      if (res.documents.isEmpty) return null;
      final row = res.documents.first.data;
      List<String> readList(dynamic v) =>
          ((v as List?) ?? const []).cast<String>();

      return MatchResult.fromJson({
        'property_id': row['property_id'],
        'client_profile_id': '',
        'compatibility_percent':
            (row['compatibility_percent'] as num?)?.toInt() ?? 0,
        'explanation': row['explanation'] as String? ?? '',
        'recommended': readList(row['recommended']),
        'considerations': readList(row['considerations']),
        'risks': readList(row['risks']),
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
    final data = {
      'property_id': propertyId,
      'profile_hash': profileHash,
      'profile_json': jsonEncode(profileJson),
      'compatibility_percent': result.compatibilityPercent,
      'explanation': result.explanation,
      'recommended': result.recommended,
      'considerations': result.considerations,
      'risks': result.risks,
      'tags_matched': result.tagsMatched,
      'tags_missing': result.tagsMissing,
      'llm_model': llmModel,
    };
    final docId = _docId(propertyId, profileHash);
    try {
      await _db.createDocument(
        databaseId: _databaseId,
        collectionId: collectionId,
        documentId: docId,
        data: data,
      );
    } on AppwriteException catch (e) {
      if (e.code == 409) {
        // Ya existe → actualizamos (re-score del mismo par).
        try {
          await _db.updateDocument(
            databaseId: _databaseId,
            collectionId: collectionId,
            documentId: docId,
            data: data,
          );
        } catch (e2) {
          debugPrint('[Hito.MatchCache] update failed: $e2');
        }
      } else {
        debugPrint('[Hito.MatchCache] upsert failed: $e');
      }
    } catch (e) {
      debugPrint('[Hito.MatchCache] upsert failed: $e');
    }
  }

  /// ID determinístico y válido (≤36 chars, charset Appwrite) a partir de la
  /// clave compuesta. FNV-1a 64-bit con `BigInt` (estable en Web, donde `int`
  /// es de 53 bits).
  static String _docId(String propertyId, String profileHash) {
    final key = '$propertyId|$profileHash';
    final mask = (BigInt.one << 64) - BigInt.one;
    final prime = BigInt.from(1099511628211);
    var hash = BigInt.parse('14695981039346656037');
    for (final unit in utf8.encode(key)) {
      hash = (hash ^ BigInt.from(unit)) & mask;
      hash = (hash * prime) & mask;
    }
    return 'm${hash.toRadixString(16)}';
  }
}
