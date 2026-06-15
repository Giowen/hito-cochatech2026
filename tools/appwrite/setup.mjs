// ============================================================================
// Hito · Appwrite setup — crea database + colecciones + atributos + índices + bucket
// ----------------------------------------------------------------------------
// Uso:  npm run setup       (corre: node --env-file=.env setup.mjs)
// Idempotente: si algo ya existe (409) lo saltea, así podés re-correrlo.
//
// Mapeo Supabase/Postgres → Appwrite:
//   tabla   → colección        columna → atributo        fila → documento
//   TEXT[]  → atributo array    JSONB   → atributo string (JSON.stringify)
//   created_at/updated_at → $createdAt/$updatedAt (automáticos, no se crean)
//   RLS permisivo anon → permisos Role.any() a nivel colección
// ============================================================================

import {
  Client,
  Databases,
  Storage,
  Permission,
  Role,
  DatabasesIndexType,
  OrderBy,
  Query,
} from 'node-appwrite';

// ── Config desde .env ───────────────────────────────────────────────────────
const ENDPOINT = process.env.APPWRITE_ENDPOINT;
const PROJECT = process.env.APPWRITE_PROJECT_ID;
const API_KEY = process.env.APPWRITE_API_KEY;
const DB = process.env.APPWRITE_DATABASE_ID || 'hito';
const BUCKET = 'property-images';

if (!ENDPOINT || !PROJECT || !API_KEY) {
  console.error(
    '✗ Faltan variables de entorno. Copiá .env.example a .env y completá ' +
      'APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID y APPWRITE_API_KEY.',
  );
  process.exit(1);
}

const client = new Client()
  .setEndpoint(ENDPOINT)
  .setProject(PROJECT)
  .setKey(API_KEY);

const databases = new Databases(client);
const storage = new Storage(client);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Permisos MVP: cualquiera lee y escribe (espeja el RLS permisivo de Supabase).
// Phase 2: endurecer con Role.user(id) / ownership por agente.
const ANY = [
  Permission.read(Role.any()),
  Permission.create(Role.any()),
  Permission.update(Role.any()),
  Permission.delete(Role.any()),
];

