import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/contract_analysis.dart';

/// Cache de análisis de contratos por (property_id, contract_type).
///
/// Estrategia: insert-only (preserva historial). `getLatest` retorna el más
/// reciente por created_at desc para esa combinación.
///
/// Si el agente sube un contrato distinto para la misma propiedad/tipo,
/// debe pasar `useCache: false` a `ContractAnalysisService.analyzeContract`
/// para forzar un nuevo cómputo.
abstract class ContractAnalysisCacheRepository {
  Future<ContractAnalysis?> getLatest({
    required String propertyId,
    required String contractType,
  });

  Future<void> insert({
    required String propertyId,
    required ContractAnalysis analysis,
  });
}

class SupabaseContractAnalysisCacheRepository
    implements ContractAnalysisCacheRepository {
  final SupabaseClient _client;

  SupabaseContractAnalysisCacheRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  @override
  Future<ContractAnalysis?> getLatest({
    required String propertyId,
    required String contractType,
  }) async {
    try {
      final rows = await _client
          .from('contract_analyses')
          .select()
          .eq('property_id', propertyId)
          .eq('contract_type', contractType)
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) return null;
      final row = rows.first;
      return ContractAnalysis.fromJson({
        'contract_type': row['contract_type'],
        'contract_text': row['contract_text'],
        'overall_risk_score':
            (row['overall_risk_score'] as num? ?? 0).toInt(),
        'analyzed_clauses': row['analyzed_clauses'] ?? const [],
        'gravamen_check': row['gravamen_check'] ?? {},
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
      await _client.from('contract_analyses').insert({
        'property_id': propertyId,
        'contract_type': analysis.contractType,
        'contract_text': analysis.contractText,
        'overall_risk_score': analysis.overallRiskScore,
        'analyzed_clauses':
            analysis.analyzedClauses.map((c) => c.toJson()).toList(),
        'gravamen_check': analysis.gravamenCheck.toJson(),
        'fraud_patterns_detected': analysis.fraudPatternsDetected,
        'summary': analysis.summary,
        'recommendations': analysis.recommendations,
      });
    } catch (e) {
      debugPrint('[Hito.ContractCache] insert failed: $e');
    }
  }
}

class NoOpContractAnalysisCacheRepository
    implements ContractAnalysisCacheRepository {
  @override
  Future<ContractAnalysis?> getLatest({
    required String propertyId,
    required String contractType,
  }) async =>
      null;

  @override
  Future<void> insert({
    required String propertyId,
    required ContractAnalysis analysis,
  }) async {}
}
