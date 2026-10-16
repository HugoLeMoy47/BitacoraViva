// Norma de interfaz: la pantalla de Auditoría nunca muestra el nombre técnico de una tabla (`person_occupation`):
// cada tabla con disparador de auditoría necesita su etiqueta en `audit.tables` de src/locales/es.json.
// El auditor de interfaz lo detecta como «código técnico visible», pero tarda ~9 minutos; esto lo encuentra en un segundo.
//
//   npm run check:etiquetas-auditoria
//
// Lee las migraciones (`create trigger trg_audit_<tabla>`) y compara con las etiquetas.

import { readdirSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..');
const dir = join(raiz, 'supabase', 'migrations');
const tablas = new Set();
for (const f of readdirSync(dir).filter((x) => x.endsWith('.sql'))) {
  for (const m of readFileSync(join(dir, f), 'utf8').matchAll(/create trigger trg_audit_([a-z_]+)/gi)) tablas.add(m[1]);
}
const etiquetas = JSON.parse(readFileSync(join(raiz, 'src', 'locales', 'es.json'), 'utf8')).audit?.tables ?? {};

const faltan = [...tablas].filter((t) => !(t in etiquetas)).sort();
if (faltan.length > 0) {
  console.error('Tablas con auditoría sin etiqueta en audit.tables (es.json):');
  for (const t of faltan) console.error('  ' + t);
  process.exit(1);
}
console.log(`Etiquetas de auditoría: ${tablas.size} tablas auditadas, todas con etiqueta.`);
