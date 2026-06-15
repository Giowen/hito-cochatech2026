import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';

import '../models/contract_analysis.dart';
import 'contract_analysis_cache_repository.dart';

/// Cache de análisis de contratos por (property_id, contract_type) sobre
/// Appwrite. Insert-only; `getLatest` ordena por `$createdAt` desc.
///
/// `analyzed_clauses` (array de objetos) y `gravamen_check` (objeto) no tienen
/// tipo nativo en Appwrite → se guardan como String JSON y se decodifican al
/// leer, para que `ContractAnalysis.fromJson` reciba la List/Map que espera.
class AppwriteContractAnalysisCacheRepository
    implements ContractAnalysisCacheRepository {
  final Databases _db;
  final String _databaseId;
  final String collectionId;

  AppwriteContractAnalysisCacheRepository({
    required Databases databases,
    required String databaseId,
    this.collectionId = 'contract_analyses',
  })  : _db = databases,
        _databaseId = databaseId;

  @override
  Future<ContractAnalysis?> getLatest({
    required String propertyId,
    required String contractType,
  }) async {
    try {
      final res = await _db.listDocuments(
        databaseId: _databaseId,
        collectionId: collectionId,
        queries: [
          Query.equal('property_id', propertyId),
          Query.equal('contract_type', contractType),
          Query.orderDesc('\$createdAt'),
          Query.limit(1),
        ],
      );
      if (res.documents.isEmpty) return null;
      final row = res.documents.first.data;
      return ContractAnalysis.fromJson({
        'contract_type': row['contract_type'],
        'contract_text': row['contract_text'],
        'overall_risk_score': (row['overall_risk_score'] as num? ?? 0).toInt(),
        'analyzed_clauses': _decodeList(row['analyzed_clauses']),
        'gravamen_check': _decodeMap(row['gravamen_check']),
        'fraud_patterns_detected':
            ((row['fraud_patterns_detected'] as List?) ?? const [])
                .cast<String>(),
        'summary': row['summary'] ?? '',
        'recommendations':
            ((row['recommendations'] as List?) ?? const []).cast<String>(),
      });
    } catch (e) {
      debugPrint('[Hito.ContractCache] getLatest failed: $e');
      return null;
    }
  }

  @override
  Future<void> insert({
    required String propertyId,
    required ContractAnalysis analysis,
  }) async {
    try {
      await _db.createDocument(
        databaseId: _databaseId,
        collectionId: collectionId,
        documentId: ID.unique(),
        data: {
          'property_id': propertyId,
          'contract_type': analysis.contractType,
          'contract_text': analysis.contractText,
          'overall_risk_score': analysis.overallRiskScore,
          'analyzed_clauses': jsonEncode(
            analysis.analyzedClauses.map((c) => c.toJson()).toList(),
          ),
          'gravamen_check': jsonEncode(analysis.gravamenCheck.toJson()),
          'fraud_patterns_detected': analysis.fraudPatternsDetected,
          'summary': analysis.summary,
          'recommendations': analysis.recommendations,
        },
      );
    } catch (e) {
      debugPrint('[Hito.ContractCache] insert failed: $e');
    }
  }

  List<dynamic> _decodeList(dynamic v) {
    if (v is String && v.isNotEmpty) {
      final decoded = jsonDecode(v);
      return decoded is List ? decoded : const [];
    }
    if (v is List) return v;
    return const [];
  }

  Map<String, dynamic> _decodeMap(dynamic v) {
    if (v is String && v.isNotEmpty) {
      final decoded = jsonDecode(v);
      return decoded is Map ? decoded.cast<String, dynamic>() : const {};
    }
    if (v is Map) return v.cast<String, dynamic>();
    return const {};
  }
}
