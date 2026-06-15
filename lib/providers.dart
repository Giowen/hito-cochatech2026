import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'utils/env.dart';
import 'models/client_profile.dart';
import 'models/lead.dart';
import 'models/match_result.dart';
import 'models/property.dart';
import 'models/contract_analysis.dart';
import 'models/valuation_report.dart';
import 'db/hito_db.dart';
import 'repositories/appwrite_contract_analysis_cache_repository.dart';
import 'repositories/appwrite_match_cache_repository.dart';
import 'repositories/appwrite_property_repository.dart';
import 'repositories/appwrite_valuation_cache_repository.dart';
import 'repositories/drift_cached_repository.dart';
import 'repositories/contract_analysis_cache_repository.dart';
import 'repositories/leads_repository.dart';
import 'repositories/match_cache_repository.dart';
import 'repositories/property_repository.dart';
import 'repositories/valuation_cache_repository.dart';
import 'services/asset_storage.dart';
import 'services/contract_analysis_service.dart';
import 'services/lead_qualification_service.dart';
import 'services/matching_service.dart' show MatchingService, MatchingBatch;
import 'services/property_image_uploader.dart';
import 'services/property_management_service.dart';
import 'services/session_storage.dart';
import 'services/valuation_service.dart';
import 'services/voice_to_profile_service.dart';

/// ───────────────────────────────────────────────────────────────────────
/// Appwrite — cliente y servicios.
///
/// A diferencia de Supabase (singleton global vía `Supabase.initialize`), el
/// SDK de Appwrite es un objeto `Client` que se construye y se inyecta en los
/// servicios `Databases`/`Storage`. Lo exponemos como providers para que los
/// repositorios lo reciban por DI.
///
/// `endpoint` y `projectId` son públicos (no secretos): el proyecto se autoriza
/// por la plataforma registrada en la consola (hostname web / package Android),
/// no por una API key embebida en el cliente.
/// ───────────────────────────────────────────────────────────────────────
final appwriteClientProvider = Provider<Client>((ref) {
  return Client()
      .setEndpoint(Env.require('APPWRITE_ENDPOINT'))
      .setProject(Env.require('APPWRITE_PROJECT_ID'));
});

/// Servicio de base de datos (API clásica `Databases`: colecciones/documentos).
final appwriteDatabasesProvider = Provider<Databases>(
  (ref) => Databases(ref.watch(appwriteClientProvider)),
);

/// Servicio de Storage (bucket `property-images`).
final appwriteStorageProvider = Provider<Storage>(
  (ref) => Storage(ref.watch(appwriteClientProvider)),
);

/// ID lógico de la base de datos en Appwrite (de `.env` / --dart-define).
final appwriteDatabaseIdProvider = Provider<String>(
  (ref) => Env.require('APPWRITE_DATABASE_ID'),
);

/// Single instance del SessionStorage para los notifiers que persisten.
final sessionStorageProvider = Provider<SessionStorage>(
  (ref) => SessionStorage(),
);

/// Repositorio de leads (in-memory + SharedPrefs persistence).
final leadsRepositoryProvider = Provider<LeadsRepository>(
  (ref) => LeadsRepository(),
);

/// Servicio de calificación AI de leads.
final leadQualificationServiceProvider =
    Provider<LeadQualificationService>(
  (ref) => LeadQualificationService(),
);

/// Inbox de leads del agente. Hidrata desde el seed JSON en el primer load
/// y mantiene la lista mutada (incluye leads creados durante la sesión por
/// voice queries del cliente).
class LeadsNotifier extends AsyncNotifier<List<Lead>> {
  @override
  Future<List<Lead>> build() async {
    return ref.read(leadsRepositoryProvider).getAll();
  }

  /// Default phone para leads creados desde voice query sin teléfono
  /// explícito. Es el número del owner del demo — se usa así durante el
  /// pitch para que cualquier "Abrir WhatsApp" caiga en el mismo lugar y
  /// no le mande mensajes accidentales a un tercero.
  ///
  /// Cuando esto se vaya a producción, el cliente debería capturar su
  /// teléfono real en el voice query o el link compartido lo pasaría como
  /// query param.
  static const _demoFallbackPhone = '+591 70415664';

  /// Default name cuando se crea lead desde vista cliente sin nombre
  /// explícito. "Juan García" coincide con el persona de la app (avatar
  /// 'J' del role selector, banner "Hola, Juan") — así el demo se siente
  /// coherente: el user que entra como Juan, deja un lead llamado Juan
  /// en el inbox de María.
  static const _demoFallbackName = 'Juan García';

