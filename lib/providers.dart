import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/client_profile.dart';
import 'models/match_result.dart';
import 'models/property.dart';
import 'models/valuation_report.dart';
import 'services/matching_service.dart';
import 'services/valuation_service.dart';

/// Notifier para el profile del cliente activo. Permite mutación vía .update().
class ClientProfileNotifier extends Notifier<ClientProfile> {
  @override
  ClientProfile build() => ClientProfile.demoJuan;

  void update(ClientProfile profile) => state = profile;
}

/// Profile activo (default: Juan demo path).
final clientProfileProvider =
    NotifierProvider<ClientProfileNotifier, ClientProfile>(
  ClientProfileNotifier.new,
);

/// Single instance del MatchingService.
final matchingServiceProvider = Provider<MatchingService>(
  (ref) => MatchingService(),
);

/// Carga todas las propiedades del seed JSON.
final propertiesProvider = FutureProvider<List<Property>>(
  (ref) => ref.read(matchingServiceProvider).loadProperties(),
);

/// Resultados de matching ordenados descending por compatibility.
final matchResultsProvider = FutureProvider<List<MatchResult>>((ref) async {
  final profile = ref.watch(clientProfileProvider);
  final service = ref.watch(matchingServiceProvider);
  final properties = await ref.watch(propertiesProvider.future);
  return service.scoreAll(profile: profile, properties: properties);
});

/// Notifier para el property_id seleccionado actualmente (sync entre lista y mapa).
class SelectedPropertyIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
  void clear() => state = null;
}

/// Selected property id — sincroniza highlight de card en lista con marker en mapa.
final selectedPropertyIdProvider =
    NotifierProvider<SelectedPropertyIdNotifier, String?>(
  SelectedPropertyIdNotifier.new,
);

/// Single instance del ValuationService.
final valuationServiceProvider = Provider<ValuationService>(
  (ref) => ValuationService(),
);

/// Valuación para una propiedad específica (family por propertyId).
final valuationProvider =
    FutureProvider.family<ValuationReport, String>((ref, propertyId) async {
  final service = ref.read(valuationServiceProvider);
  final properties = await ref.read(propertiesProvider.future);
  final property = {for (final p in properties) p.id: p}[propertyId];
  if (property == null) {
    throw Exception('Property not found: $propertyId');
  }
  return service.valuate(property: property, allProperties: properties);
});

/// Property id cuya valuación está activa (muestra comparables en mapa).
class ActiveValuationPropertyIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? id) => state = id;
}

/// Cuando una valuación está activa, el mapa highlightea los comparables.
final activeValuationPropertyIdProvider =
    NotifierProvider<ActiveValuationPropertyIdNotifier, String?>(
  ActiveValuationPropertyIdNotifier.new,
);