// ── Definición declarativa de las colecciones ───────────────────────────────
// type: string | integer | float | boolean
// Reglas Appwrite: un atributo required NO lleva default; un atributo array
// tampoco. El código Dart ya defaultea arrays vacíos al leer, así que los
// arrays van como opcionales sin default.
const COLLECTIONS = [
  {
    id: 'properties',
    name: 'Properties',
    attributes: [
      { key: 'address', type: 'string', size: 500, required: true },
      { key: 'title', type: 'string', size: 300 },
      { key: 'lat', type: 'float', required: true },
      { key: 'lng', type: 'float', required: true },
      { key: 'neighborhood', type: 'string', size: 100 },
      { key: 'price_bob', type: 'integer', default: 0 },
      { key: 'price_usd_paralelo', type: 'integer', default: 0 },
      { key: 'area_m2', type: 'integer', default: 0 },
      { key: 'lot_m2', type: 'integer' },
      { key: 'bedrooms', type: 'integer', default: 0 },
      { key: 'bathrooms', type: 'integer', default: 0 },
      { key: 'parking', type: 'integer', default: 0 },
      { key: 'type', type: 'string', size: 50, required: true },
      { key: 'listing_mode', type: 'string', size: 50, required: true },
      { key: 'supported_transactions', type: 'string', size: 50, array: true },
      { key: 'anticretico_bob', type: 'integer' },
      { key: 'rent_monthly_bob', type: 'integer' },
      { key: 'year_built', type: 'integer' },
      { key: 'age_years', type: 'integer', default: 0 },
      { key: 'amenities', type: 'string', size: 100, array: true },
      { key: 'photos', type: 'string', size: 1000, array: true },
      { key: 'cochabamba_tags', type: 'string', size: 100, array: true },
      { key: 'ai_notes', type: 'string', size: 1000, array: true },
      { key: 'compatibility', type: 'integer' },
      { key: 'listed_days', type: 'integer', default: 0 },
      { key: 'agent_name', type: 'string', size: 150 },
      { key: 'image', type: 'string', size: 100, default: 'gradient-1' },
      { key: 'listing_status', type: 'string', size: 50, default: 'activa' },
      { key: 'description', type: 'string', size: 5000, default: '' },
      { key: 'has_lien', type: 'boolean', default: false },
    ],
    indexes: [
      { key: 'idx_listing_status', attributes: ['listing_status'] },
      { key: 'idx_neighborhood', attributes: ['neighborhood'] },
      { key: 'idx_compatibility', attributes: ['compatibility'], orders: [OrderBy.Desc] },
    ],
  },
  {
    id: 'valuation_reports',
    name: 'Valuation Reports',
    attributes: [
      { key: 'property_id', type: 'string', size: 64, required: true },
      { key: 'estimated_value_bob', type: 'integer', default: 0 },
      { key: 'estimated_value_usd_paralelo', type: 'integer', default: 0 },
      { key: 'estimated_value_usd_low', type: 'integer' },
      { key: 'estimated_value_usd_high', type: 'integer' },
      { key: 'listed_value_bob', type: 'integer', default: 0 },
      { key: 'delta_percent', type: 'float', default: 0 },
      { key: 'usd_paralelo_rate_used', type: 'float', default: 10.2 },
      { key: 'comparables', type: 'string', size: 200, array: true },
      { key: 'comparable_details', type: 'string', size: 2000, array: true },
      { key: 'factors', type: 'string', size: 500, array: true },
      { key: 'confidence_score', type: 'float', default: 0.7 },
      { key: 'recommendation_for_agent', type: 'string', size: 5000 },
      { key: 'recommendation_for_client', type: 'string', size: 5000 },
      { key: 'reasoning', type: 'string', size: 5000 },
    ],
    indexes: [{ key: 'idx_val_property', attributes: ['property_id'] }],
  },
  {
    id: 'contract_analyses',
    name: 'Contract Analyses',
    attributes: [
      { key: 'property_id', type: 'string', size: 64 },
      { key: 'contract_type', type: 'string', size: 50, required: true },
      { key: 'contract_text', type: 'string', size: 100000, required: true },
      { key: 'overall_risk_score', type: 'integer', default: 0 },
      // JSONB → string JSON-codificado (lo decodifica el repo Dart):
      { key: 'analyzed_clauses', type: 'string', size: 50000 },
      { key: 'gravamen_check', type: 'string', size: 10000 },
      { key: 'fraud_patterns_detected', type: 'string', size: 500, array: true },
      { key: 'summary', type: 'string', size: 5000 },
      { key: 'recommendations', type: 'string', size: 2000, array: true },
    ],
    indexes: [
      { key: 'idx_contract_prop_type', attributes: ['property_id', 'contract_type'] },
    ],
  },
  {
    id: 'match_scoring_cache',
    name: 'Match Scoring Cache',
    attributes: [
      { key: 'property_id', type: 'string', size: 64, required: true },
      { key: 'profile_hash', type: 'string', size: 64, required: true },
      { key: 'profile_json', type: 'string', size: 5000 },
      { key: 'compatibility_percent', type: 'integer', min: 0, max: 100, default: 0 },
      { key: 'explanation', type: 'string', size: 5000 },
      { key: 'recommended', type: 'string', size: 1000, array: true },
      { key: 'considerations', type: 'string', size: 1000, array: true },
      { key: 'risks', type: 'string', size: 1000, array: true },
      { key: 'tags_matched', type: 'string', size: 100, array: true },
      { key: 'tags_missing', type: 'string', size: 100, array: true },
      { key: 'llm_model', type: 'string', size: 100, default: 'llama-3.3-70b-versatile' },
    ],
    indexes: [
      { key: 'idx_match_property', attributes: ['property_id'] },
      { key: 'idx_match_hash', attributes: ['profile_hash'] },
    ],
  },
];

// ── Helpers ─────────────────────────────────────────────────────────────────
function isConflict(e) {
  return e && (e.code === 409 || e.type === 'collection_already_exists');
}

async function step(label, fn) {
  try {
    await fn();
    console.log(`  ✓ ${label}`);
  } catch (e) {
    if (isConflict(e)) {
      console.log(`  • ${label} (ya existía, ok)`);
    } else {
      console.error(`  ✗ ${label}\n    → ${e.message || e}`);
      throw e;
    }
  }
}

