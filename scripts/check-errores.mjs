// E13 fase 1: cada error de dominio de la base lleva un código estable (BVnnn) y cada código tiene su texto en
// pantalla. Comprueba, sin base de datos:
//   · todo `errcode = 'BVnnn'` de las migraciones tiene su texto en src/locales/es.json (errors.db.bvnnn);
//   · ningún texto de errors.db sobra (sin código que lo use);
//   · todo código BVnnn escrito en el código de la interfaz existe en el catálogo;
//   · ningún texto de error trae referencias internas (Ethos, ADR, BV-x.y, nombres de funciones…).
// (Que ninguna función VIGENTE levante un error sin código lo comprueba la suite de la base: «E13: ninguna función…».)
//
//   npm run check:errores            |   npm run check:errores -- --locale=ruta/es.json   (para probarlo con otro archivo)

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..');
const arg = process.argv.find((a) => a.startsWith('--locale='));
const locale = JSON.parse(readFileSync(arg ? arg.slice('--locale='.length) : join(raiz, 'src', 'locales', 'es.json'), 'utf8'));
const textos = locale.errors?.db ?? {};

// Códigos que levantan las migraciones
const enBase = new Set();
const dirMig = join(raiz, 'supabase', 'migrations');
for (const f of readdirSync(dirMig).filter((x) => x.endsWith('.sql'))) {
  for (const m of readFileSync(join(dirMig, f), 'utf8').matchAll(/errcode\s*=\s*'(BV\d{3})'/gi)) enBase.add(m[1].toLowerCase());
}

// Códigos escritos en la interfaz (p. ej. new DbError('…', 'BV203'))
const enInterfaz = new Set();
(function walk(d) {
  for (const f of readdirSync(d)) {
    const p = join(d, f);
    if (statSync(p).isDirectory()) walk(p);
    else if (/\.(ts|tsx)$/.test(f) && !/\.test\./.test(f)) for (const m of readFileSync(p, 'utf8').matchAll(/'(BV\d{3})'/g)) enInterfaz.add(m[1].toLowerCase());
  }
})(join(raiz, 'src'));

const fallos = [];
for (const c of enBase) if (!(c in textos)) fallos.push(`El código ${c.toUpperCase()} lo levanta la base pero no tiene texto en errors.db.${c} (src/locales/es.json).`);
for (const c of Object.keys(textos)) if (!enBase.has(c) && !enInterfaz.has(c)) fallos.push(`errors.db.${c} no corresponde a ningún código de la base ni de la interfaz: sobra.`);
for (const c of enInterfaz) if (!(c in textos)) fallos.push(`La interfaz usa el código ${c.toUpperCase()} pero errors.db.${c} no existe.`);
const INTERNO = /\b(Ethos|ADR-\d|BV-\d|MD-\d|fn_\w+|Regla Dura|P-0\d)\b|\(C[1-8]\)/;
for (const [c, t] of Object.entries(textos)) {
  if (typeof t !== 'string' || !t.trim()) fallos.push(`errors.db.${c} está vacío.`);
  else if (INTERNO.test(t)) fallos.push(`errors.db.${c} trae una referencia interna que no debe verse en pantalla: «${t}»`);
}

if (fallos.length) {
  console.log(fallos.join('\n'));
  console.log(`\n${fallos.length} problema(s) con los códigos de error.`);
  process.exit(1);
}
console.log(`Códigos de error: ${enBase.size} en la base, ${Object.keys(textos).length} con texto; ${enInterfaz.size} en la interfaz.`);
