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

import { execSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
let sql = readFileSync(join(root, 'supabase', 'tests', 'rls_negative.sql'), 'utf8');

const target = process.argv.includes('--local') ? '--local' : '--linked';
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

// En GitHub Actions las fallas se publican además como anotaciones, legibles sin abrir el log.
const annotate = (msg) => {
  if (!process.env.GITHUB_ACTIONS) return;
  const esc = String(msg).split('%').join('%25').split('\r').join('%0D').split('\n').join('%0A');
  console.log('::error title=test-rls::' + esc.slice(0, 6000));
};

// Ejecuta el archivo y devuelve { ok, text }. La prueba termina SIEMPRE con un error deliberado
// (así la transacción se revierte), por lo que lo esperado es ok = false y el reporte en el texto.
//  · --linked: API de gestión del proyecto enlazado (acepta un archivo con varias sentencias).
//  · --local:  `supabase db query --local` usa el protocolo extendido y NO admite varias
//              sentencias, así que se usa psql directo (o el psql del contenedor de Postgres).
function run() {
  if (target === '--local') {
    const url = process.env.RLS_DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
    let r = spawnSync('psql', [url, '-X', '-q', '-v', 'ON_ERROR_STOP=1', '-f', file], { cwd: root, encoding: 'utf8' });
    if (r.error && r.error.code === 'ENOENT') {
      r = spawnSync(
        'docker',
        ['exec', '-i', 'supabase_db_bitacora-viva', 'psql', '-U', 'postgres', '-d', 'postgres', '-X', '-q', '-v', 'ON_ERROR_STOP=1'],
        { input: sql, encoding: 'utf8' }
      );
    }
    if (r.error) return { ok: false, text: `No se pudo ejecutar psql ni docker: ${r.error.message}` };
    return { ok: r.status === 0, text: `${r.stdout || ''}${r.stderr || ''}` };
  }
  try {
    execSync(`npx supabase db query ${target} -f "${file}"`, { cwd: root, encoding: 'utf8', stdio: 'pipe' });
    return { ok: true, text: '' };
  } catch (e) {
    return { ok: false, text: `${e.stdout || ''}${e.stderr || ''}` };
  }
}

const result = run();
if (result.ok) {
  console.error('La transacción de prueba no terminó con el resultado esperado.');
  annotate('La transacción de prueba terminó sin error: debía revertirse con un error deliberado.');
  process.exit(1);
}
const text = result.text;

const start = text.indexOf('RLS_RESULTS');
if (start < 0) {
  console.error('No se obtuvo el reporte de pruebas. Salida:\n' + text.slice(0, 2000));
  annotate('Sin reporte de pruebas. Salida: ' + text.slice(0, 2500));
  process.exit(1);
}

// El reporte llega dentro de un JSON con saltos de línea escapados.
const lines = text
  .slice(start)
  .split(/\\n|\n/)
  .map((l) => l.replace(/\\"/g, '"').trim())
  .filter((l) => /^(PASS|FAIL)\^/.test(l));

let failed = 0;
const failures = [];
for (const l of lines) {
  const [verdict, name, expected, actual] = l.split('^');
  if (verdict === 'FAIL') {
    failed++;
    failures.push(`${name} (esperado ${expected} / obtenido ${String(actual).slice(0, 80)})`);
    console.log(`FALLA  ${name}  (esperado: ${expected} / obtenido: ${actual})`);
  }
}
const passed = lines.length - failed;
console.log(`\n${passed} pruebas pasan, ${failed} fallan, ${lines.length} en total.`);
if (failed > 0) annotate(`${failed} prueba(s) fallan:\n` + failures.slice(0, 40).join('\n'));
if (lines.length === 0) annotate('El reporte llegó vacío. Texto: ' + text.slice(start, start + 1500));
process.exit(failed > 0 || lines.length === 0 ? 1 : 0);
