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
