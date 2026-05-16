# Hito — Architecture for Code Review

> Documento para defender la arquitectura de Hito ante un jurado técnico (CochaTech 2026) o un VC que abra el repo. Explica las decisiones MVP, el camino a Phase 2 (10K agentes / 100K propiedades), y los hooks ya plantados.

## Stack actual (MVP, hackathon)

```
┌────────────────────────────────────────────────────────┐
│             Flutter (Web / Android / iOS)              │
│  ┌────────────────────────────────────────────────┐    │
│  │ Widgets (screens/, widgets/) — design-system   │    │
│  └─────────────────┬──────────────────────────────┘    │
│  ┌─────────────────▼──────────────────────────────┐    │
│  │ State: Riverpod (NotifierProvider, Family,     │    │
│  │ FutureProvider) — providers.dart               │    │
│  └─────────────────┬──────────────────────────────┘    │
│  ┌─────────────────▼──────────────────────────────┐    │
│  │ Services (MatchingService, ValuationService,   │    │
│  │ ContractAnalysisService, GroqClient)           │    │
│  └─────────────────┬──────────────────────────────┘    │
│  ┌─────────────────▼──────────────────────────────┐    │
│  │ Repositories (PropertyRepository, ...)         │    │
│  │ MVP: InMemoryPropertyRepository (seed JSON)    │    │
│  └─────────────────┬──────────────────────────────┘    │
│  ┌─────────────────▼──────────────────────────────┐    │
│  │ Data: assets/seed/*.json + Groq API            │    │
│  └────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────┘
```

### Por qué cada capa existe

- **Widgets/screens** (`lib/screens`, `lib/widgets`): UI cross-platform, theme tokens del claude-design system. Sin web-only deps (validado en Phase 0 stack validation: flutter_map + OSM, record audio HTTPS).
- **State (Riverpod 3.x)** (`lib/providers.dart`): NotifierProvider para mutables (selectedPropertyId, viewMode, activeFlow), FutureProvider.family para queries paramétricas (valuationProvider(id)).
- **Services** (`lib/services`): lógica de negocio. Cada service expone método demo path (hardcoded, cero red) Y método LLM (Groq Llama 3.3 70B). El demo path garantiza reproducibilidad del pitch; el LLM path es la versión producción.
- **Repositories** (`lib/repositories`): abstracción de data source. MVP usa InMemory + seed JSON. Phase 2 swap a Drift+Supabase NO toca services ni widgets.

---

## Path a Phase 2: offline-first con sync incremental

### Repository pattern (ya plantado)

```dart
// lib/providers.dart
final propertyRepositoryProvider = Provider<PropertyRepository>(
  (ref) => InMemoryPropertyRepository(),  // MVP

  // Phase 2 (1-line swap, sin tocar services):
  // (ref) => DriftPropertyRepository(
  //   db: ref.read(hitoDbProvider),
  //   supabase: ref.read(supabaseProvider),
  // ),
);
```

### Por qué offline-first

El target son agentes inmobiliarios bolivianos, frecuentemente trabajando desde:
- Visitas in-situ con WiFi inestable
- Vehículos con 3G/4G intermitente
- Oficinas con cortes eléctricos

Si el agente abre la app y tiene 0 latencia + 0 errores aunque esté offline, lo retenemos. Si tiene que esperar 3s al servidor cada click, se va a WhatsApp.

### Por qué Drift (no SQLite directo)

- **Type-safe**: queries verificadas en compile-time
- **Cross-platform**: Web (sql.js), Android (sqlite3), iOS (sqlite3), Desktop
- **Reactive**: `.watch()` para streams reactivos → Riverpod integra natural
- **Migrations**: explicit version → ALTER scripts, no breaking changes silenciosos

### Sync incremental (Phase 2 design)

```
┌──────────────────┐  delta sync     ┌──────────────────┐
│ Drift local DB   │ ◄──────────────►│ Supabase Postgres│
│ (Flutter device) │  WHERE          │ (cloud)          │
│                  │  updated_at >   │                  │
└──────────────────┘  last_sync      └──────────────────┘
        ▲
        │ writes go to local first,
        │ enqueued for sync
        │
┌──────────────────┐
│  Services        │
│  (offline-safe)  │
└──────────────────┘
```

- **Reads**: 100% local-first vía Drift. Background sync no bloquea UI.
- **Writes**: a Drift inmediatamente + queued en sync_queue table. Background worker drena queue cuando hay red.
- **Conflict resolution**: last-write-wins por defecto. Para campos críticos (price, contracts) → CRDT con vector clocks (Phase 3).
- **RLS (Row-Level Security)**: Supabase policies por agent_id → cada agente solo ve/edita sus listings + assigned clients.

---