  /// Llamado cuando el cliente termina una voice query — crea el lead y
  /// lo agrega al inbox de María al tope.
  Future<void> addFromVoice({
    required ClientProfile profile,
    LeadSource source = LeadSource.organic,
    String? clientName,
    String? clientPhone,
  }) async {
    final repo = ref.read(leadsRepositoryProvider);
    final qualifier = ref.read(leadQualificationServiceProvider);
    final propertiesAsync = ref.read(propertiesProvider);

    final qualification = await qualifier.qualify(
      profile: profile,
      inventory: propertiesAsync.value ?? const [],
    );

    final lead = Lead(
      id: 'lead-${DateTime.now().millisecondsSinceEpoch}',
      clientName: clientName ?? _demoFallbackName,
      clientPhone: clientPhone ?? _demoFallbackPhone,
      profile: profile,
      qualificationScore: qualification.score,
      qualificationReasoning: qualification.reasoning,
      source: source,
      createdAt: DateTime.now(),
    );
    final updated = await repo.add(lead);
    state = AsyncValue.data(updated);
  }

  /// Update status/notes/lastContact de un lead existente.
  Future<void> updateLead(Lead lead) async {
    final repo = ref.read(leadsRepositoryProvider);
    final updated = await repo.update(lead);
    state = AsyncValue.data(updated);
  }

  /// Reset al seed — útil para limpiar entre demos.
  Future<void> resetToSeed() async {
    final repo = ref.read(leadsRepositoryProvider);
    final seed = await repo.resetToSeed();
    state = AsyncValue.data(seed);
  }
}

final leadsProvider =
    AsyncNotifierProvider<LeadsNotifier, List<Lead>>(LeadsNotifier.new);

/// Count de leads pendientes (sin contactar) — usado para badge en sidebar.
final pendingLeadsCountProvider = Provider<int>((ref) {
  final leads = ref.watch(leadsProvider).value ?? const [];
  return leads.where((l) => l.status == LeadStatus.pending).length;
});

/// Selected lead para detalle view.
class SelectedLeadIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String? id) => state = id;
}

final selectedLeadIdProvider =
    NotifierProvider<SelectedLeadIdNotifier, String?>(
  SelectedLeadIdNotifier.new,
);

/// True si el cliente actual abrió la app desde el link compartido por un
/// agente. Driven por query param `?agent=...` en la URL al cargar la app.
/// Cuando es true, los leads se taggean como `LeadSource.shareLink` y María
/// ve un badge especial "vino por tu link".
class ShareLinkOriginNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final shareLinkOriginProvider =
    NotifierProvider<ShareLinkOriginNotifier, bool>(
  ShareLinkOriginNotifier.new,
);

/// Notifier para el profile del cliente activo.
///
/// Cold start SIEMPRE arranca en null → la UI muestra el micrófono / estado
/// "¿qué buscas?" en cada carga, en vez de restaurar el último query (lo que
/// confundía: aparecía el prompt anterior escrito en lugar del micrófono).
/// Dentro de la sesión, `update` persiste por si otra parte de la app lo lee,
/// pero el reload empieza limpio.
class ClientProfileNotifier extends Notifier<ClientProfile?> {
  @override
  ClientProfile? build() => null;

  void update(ClientProfile profile) {
    state = profile;
    ref.read(sessionStorageProvider).setClientProfile(profile);
  }

  void clear() {
    state = null;
    ref.read(sessionStorageProvider).setClientProfile(null);
  }
}

/// Profile activo del cliente. Null si aún no hizo voice query.
final clientProfileProvider =
    NotifierProvider<ClientProfileNotifier, ClientProfile?>(
  ClientProfileNotifier.new,
);

