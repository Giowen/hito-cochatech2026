import '../models/contract_analysis.dart';
import '../models/property.dart';

/// GravamenMockService — simula consulta al registro de Derechos Reales.
/// MVP mock: lee Property.hasLien. Producción: integración con AETN o
/// registro electrónico de DDRR vía partnership institucional.
class GravamenMockService {
  GravamenCheck check(Property property) {
    if (property.hasLien) {
      return const GravamenCheck(
        status: 'flagged',
        details:
            '1 hipoteca activa con BCB (Banco Central de Bolivia), no declarada por el propietario en el contrato. Monto pendiente: Bs 320.000.- Constitución: marzo 2024.',
      );
    }
    return const GravamenCheck(
      status: 'clean',
      details:
          'No se detectaron gravámenes activos en el registro de Derechos Reales.',
    );
  }
}
