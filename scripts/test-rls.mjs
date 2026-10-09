// Corre las pruebas negativas de RLS (supabase/tests/rls_negative.sql) contra el
// proyecto enlazado. La transacción de prueba siempre se revierte: no deja datos.
//
//   npm run test:rls
//
// Sale con código 1 si alguna prueba falla.
//
// Validar migraciones SIN aplicarlas a la base:
//
//   npm run test:rls -- --include=20261009
//
// Las migraciones cuyo nombre empieza con el prefijo se ejecutan DENTRO de la misma
// transacción de prueba, antes del escenario, y se revierten con ella. Así una migración
// nueva se prueba contra el motor real sin pasar por `db push` ni dejar rastro.

import { execSync } from 'node:child_process';
import { mkdtempSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
let sql = readFileSync(join(root, 'supabase', 'tests', 'rls_negative.sql'), 'utf8');

const include = process.argv.find((a) => a.startsWith('--include='))?.slice('--include='.length);
if (include) {
  const dir = join(root, 'supabase', 'migrations');
  const files = readdirSync(dir).filter((f) => f.endsWith('.sql') && f.startsWith(include)).sort();
  if (files.length === 0) {
    console.error(`Ninguna migración empieza con «${include}».`);
    process.exit(1);
  }
  console.log(`Se aplican dentro de la transacción de prueba (y se revierten): ${files.join(', ')}`);
  const body = files.map((f) => `-- >>> ${f}\n${readFileSync(join(dir, f), 'utf8')}\n`).join('\n');
  sql = sql.replace(/^begin;\s*$/m, () => `begin;\n\n${body}`);
}
const file = join(mkdtempSync(join(tmpdir(), 'bv-rls-')), 'rls_negative.sql');
writeFileSync(file, sql);

let text;
try {
  execSync(`npx supabase db query --linked -f "${file}"`, { cwd: root, encoding: 'utf8', stdio: 'pipe' });
  console.error('La transacción de prueba no terminó con el resultado esperado.');
  process.exit(1);
} catch (e) {
  text = `${e.stdout || ''}${e.stderr || ''}`;
}

const start = text.indexOf('RLS_RESULTS');
if (start < 0) {
  console.error('No se obtuvo el reporte de pruebas. Salida:\n' + text.slice(0, 2000));
  process.exit(1);
}

// El reporte llega dentro de un JSON con saltos de línea escapados.
const lines = text
  .slice(start)
  .split(/\\n|\n/)
  .map((l) => l.replace(/\\"/g, '"').trim())
  .filter((l) => /^(PASS|FAIL)\^/.test(l));

let failed = 0;
for (const l of lines) {
  const [verdict, name, expected, actual] = l.split('^');
  if (verdict === 'FAIL') {
    failed++;
    console.log(`FALLA  ${name}  (esperado: ${expected} / obtenido: ${actual})`);
  }
}
const passed = lines.length - failed;
console.log(`\n${passed} pruebas pasan, ${failed} fallan, ${lines.length} en total.`);
process.exit(failed > 0 ? 1 : 0);