/// Cache layer para AI scoring decisions (`match_scoring_cache` en Appwrite).
/// Real LLM siempre escribe aquí en cada miss; segundo load = hit instant.
final matchCacheRepositoryProvider = Provider<MatchCacheRepository>(
  (ref) => AppwriteMatchCacheRepository(
    databases: ref.watch(appwriteDatabasesProvider),
    databaseId: ref.watch(appwriteDatabaseIdProvider),
  ),
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
///   1. DriftCachedRepository.getAll()
///      → cache Drift hit: instantáneo + background refresh Appwrite
///      → cache miss: espera Appwrite, cachea, retorna
///      → Appwrite falla + cache cold: throw
///   2. FallbackPropertyRepository cacha throw → InMemory seed JSON
///
/// Read flow (Web, sin Drift):
///   1. AppwritePropertyRepository directo
///   2. FallbackPropertyRepository cacha throw → InMemory seed JSON
///
/// Resultado: demo funciona en todos los escenarios sin tocar UI.
final propertyRepositoryProvider = Provider<PropertyRepository>((ref) {
  final appwriteRepo = AppwritePropertyRepository(
    databases: ref.watch(appwriteDatabasesProvider),
    databaseId: ref.watch(appwriteDatabaseIdProvider),
  );
  final db = ref.watch(hitoDbProvider);
  final PropertyRepository primary = db == null
      ? appwriteRepo
      : DriftCachedRepository(remote: appwriteRepo, db: db);
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

/// PropertyImageUploader — compresión client-side + upload a Appwrite Storage
/// (bucket `property-images`). Usado por add_property_screen.
final propertyImageUploaderProvider = Provider<PropertyImageUploader>(
  (ref) => PropertyImageUploader(
    storage: ref.watch(appwriteStorageProvider),
    endpoint: Env.require('APPWRITE_ENDPOINT'),
    projectId: Env.require('APPWRITE_PROJECT_ID'),
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
///
/// **Implementación**: lee del `matchingBatchProvider` (que emite progreso
/// incremental) y devuelve la última snapshot ordenada. La UI principal usa
/// este provider tradicional para la lista; el mapa usa `matchingBatchProvider`
/// directo para pintar markers a medida que llegan.
final matchResultsProvider = Provider<AsyncValue<List<MatchResult>>>((ref) {
  final batch = ref.watch(matchingBatchProvider);
  return batch.when(
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
    data: (b) {
      final sorted = [...b.completed]
        ..sort((a, b) => b.compatibilityPercent.compareTo(a.compatibilityPercent));
      return AsyncValue.data(sorted);
    },
  );
});

/// Stream del progreso del matching. Emite snapshots `MatchingBatch` cada vez
/// que termina un batch del LLM. Usado por el mapa para mostrar markers
/// progresivamente + radar overlay durante el scoring.
final matchingBatchProvider =
    StreamProvider<MatchingBatch>((ref) async* {
  final profile = ref.watch(clientProfileProvider);
  if (profile == null) {
    yield const MatchingBatch(
      candidates: [],
      completed: [],
      pending: [],
    );
    return;
  }
  final service = ref.watch(matchingServiceProvider);
  final properties = await ref.watch(propertiesProvider.future);
  yield* service.scoreAllStream(profile: profile, properties: properties);
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

/// Cache layer para valuaciones AI (`valuation_reports` en Appwrite).
/// Insert-only — cada nuevo cómputo es un documento con timestamp; getLatest
/// retorna el más reciente.
final valuationCacheRepositoryProvider = Provider<ValuationCacheRepository>(
  (ref) => AppwriteValuationCacheRepository(
    databases: ref.watch(appwriteDatabasesProvider),
    databaseId: ref.watch(appwriteDatabaseIdProvider),
  ),
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

/// Cache layer para análisis de contratos (`contract_analyses` Appwrite).
/// Keyed por (property_id, contract_type), insert-only.
final contractAnalysisCacheRepositoryProvider =
    Provider<ContractAnalysisCacheRepository>(
  (ref) => AppwriteContractAnalysisCacheRepository(
    databases: ref.watch(appwriteDatabasesProvider),
    databaseId: ref.watch(appwriteDatabaseIdProvider),
  ),
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
  /// Idem ClientProfileNotifier: _hydrate async corre después del set() que
  /// hace el RoleSelector → antes pisaba la elección "María" y rebotaba a
  /// "Juan" porque el storage default era cliente.
  bool _userTouched = false;

  @override
  ViewMode build() {
    _hydrate();
    return ViewMode.client;
  }

  Future<void> _hydrate() async {
    final stored = await ref.read(sessionStorageProvider).getViewMode();
    if (_userTouched) return;
    state = stored == 'agent' ? ViewMode.agent : ViewMode.client;
  }

  void set(ViewMode mode) {
    _userTouched = true;
    state = mode;
    ref.read(sessionStorageProvider).setViewMode(mode.name);
  }

  void toggle() => set(
        state == ViewMode.client ? ViewMode.agent : ViewMode.client,
      );
}

/// Vista global (María agente / Juan cliente) — controlado desde HitoTopBar.
final viewModeProvider = NotifierProvider<ViewModeNotifier, ViewMode>(
  ViewModeNotifier.new,
);

/// Flujo principal activo en sidebar (Inbox / Matchmaking / Valuación / Copiloto Legal).
/// `leads` solo visible cuando viewMode=agent.
enum HitoFlow { leads, matchmaking, valuacion, copilotoLegal }

class ActiveFlowNotifier extends Notifier<HitoFlow> {
  @override
  HitoFlow build() => HitoFlow.matchmaking;

  void set(HitoFlow flow) => state = flow;
}

final activeFlowProvider = NotifierProvider<ActiveFlowNotifier, HitoFlow>(
  ActiveFlowNotifier.new,
);

/// Si el usuario ya seleccionó su rol (María/Juan) → mostramos MatchesScreen.
/// Si no → mostramos RoleSelectorScreen como entry point. Persiste entre
/// reloads — el usuario no necesita re-elegir su rol cada vez que abre la app.
class HasSelectedRoleNotifier extends Notifier<bool> {
  bool _userTouched = false;

  @override
  bool build() {
    _hydrate();
    return false;
  }

  Future<void> _hydrate() async {
    final stored = await ref.read(sessionStorageProvider).getHasSelectedRole();
    if (_userTouched) return;
    state = stored;
  }

  void confirm() {
    _userTouched = true;
    state = true;
    ref.read(sessionStorageProvider).setHasSelectedRole(true);
  }

  void reset() {
    _userTouched = true;
    state = false;
    ref.read(sessionStorageProvider).setHasSelectedRole(false);
  }
}

final hasSelectedRoleProvider =
    NotifierProvider<HasSelectedRoleNotifier, bool>(
  HasSelectedRoleNotifier.new,
);
