// Norma de interfaz: un modal es para confirmar o decidir algo corto. Si pide más de TRES campos,
// es una página (ruta propia, botón «atrás» que funciona, barra de acciones fija, contexto al lado).
//
//   npm run check:modales
//
// Cuenta, dentro de cada <ModalShell>, los campos de captura: input (menos radios), select y textarea.
// Los modales que ya superaban el límite cuando se adoptó la norma (12 oct 2026) están en
// scripts/modales-heredados.json con su tope actual: ese tope solo puede BAJAR. Un modal nuevo con más de
// tres campos, o uno heredado que crezca, hace fallar la comprobación. Al convertir uno en página se borra
// de la lista.

import ts from 'typescript';
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const LIMITE = 3;
const raiz = join(dirname(fileURLToPath(import.meta.url)), '..');
const src = join(raiz, 'src');
const heredadosFile = join(dirname(fileURLToPath(import.meta.url)), 'modales-heredados.json');
const heredados = existsSync(heredadosFile) ? JSON.parse(readFileSync(heredadosFile, 'utf8')) : {};

const files = [];
(function walk(d) {
  for (const f of readdirSync(d)) {
    const p = join(d, f);
    if (statSync(p).isDirectory()) walk(p);
    else if (/\.tsx$/.test(f) && !/\.test\./.test(f)) files.push(p);
  }
})(src);

const medido = {}; // archivo -> máximo de campos en un modal
for (const f of files) {
  const sf = ts.createSourceFile(f, readFileSync(f, 'utf8'), ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
  const rel = relative(raiz, f).replace(/\\/g, '/');
  const contar = (nodo) => {
    let n = 0;
    (function visit(x) {
      const el = ts.isJsxOpeningElement(x) || ts.isJsxSelfClosingElement(x) ? x : null;
      if (el) {
        const tag = el.tagName.getText();
        if (tag === 'select' || tag === 'textarea') n++;
        if (tag === 'input') {
          const type = el.attributes.properties.find((a) => ts.isJsxAttribute(a) && a.name.getText() === 'type');
          const valor = type && ts.isJsxAttribute(type) && type.initializer && ts.isStringLiteral(type.initializer) ? type.initializer.text : 'text';
          if (valor !== 'radio' && valor !== 'hidden') n++;
        }
      }
      ts.forEachChild(x, visit);
    })(nodo);
    return n;
  };
  (function visit(x) {
    if (ts.isJsxElement(x) && x.openingElement.tagName.getText() === 'ModalShell') {
      medido[rel] = Math.max(medido[rel] ?? 0, contar(x));
    }
    ts.forEachChild(x, visit);
  })(sf);
}

const fallos = [];
for (const [archivo, campos] of Object.entries(medido)) {
  const tope = archivo in heredados ? Math.max(heredados[archivo], LIMITE) : LIMITE;
  if (campos > tope) {
    fallos.push(
      archivo in heredados
        ? `${archivo}: un modal heredado creció a ${campos} campos (tope ${tope}). Pasa el formulario a una página.`
        : `${archivo}: un modal pide ${campos} campos (máximo ${LIMITE}). Un formulario más largo va en una página, no en un modal.`
    );
  }
}
// Un heredado que ya cumple (o ya no existe) debe salir de la lista: así el tope solo baja
const sobrantes = Object.keys(heredados).filter((a) => !(a in medido) || medido[a] <= LIMITE);
for (const a of sobrantes) fallos.push(`${a}: ya cumple (o ya no tiene modal). Quítalo de scripts/modales-heredados.json.`);

const pendientes = Object.keys(heredados).filter((a) => a in medido && medido[a] > LIMITE);
if (fallos.length) {
  console.log(fallos.join('\n'));
  console.log(`\n${fallos.length} problema(s) con la norma de modales.`);
  process.exit(1);
}
console.log(`Norma de modales: ${Object.keys(medido).length} archivos con modal; ${pendientes.length} heredado(s) por convertir en página.`);
for (const a of pendientes) console.log(`  · ${a}: ${medido[a]} campos`);
