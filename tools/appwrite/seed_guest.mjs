// ============================================================================
// Hito · Seed GUEST — siembra `properties` SIN API key, como cliente anónimo.
// Funciona porque la colección tiene create(Role.any()) (permisos MVP). Útil
// cuando no hay APPWRITE_API_KEY en .env. Mismo origen de data que seed.mjs.
//   Uso:  node --env-file=.env seed_guest.mjs
// ============================================================================

import { Client, Databases } from 'node-appwrite';
import { readFile } from 'node:fs/promises';

const ENDPOINT = process.env.APPWRITE_ENDPOINT;
const PROJECT = process.env.APPWRITE_PROJECT_ID;
const DB = process.env.APPWRITE_DATABASE_ID || 'hito';

if (!ENDPOINT || !PROJECT) {
  console.error('✗ Faltan APPWRITE_ENDPOINT / APPWRITE_PROJECT_ID en .env');
  process.exit(1);
}

// Cliente GUEST: solo endpoint + project, sin setKey().
const client = new Client().setEndpoint(ENDPOINT).setProject(PROJECT);
const databases = new Databases(client);

const props = JSON.parse(
  await readFile(new URL('../../assets/seed/properties.json', import.meta.url), 'utf8'),
);
console.log(`\n▶ Seed GUEST "properties" — ${props.length} documentos (sin API key)`);

let creados = 0, actualizados = 0, errores = 0;
for (const p of props) {
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
      console.error(`  ✗ ${id}: ${e.code || ''} ${e.message}`);
    }
  }
}
console.log(`\n${creados} creados, ${actualizados} actualizados, ${errores} errores.`);
if (errores > 0 && creados === 0 && actualizados === 0) process.exitCode = 1;
