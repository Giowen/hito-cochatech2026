// ============================================================================
// Hito · Appwrite seed — importa assets/seed/properties.json a la colección
// `properties`. Corré `npm run setup` ANTES (crea la colección + atributos).
// ----------------------------------------------------------------------------
// Uso:  npm run seed       (corre: node --env-file=.env seed.mjs)
// Idempotente: si el documento ya existe (409) lo actualiza, así podés
// re-correrlo para refrescar la data canónica.
//
// Nota: solo se siembran `properties`. Las otras colecciones se llenan en
// runtime:
//   - valuation_reports / match_scoring_cache → caches que escribe el LLM.
//   - contract_analyses → la app tiene seed local (seed_contract_analyses.dart)
//     y cae al LLM; no requiere seed en la DB.
//   - leads → in-memory (SharedPreferences), no hay colección.
// ============================================================================

import { Client, Databases } from 'node-appwrite';
import { readFile } from 'node:fs/promises';

const ENDPOINT = process.env.APPWRITE_ENDPOINT;
const PROJECT = process.env.APPWRITE_PROJECT_ID;
const API_KEY = process.env.APPWRITE_API_KEY;
const DB = process.env.APPWRITE_DATABASE_ID || 'hito';

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

async function loadJson(relPath) {
  const url = new URL(relPath, import.meta.url);
  return JSON.parse(await readFile(url, 'utf8'));
}

async function seedProperties() {
  const props = await loadJson('../../assets/seed/properties.json');
  console.log(`\n▶ Seed "properties" — ${props.length} documentos`);

  let creados = 0;
  let actualizados = 0;
  let errores = 0;

  for (const p of props) {
    // `id` se usa como $id del documento (no es un atributo de la colección).
    const { id, ...data } = p;
    try {
      await databases.createDocument(DB, 'properties', id, data);
      creados++;
      console.log(`  ✓ ${id} creado`);
    } catch (e) {
      if (e.code === 409) {
        try {
          await databases.updateDocument(DB, 'properties', id, data);
          actualizados++;
          console.log(`  • ${id} ya existía → actualizado`);
        } catch (e2) {
          errores++;
          console.error(`  ✗ ${id} (update): ${e2.message}`);
        }
      } else {
        errores++;
        console.error(`  ✗ ${id}: ${e.message}`);
      }
    }
  }

  console.log(
    `\n✓ Seed completo — ${creados} creados, ${actualizados} actualizados, ` +
      `${errores} errores.`,
  );
  if (errores > 0) process.exitCode = 1;
}

await seedProperties();
