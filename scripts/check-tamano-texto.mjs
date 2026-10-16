// Norma de interfaz: ningún texto visible por debajo de 12 px (el auditor de interfaz lo mide, pero tarda ~9 minutos
// en el CI; esta comprobación estática encuentra lo mismo en un segundo).
//
//   npm run check:tamano-texto
//
// Busca clases de Tailwind con tamaño fijo menor a 12 px (`text-[11px]`, `text-[10px]`…) en los componentes.
// Excepción documentada: el recibo imprimible de derechos ARCO (`ArcoReceiptModal`) es un documento para imprimir,
// no pantalla. Para una excepción nueva, agrégala a EXCEPCIONES con su motivo.

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const MINIMO = 12;
const EXCEPCIONES = {
  'src/components/ArcoReceiptModal.tsx': 'documento imprimible (recibo ARCO), no pantalla',
};

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..');
const files = [];
(function walk(d) {
  for (const f of readdirSync(d)) {
    const p = join(d, f);
    if (statSync(p).isDirectory()) walk(p);
    else if (/\.tsx$/.test(f) && !/\.test\./.test(f)) files.push(p);
  }
})(join(raiz, 'src'));

const hallazgos = [];
for (const file of files) {
  const rel = relative(raiz, file).replace(/\\/g, '/');
  if (EXCEPCIONES[rel]) continue;
  readFileSync(file, 'utf8').split('\n').forEach((line, i) => {
    for (const m of line.matchAll(/text-\[(\d+(?:\.\d+)?)px\]/g)) {
      if (Number(m[1]) < MINIMO) hallazgos.push(`${rel}:${i + 1}  ${m[0]}`);
    }
  });
}

if (hallazgos.length > 0) {
  console.error(`Texto menor de ${MINIMO} px (usa text-xs, que es de 12 px):`);
  for (const h of hallazgos) console.error('  ' + h);
  process.exit(1);
}
console.log(`Ningún texto menor de ${MINIMO} px en ${files.length} componentes.`);
