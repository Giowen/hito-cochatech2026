import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/client_profile.dart';
import 'models/match_result.dart';
import 'models/property.dart';
import 'models/contract_analysis.dart';
import 'models/valuation_report.dart';
import 'db/hito_db.dart';
import 'repositories/drift_cached_supabase_repository.dart';
import 'repositories/contract_analysis_cache_repository.dart';
import 'repositories/match_cache_repository.dart';
import 'repositories/property_repository.dart';
import 'repositories/supabase_property_repository.dart';
import 'repositories/valuation_cache_repository.dart';
import 'services/asset_storage.dart';
import 'services/contract_analysis_service.dart';
import 'services/matching_service.dart';
import 'services/property_management_service.dart';
import 'services/valuation_service.dart';
import 'services/voice_to_profile_service.dart';

/// Notifier para el profile del cliente activo. Default null — el cliente
/// debe describir su búsqueda por voz para que el matching se ejecute.
///
/// Esto evita el "demo path" donde la app aparece con scores precalculados
/// del perfil hardcoded de Juan. La experiencia honesta: usuario llega →
/// search vacío → voz → AI scorea.
class ClientProfileNotifier extends Notifier<ClientProfile?> {
  @override
  ClientProfile? build() => null;

  void update(ClientProfile profile) => state = profile;
  void clear() => state = null;
}

/// Profile activo del cliente. Null si aún no hizo voice query.
final clientProfileProvider =
    NotifierProvider<ClientProfileNotifier, ClientProfile?>(
  ClientProfileNotifier.new,
);

/// Cache layer para AI scoring decisions (`match_scoring_cache` en Supabase).
/// Real LLM siempre escribe aquí en cada miss; segundo load = hit instant.
final matchCacheRepositoryProvider = Provider<MatchCacheRepository>(
  (ref) => SupabaseMatchCacheRepository(),
);

/// MatchingService — real Groq Llama 3.3 con cache. Sin hardcoded shortcuts.
final matchingServiceProvider = Provider<MatchingService>(
  (ref) => MatchingService(
    cache: ref.watch(matchCacheRepositoryProvider),
  ),
);

/// Single instance del Drift database (Mobile/Desktop).
/// Returns null on Web — sqlite3 WASM en Web requiere setup adicional que
/// hace overhead vs valor. Web usa Supabase + InMemory fallback (Phase B.3
/// chain). Mobile usa Drift full offline-first (Phase B.4).
final hitoDbProvider = Provider<HitoDatabase?>((ref) {
  if (kIsWeb) return null;
  final db = HitoDatabase();
  ref.onDispose(() async => db.close());
  return db;
});

/// Repositorio de propiedades — multi-tier resilient.
///
/// Read flow (Mobile con Drift):
///   1. DriftCachedSupabaseRepository.getAll()
///      → cache Drift hit: instantáneo + background refresh Supabase
///      → cache miss: espera Supabase, cachea, retorna
///      → Supabase falla + cache cold: throw
///   2. FallbackPropertyRepository cacha throw → InMemory seed JSON
///
/// Read flow (Web, sin Drift):
///   1. SupabasePropertyRepository directo
///   2. FallbackPropertyRepository cacha throw → InMemory seed JSON
///
/// Resultado: demo funciona en todos los escenarios sin tocar UI.
final propertyRepositoryProvider = Provider<PropertyRepository>((ref) {
  final supabaseRepo = SupabasePropertyRepository();
  final db = ref.watch(hitoDbProvider);
  final PropertyRepository primary = db == null
      ? supabaseRepo
      : DriftCachedSupabaseRepository(remote: supabaseRepo, db: db);
  return FallbackPropertyRepository(
    primary: primary,
    fallback: InMemoryPropertyRepository(),
  );
});

/// Carga todas las propiedades vía repository.
final propertiesProvider = FutureProvider<List<Property>>(
  (ref) => ref.read(propertyRepositoryProvider).getAll(),
);

/// PropertyManagementService — agent CRUD operations (insert + geocode).
/// El UI screen invalida `propertiesProvider` tras un insert exitoso,
/// disparando re-scoring automático con Groq de la nueva propiedad.
final propertyManagementServiceProvider = Provider<PropertyManagementService>(
  (ref) => PropertyManagementService(
    repo: ref.watch(propertyRepositoryProvider),
  ),
);

/// VoiceToProfileService — Whisper (Groq) + LLM extraction. Convierte voz
/// del usuario en un ClientProfile estructurado. Cero hardcoded.
final voiceToProfileServiceProvider = Provider<VoiceToProfileService>(
  (ref) => VoiceToProfileService(),
);

