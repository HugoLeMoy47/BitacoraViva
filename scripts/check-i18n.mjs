// Verifica que toda clave de traducción usada en el código exista en src/locales/es.json.
// Sale con código 1 si falta alguna: así una clave sin resolver nunca llega a pantalla.
//
//   npm run check:i18n

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const locale = JSON.parse(readFileSync(join(root, 'src', 'locales', 'es.json'), 'utf8'));

const has = (key) => {
  let cur = locale;
  for (const part of key.split('.')) {
    if (cur && typeof cur === 'object' && part in cur) cur = cur[part];
    else return false;
  }
  return typeof cur === 'string';
};

const files = [];
(function walk(dir) {
  for (const f of readdirSync(dir)) {
    const p = join(dir, f);
    if (statSync(p).isDirectory()) walk(p);
    else if (/\.tsx?$/.test(f)) files.push(p);
  }
})(join(root, 'src'));

const missing = new Map();
for (const file of files) {
  const src = readFileSync(file, 'utf8');
  for (const m of src.matchAll(/\bt\(\s*(['"`])([^'"`]+)\1/g)) {
    const key = m[2];
    if (key.includes('${')) continue; // plantilla dinámica: se revisa a mano
    if (!has(key)) {
      if (!missing.has(key)) missing.set(key, new Set());
      missing.get(key).add(basename(file));
    }
  }
}

if (missing.size > 0) {
  console.error(`Faltan ${missing.size} claves de traducción:`);
  for (const [key, where] of missing) console.error(`  ${key}  ←  ${[...where].join(', ')}`);
  process.exit(1);
}
console.log('Traducciones: todas las claves usadas existen.');

// Inglés: el español es la fuente. Toda clave de en.json debe existir en es.json y llevar los mismos {marcadores}.
// Mientras la traducción se completa, lo que falta se muestra en español (t() cae al español) y aquí solo se informa;
// con --completo la falta de una clave es un error (la condición para ofrecer el inglés en el selector).
const flatten = (obj, prefix = '', out = new Map()) => {
  for (const [k, v] of Object.entries(obj)) {
    const key = prefix ? `${prefix}.${k}` : k;
    if (v && typeof v === 'object') flatten(v, key, out);
    else out.set(key, String(v));
  }
  return out;
};
const es = flatten(locale);
const en = flatten(JSON.parse(readFileSync(join(root, 'src', 'locales', 'en.json'), 'utf8')));
const marcadores = (txt) => [...txt.matchAll(/\{[a-z_]+\}/g)].map((m) => m[0]).sort().join(',');
const problemas = [];
for (const [key, txt] of en) {
  if (!es.has(key)) problemas.push(`${key}: existe en en.json y no en es.json`);
  else if (marcadores(txt) !== marcadores(es.get(key))) problemas.push(`${key}: los marcadores {…} no coinciden con el español`);
}
const faltan = [...es.keys()].filter((k) => !en.has(k));
console.log(`Inglés: ${en.size} de ${es.size} claves traducidas (${Math.round((100 * en.size) / es.size)} %).`);
if (problemas.length > 0) {
  console.error(`Inglés con ${problemas.length} problemas:`);
  for (const p of problemas) console.error(`  ${p}`);
  process.exit(1);
}
if (process.argv.includes('--completo') && faltan.length > 0) {
  console.error(`Inglés incompleto: faltan ${faltan.length} claves (la primera: ${faltan[0]}).`);
  process.exit(1);
}