function createAttribute(colId, a) {
  const isArr = !!a.array;
  // default solo aplica a escalares opcionales
  const def = a.required || isArr ? undefined : a.default;
  switch (a.type) {
    case 'string':
      return databases.createStringAttribute(DB, colId, a.key, a.size, !!a.required, def, isArr);
    case 'integer':
      return databases.createIntegerAttribute(DB, colId, a.key, !!a.required, a.min, a.max, def, isArr);
    case 'float':
      return databases.createFloatAttribute(DB, colId, a.key, !!a.required, a.min, a.max, def, isArr);
    case 'boolean':
      return databases.createBooleanAttribute(DB, colId, a.key, !!a.required, def, isArr);
    default:
      throw new Error(`Tipo de atributo desconocido: ${a.type}`);
  }
}

// Los atributos se crean async (status 'processing'). Hay que esperar a que
// estén 'available' antes de crear índices sobre ellos.
async function waitForAttributesAvailable(colId, keys) {
  for (let i = 0; i < 60; i++) {
    // OJO: listAttributes devuelve máx. 25 por defecto — hay que pedir el límite
    // alto o no veríamos los atributos 26+ y esperaríamos para siempre.
    const list = await databases.listAttributes(DB, colId, [Query.limit(100)]);
    const status = Object.fromEntries(list.attributes.map((a) => [a.key, a.status]));
    const pending = keys.filter((k) => status[k] !== 'available');
    if (pending.length === 0) return;
    if (i % 5 === 0) {
      console.log(`    … esperando ${pending.length} atributos (${pending.slice(0, 3).join(', ')}…)`);
    }
    await sleep(1000);
  }
  throw new Error(`Timeout esperando atributos de ${colId}`);
}

// ── Main ──────────────────────────────────────────────────────────────────--
async function main() {
  console.log(`\n▶ Appwrite setup — proyecto ${PROJECT} @ ${ENDPOINT}\n`);

  console.log('1) Base de datos');
  // En el plan Free hay 1 sola database. Recrearla choca con el límite del plan
  // (no devuelve 409), así que chequeamos existencia primero.
  try {
    await databases.get(DB);
    console.log(`  • database "${DB}" (ya existía, ok)`);
  } catch (_) {
    await step(`database "${DB}"`, () => databases.create(DB, 'Hito'));
  }

  for (const col of COLLECTIONS) {
    console.log(`\n2) Colección "${col.id}"`);
    await step(`crear colección`, () =>
      databases.createCollection(DB, col.id, col.name, ANY, /* documentSecurity */ false),
    );

    // Idempotencia: en vez de crear-y-cachar-409 (Appwrite a veces devuelve
    // 500 al recrear atributos numéricos), listamos los que ya existen y los
    // salteamos. Limit 100 porque el default es 25.
    const haveAttrs = new Set(
      (await databases.listAttributes(DB, col.id, [Query.limit(100)])).attributes.map((a) => a.key),
    );
    for (const a of col.attributes) {
      if (haveAttrs.has(a.key)) {
        console.log(`  • atributo ${a.key} (ya existía, ok)`);
        continue;
      }
      await step(`atributo ${a.key} (${a.type}${a.array ? '[]' : ''})`, () =>
        createAttribute(col.id, a),
      );
    }

    console.log(`   Esperando que los atributos estén disponibles…`);
    await waitForAttributesAvailable(col.id, col.attributes.map((a) => a.key));

    const haveIdx = new Set(
      (await databases.listIndexes(DB, col.id, [Query.limit(100)])).indexes.map((i) => i.key),
    );
    for (const idx of col.indexes || []) {
      if (haveIdx.has(idx.key)) {
        console.log(`  • índice ${idx.key} (ya existía, ok)`);
        continue;
      }
      await step(`índice ${idx.key}`, () =>
        databases.createIndex(
          DB,
          col.id,
          idx.key,
          DatabasesIndexType.Key,
          idx.attributes,
          idx.orders || [],
        ),
      );
    }
  }

  console.log(`\n3) Storage bucket "${BUCKET}"`);
  await step(`crear bucket`, () =>
    storage.createBucket(
      BUCKET,
      'Property Images',
      ANY,
      /* fileSecurity */ false,
      /* enabled */ true,
      /* maximumFileSize */ 10_000_000,
      /* allowedFileExtensions */ ['jpg', 'jpeg', 'png', 'webp'],
    ),
  );

  console.log('\n✓ Listo. Database, colecciones, índices y bucket creados.\n');
}

main().catch((e) => {
  console.error('\n✗ Falló el setup:', e.message || e);
  process.exitCode = 1;
});
