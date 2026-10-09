// Reinicia la DEMO: vacia los datos de negocio y vuelve a sembrar supabase/seed.sql.
//
//   npm run demo:reset -- --confirm <project-ref>             reinicia
//   npm run demo:reset -- --confirm <project-ref> --dry-run   prueba completa y revierte
//
// Requiere el CLI de Supabase con sesion iniciada y el proyecto enlazado
// (supabase login && supabase link). Para que no se ejecute en un proyecto equivocado,
// --confirm debe coincidir con el proyecto enlazado, y la base misma se niega si su
// entorno (public.app_config) no es "demo".

import { execSync } from 'node:child_process';
import { mkdtempSync, readFileSync, readdirSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const confirmIdx = args.indexOf('--confirm');
const confirm = confirmIdx >= 0 ? args[confirmIdx + 1] : undefined;

const refFile = join(root, 'supabase', '.temp', 'project-ref');
if (!existsSync(refFile)) {
  console.error('No hay proyecto enlazado. Ejecuta: npx supabase link --project-ref <ref>');
  process.exit(1);
}
const linked = readFileSync(refFile, 'utf8').trim();

if (confirm !== linked) {
  console.error(`Proyecto enlazado: ${linked}`);
  console.error(`Para continuar, repite el comando con: --confirm ${linked}`);
  console.error('Esto BORRA todos los datos de la demo (incluida la auditoria) y los vuelve a sembrar.');
  process.exit(1);
}

const reset = readFileSync(join(root, 'supabase', 'demo', 'reset_demo.sql'), 'utf8');
const seed = readFileSync(join(root, 'supabase', 'seed.sql'), 'utf8');

// Probar una migración nueva junto con el reinicio y la semilla, SIN aplicarla: solo con --dry-run.
//   npm run demo:reset -- --confirm <ref> --dry-run --include=20261009
const include = args.find((a) => a.startsWith('--include='))?.slice('--include='.length);
let migrations = '';
if (include) {
  if (!dryRun) {
    console.error('--include solo se admite junto con --dry-run: las migraciones se aplican con `supabase db push`.');
    process.exit(1);
  }
  const dir = join(root, 'supabase', 'migrations');
  const files = readdirSync(dir).filter((f) => f.endsWith('.sql') && f.startsWith(include)).sort();
  if (files.length === 0) {
    console.error(`Ninguna migración empieza con «${include}».`);
    process.exit(1);
  }
  console.log(`Se aplican dentro de la transacción de prueba (y se revierten): ${files.join(', ')}`);
  migrations = files.map((f) => `-- >>> ${f}\n${readFileSync(join(dir, f), 'utf8')}\n`).join('\n');
}

const summary = `
select
  (select value from public.app_config where key = 'environment') as entorno,
  (select count(*) from auth.users where email like '%@alberguesantafe.org') as usuarios_demo,
  (select count(*) from public."case") as casos,
  (select count(*) from public.person) as personas,
  (select count(*) from public.journal_entry) as entradas_bitacora,
  (select count(*) from public.task) as tareas,
  (select count(*) from public.routine_template) as rutinas,
  (select count(*) from public.shift_note) as notas_turno,
  (select count(*) from public.audit_event) as eventos_auditoria`;

// Dry-run: el resumen se calcula dentro de la transaccion y se devuelve como error, lo que la revierte.
const closing = dryRun
  ? `do $$ declare r text; begin
       select concat_ws(', ', 'entorno=' || s.entorno, 'usuarios_demo=' || s.usuarios_demo, 'casos=' || s.casos,
                        'personas=' || s.personas, 'entradas_bitacora=' || s.entradas_bitacora,
                        'tareas=' || s.tareas, 'rutinas=' || s.rutinas, 'notas_turno=' || s.notas_turno,
                        'eventos_auditoria=' || s.eventos_auditoria) into r from (${summary}) s;
       raise exception 'DRY-RUN OK (revertido): %', r;
     end $$;`
  : `commit;\n${summary};`;

const sql = `begin;\n${migrations}\n${reset}\n${seed}\n${closing}\n`;
const file = join(mkdtempSync(join(tmpdir(), 'bv-reset-')), 'reset-and-seed.sql');
writeFileSync(file, sql);

console.log(`${dryRun ? '[DRY-RUN] ' : ''}Reiniciando demo en el proyecto ${linked}...`);
try {
  const out = execSync(`npx supabase db query --linked -f "${file}"`, { cwd: root, encoding: 'utf8' });
  console.log(out);
} catch (e) {
  const text = `${e.stdout || ''}${e.stderr || ''}`;
  const m = text.match(/DRY-RUN OK \(revertido\): [^"\\]*/);
  if (dryRun && m) {
    console.log(m[0]);
    process.exit(0);
  }
  console.error(text || e.message);
  process.exit(1);
}
