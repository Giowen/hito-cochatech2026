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
            'Propiedad figura como garantía en hipoteca activa con Banco BISA por \$42,000 USD. Folio Real 3.01.4.99.0034521. El contrato presentado declara la propiedad libre de gravámenes (Cláusula QUINTA) — declaración FALSA verificada en DD.RR. 2 horas atrás.',
      );
    }
    return const GravamenCheck(
      status: 'clean',
      details:
          'No se detectaron gravámenes activos en el registro de Derechos Reales.',
    );
  }
}