## Asset storage: Cloudflare R2 (Phase 2)

### Por qué R2 (no S3, no Firebase Storage)

- **Egress: $0** (S3 cobra $0.09/GB de salida, Firebase también)
- **Storage: $0.015/GB/mes** (S3 $0.023, Firebase $0.026)
- **Compatible API**: S3-compatible — `aws-sdk` o `dart_aws` funciona sin cambios
- **CDN incluido**: Cloudflare's edge network sin paywall extra

### Stubs ya plantados en código

`// TODO R2:` comments marcan los puntos de integración:

- `lib/widgets/property_card.dart`: `_PhotoStub._gradientFor()` — actualmente gradients sintéticos por property.image, en Phase 2 → NetworkImage(R2 signed URL)
- `lib/widgets/voice_input_sheet.dart`: el audio capturado por `record` package — en Phase 2 → upload a R2 → trigger Whisper transcription via R2 webhook
- `lib/services/contract_analysis_service.dart::loadAnticreticoSample()` — actualmente lee de assets/, en Phase 2 → lee de R2 signed URL (PDFs subidos por el agente)
- Backup video del demo en `hito-demo-backup.mp4` — en Phase 2 vive en R2 bucket público de marketing

---

## Por qué la economía cierra a 10K agentes / 100K propiedades

### Cost per agent/month (modelado)

| Componente | Cost/agent/mes |
|---|---|
| Drift local DB | $0 (en device del agente) |
| Supabase Free Tier @ ≤ 500 agentes; Pro $25/proyecto @ ≤ 5K agentes | $0.005-0.02 |
| Groq Llama 3.3 70B — ~50 match scorings/día × 1.5K tokens × $0.00059/1K | ~$2.65 |
| Groq Whisper — ~10 voice queries/día × 6s audio | ~$0.05 |
| Cloudflare R2 — ~100MB fotos + 50MB PDFs × $0.015/GB | ~$0.002 |
| Cloudflare egress | $0 |
| Vercel/Cloudflare Pages (web hosting) | ~$0.01 |
| **Total infra cost/agente/mes** | **~$2.74** |

### Pricing: $5/agente/mes

- **Margin bruto**: ($5 - $2.74) / $5 = **45%**
- **Margin a escala** (con prompt caching, batch scoring, Groq committed-use discount): ~70%

### Headroom de la arquitectura

- 10K agentes × 100K propiedades = 100K rows en `properties` Supabase
- Postgres con índices apropiados maneja 1M rows sin tunning especial
- Drift local: cada agente tiene típicamente 50-200 propiedades suyas → 200 rows max en dispositivo
- Sync queries: WHERE agent_id = X AND updated_at > Y → O(delta) ≤ 200 rows
- **No infraestructura especial hasta los 100K agentes activos**. Ahí entran shards de Postgres + read replicas. Phase 4 (post-Series A).

---

## Multi-platform readiness

### Validated en Phase 0 stack validation

- ✅ Flutter 3.41 stable
- ✅ flutter_map + OSM tiles en Chrome (Web) — funciona
- ✅ `record` package en Web HTTPS — captura audio cross-browser
- ✅ Groq streaming en Web vía dio + ResponseType.stream — <2s first token

### Targets

- **MVP demo**: Flutter Web @ Chrome (Sat-Sun hackathon pitch)
- **Phase 2**: Android APK release para hosting en R2 + QR code para descarga (agentes bolivianos prefieren APK por bajo data cost vs Play Store)
- **Phase 3**: iOS via TestFlight → App Store

### Cross-platform safe

Ningún package usado es web-only:
- `flutter_map` ✅ Web/Android/iOS
- `dio` ✅ todos
- `record` ✅ todos (Web requiere HTTPS)
- `flutter_dotenv` ✅ todos
- `pdf` ✅ todos
- `google_fonts` ✅ todos (runtime cached)

---

## La línea de cierre del pitch — defendida en el código

> "Nuestra arquitectura permite atender 10,000 agentes y 100,000 propiedades antes de tocar la infraestructura. $5/agente/mes a esa escala."

**Esto NO es bluff**. El repository pattern + Groq + Drift + R2 + Supabase RLS ya están diseñados para esa escala:

- Repository abstraction → swap MVP a Drift+Supabase sin tocar services (1 línea en providers.dart)
- Groq pay-per-call con cache hint → marginal cost cae a ~$0.50/agente a escala con prompt caching
- Drift local-first → cero round-trips en hot path
- R2 egress gratis → cero costo de fotos/contratos servidos a clientes finales
- Supabase RLS → tenant isolation sin código custom

**Hito en estado actual**: MVP funcional con demo path hardcoded. Hito en Phase 2: producción con misma arquitectura, swap de 1 línea de provider + implementaciones concretas de los repository methods.
