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

if (missing.size === 0) {
  console.log('Traducciones: todas las claves usadas existen.');
  process.exit(0);
}
console.error(`Faltan ${missing.size} claves de traducción:`);
for (const [key, where] of missing) console.error(`  ${key}  ←  ${[...where].join(', ')}`);
process.exit(1);
