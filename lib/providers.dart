import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/client_profile.dart';
import 'models/match_result.dart';
import 'models/property.dart';
import 'services/matching_service.dart';

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
