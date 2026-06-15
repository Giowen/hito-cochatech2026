import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';

import '../models/valuation_report.dart';
import 'valuation_cache_repository.dart';

/// Cache de valuaciones AI por property_id sobre Appwrite.
///
/// Insert-only (preserva historial). `getLatest` ordena por `$createdAt` desc
/// (campo de sistema de Appwrite, equivalente al `created_at` de Supabase) y
/// retorna el documento más reciente.
class AppwriteValuationCacheRepository implements ValuationCacheRepository {
  final Databases _db;
  final String _databaseId;
  final String collectionId;

  AppwriteValuationCacheRepository({
    required Databases databases,
    required String databaseId,
    this.collectionId = 'valuation_reports',
  })  : _db = databases,
        _databaseId = databaseId;

  @override
  Future<ValuationReport?> getLatest(String propertyId) async {
    try {
      final res = await _db.listDocuments(
        databaseId: _databaseId,
        collectionId: collectionId,
        queries: [
          Query.equal('property_id', propertyId),
          Query.orderDesc('\$createdAt'),
          Query.limit(1),
        ],
      );
      if (res.documents.isEmpty) return null;
      return ValuationReport.fromJson(res.documents.first.data);
    } catch (e) {
      debugPrint('[Hito.ValuationCache] getLatest failed: $e');
      return null;
    }
  }

  @override
  Future<void> insert(ValuationReport report) async {
    try {
      await _db.createDocument(
        databaseId: _databaseId,
        collectionId: collectionId,
        documentId: ID.unique(),
        data: report.toJson(),
      );
    } catch (e) {
      debugPrint('[Hito.ValuationCache] insert failed: $e');
    }
  }
}
