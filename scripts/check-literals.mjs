// Regla Dura 9: cero literales de texto visible en componentes. Toda cadena que ve una persona
// va con clave de traducción en src/locales/es.json (aunque solo exista español).
//
//   npm run check:literals
//
// Recorre el AST de TypeScript de cada componente (.tsx, sin pruebas) y falla si encuentra:
//   · texto JSX con palabras (<p>Hola mundo</p>);
//   · atributos visibles con texto fijo (placeholder, title, aria-label, alt, label);
//   · cadenas en expresiones JSX ({'Hola mundo'});
//   · alternativas literales visibles (x || 'Sin dato');
//   · ramas literales de un condicional en el contenido ({cond ? 'Texto' : t('clave')}).
// `check:i18n` comprueba lo contrario: que toda clave usada exista.

import ts from 'typescript';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', 'src');
const files = [];
(function walk(d) {
  for (const f of readdirSync(d)) {
    const p = join(d, f);
    if (statSync(p).isDirectory()) walk(p);
    else if (/\.tsx$/.test(f) && !/\.test\./.test(f)) files.push(p);
  }
})(root);

const ATTRS = new Set(['placeholder', 'title', 'aria-label', 'alt', 'label', 'aria-description']);
const hasWords = (s) => /[A-Za-zÁÉÍÓÚáéíóúñÑ]{3,}/.test(s);
// Códigos de documentación que nunca deben verse en pantalla («(C1)», «BV-4.3», «Ethos»…)
const CODE = /\(C[1-8]\)|\bBV-\d|\bMD-\d|\bADR-\d|\bEthos\b|\bRegla Dura\b|\bP-0\d\b/;
const found = [];

for (const f of files) {
  const sf = ts.createSourceFile(f, readFileSync(f, 'utf8'), ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
  const add = (node, kind, text) => {
    const { line } = sf.getLineAndCharacterOfPosition(node.getStart());
    found.push(`${relative(root, f).replace(/\\/g, '/')}:${line + 1}  [${kind}]  ${text.replace(/\s+/g, ' ').trim().slice(0, 70)}`);
  };
  (function visit(n) {
    if (ts.isJsxText(n) && (hasWords(n.getText()) || CODE.test(n.getText()))) add(n, 'texto JSX', n.getText());
    if (ts.isJsxAttribute(n) && n.initializer && ts.isStringLiteral(n.initializer) && ATTRS.has(n.name.getText()) && hasWords(n.initializer.text)) {
      add(n, `atributo ${n.name.getText()}`, n.initializer.text);
    }
    // Atributo visible con expresión: title={cond ? 'Texto' : undefined}
    if (ts.isJsxAttribute(n) && n.initializer && ts.isJsxExpression(n.initializer) && n.initializer.expression && ATTRS.has(n.name.getText())) {
      (function strings(e) {
        // t('clave') es justamente lo correcto: no se mira dentro de las llamadas a t(...)
        if (ts.isCallExpression(e) && e.expression.getText() === 't') return;
        // En `cond ? 'A' : 'B'` solo importan las ramas; una comparación (x === 'clave') no es texto visible
        if (ts.isConditionalExpression(e)) { strings(e.whenTrue); strings(e.whenFalse); return; }
        if (ts.isBinaryExpression(e) && [ts.SyntaxKind.EqualsEqualsEqualsToken, ts.SyntaxKind.ExclamationEqualsEqualsToken, ts.SyntaxKind.EqualsEqualsToken, ts.SyntaxKind.ExclamationEqualsToken].includes(e.operatorToken.kind)) return;
        if ((ts.isStringLiteral(e) || ts.isNoSubstitutionTemplateLiteral(e)) && hasWords(e.text) && !/^\{\w+\}$/.test(e.text)) add(e, `atributo ${n.name.getText()}`, e.text);
        else ts.forEachChild(e, strings);
      })(n.initializer.expression);
    }
    if (ts.isJsxExpression(n) && n.expression && (ts.isStringLiteral(n.expression) || ts.isNoSubstitutionTemplateLiteral(n.expression)) && hasWords(n.expression.text)) {
      add(n, 'cadena en JSX', n.expression.text);
    }
    // Texto escrito a mano en la rama de un condicional que es CONTENIDO: {cond ? 'Anonimizado' : t('clave')}
    // (no se miran los atributos: className={cond ? 'bg-x' : 'bg-y'} no es texto visible)
    if (ts.isJsxExpression(n) && n.expression && ts.isConditionalExpression(n.expression) && n.parent && (ts.isJsxElement(n.parent) || ts.isJsxFragment(n.parent))) {
      for (const rama of [n.expression.whenTrue, n.expression.whenFalse]) {
        if ((ts.isStringLiteral(rama) || ts.isNoSubstitutionTemplateLiteral(rama)) && hasWords(rama.text)) add(rama, 'rama literal en contenido', rama.text);
      }
    }
    if (
      ts.isBinaryExpression(n) &&
      (n.operatorToken.kind === ts.SyntaxKind.BarBarToken || n.operatorToken.kind === ts.SyntaxKind.QuestionQuestionToken) &&
      ts.isStringLiteral(n.right) &&
      /[A-ZÁÉÍÓÚ][a-záéíóú]+ [a-záéíóú]+/.test(n.right.text)
    ) {
      add(n.right, 'alternativa literal', n.right.text);
    }
    ts.forEachChild(n, visit);
  })(sf);
}

if (found.length) {
  console.log(found.join('\n'));
  console.log(`\n${found.length} texto(s) escrito(s) a mano en componentes. Muévelos a src/locales/es.json con t('clave').`);
  process.exit(1);
}
console.log(`Sin literales de texto en ${files.length} componentes.`);