/// Resultados de matching ordenados descending por compatibility.
/// Si el cliente aún no hizo voice query (profile null), retorna [] — la
/// UI muestra empty state CTA en vez de scores.
final matchResultsProvider = FutureProvider<List<MatchResult>>((ref) async {
  final profile = ref.watch(clientProfileProvider);
  if (profile == null) return const [];
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

/// Cache layer para valuaciones AI (`valuation_reports` en Supabase).
/// Insert-only — cada nuevo cómputo es un row con timestamp; getLatest
/// retorna el más reciente.
final valuationCacheRepositoryProvider = Provider<ValuationCacheRepository>(
  (ref) => SupabaseValuationCacheRepository(),
);

/// ValuationService — Groq Llama 3.3 con comparables live de Supabase.
/// Sin demo path hardcoded.
final valuationServiceProvider = Provider<ValuationService>(
  (ref) => ValuationService(
    cache: ref.watch(valuationCacheRepositoryProvider),
  ),
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

/// Cache layer para análisis de contratos (`contract_analyses` Supabase).
/// Keyed por (property_id, contract_type), insert-only.
final contractAnalysisCacheRepositoryProvider =
    Provider<ContractAnalysisCacheRepository>(
  (ref) => SupabaseContractAnalysisCacheRepository(),
);

/// ContractAnalysisService — real Groq Llama 3.3 con conocimiento del Código
/// Civil boliviano. Gravamen sigue mock (DDRR sin API público) — el mock se
/// pasa al LLM como contexto y se override en el resultado final.
final contractAnalysisServiceProvider = Provider<ContractAnalysisService>(
  (ref) => ContractAnalysisService(
    cache: ref.watch(contractAnalysisCacheRepositoryProvider),
  ),
);

/// Análisis de contrato anticrético para una propiedad específica.
final contractAnalysisProvider =
    FutureProvider.family<ContractAnalysis, String>((ref, propertyId) async {
  final service = ref.read(contractAnalysisServiceProvider);
  final properties = await ref.read(propertiesProvider.future);
  final property = {for (final p in properties) p.id: p}[propertyId];
  if (property == null) {
    throw Exception('Property not found: $propertyId');
  }
  return service.analyzeAnticreticoFor(property);
});

/// AssetStorage — upload de fotos, contratos, voice recordings.
/// MVP: MockAssetStorage (genera placeholder URLs).
/// Phase 2: swap a R2AssetStorage.fromEnv() cuando credentials estén en .env.
/// Ver lib/services/asset_storage.dart para setup detallado.
final assetStorageProvider = Provider<AssetStorage>((ref) {
  // TODO Phase 2: detectar si R2_ACCESS_KEY_ID está en .env → switch a R2.
  // try {
  //   return R2AssetStorage.fromEnv();
  // } on StateError {
  //   return MockAssetStorage();
  // }
  return MockAssetStorage();
});

/// Perspectiva global de vista — afecta valuation/recommendations en todos los flows.
enum ViewMode {
  /// Vista cliente — Juan (default). Recommendations enfocadas en buyer perspective.
  client,

  /// Vista agente — María. Recommendations enfocadas en agente/seller perspective.
  agent,
}

class ViewModeNotifier extends Notifier<ViewMode> {
  @override
  ViewMode build() => ViewMode.client;

  void set(ViewMode mode) => state = mode;
  void toggle() => state =
      state == ViewMode.client ? ViewMode.agent : ViewMode.client;
}

/// Vista global (María agente / Juan cliente) — controlado desde HitoTopBar.
final viewModeProvider = NotifierProvider<ViewModeNotifier, ViewMode>(
  ViewModeNotifier.new,
);

/// Vista del panel derecho — map o AI thinking. Default 'map' (alineado al
/// design canonical fullscreen). El toggle permite cambiar a 'ai' para ver
/// el pipeline en vivo del matching.
enum RightPanelView { map, ai }

class RightPanelViewNotifier extends Notifier<RightPanelView> {
  @override
  RightPanelView build() => RightPanelView.map;
  void set(RightPanelView v) => state = v;
}

final rightPanelViewProvider =
    NotifierProvider<RightPanelViewNotifier, RightPanelView>(
  RightPanelViewNotifier.new,
);

/// Flujo principal activo en sidebar (Matchmaking / Valuación / Copiloto Legal).
enum HitoFlow { matchmaking, valuacion, copilotoLegal }

class ActiveFlowNotifier extends Notifier<HitoFlow> {
  @override
  HitoFlow build() => HitoFlow.matchmaking;

  void set(HitoFlow flow) => state = flow;
}

final activeFlowProvider = NotifierProvider<ActiveFlowNotifier, HitoFlow>(
  ActiveFlowNotifier.new,
);

/// Si el usuario ya seleccionó su rol (María/Juan) → mostramos MatchesScreen.
/// Si no → mostramos RoleSelectorScreen como entry point.
class HasSelectedRoleNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void confirm() => state = true;
  void reset() => state = false;
}

final hasSelectedRoleProvider =
    NotifierProvider<HasSelectedRoleNotifier, bool>(
  HasSelectedRoleNotifier.new,
);
