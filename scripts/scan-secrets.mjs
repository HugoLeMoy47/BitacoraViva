// Escáner de secretos (Regla Dura 2: service_role nunca llega al navegador ni al repositorio).
// Revisa los archivos versionados y falla si encuentra:
//   · un JWT cuyo rol es `service_role` (la clave `anon` es pública por diseño y se permite);
//   · una clave secreta nueva de Supabase (`sb_secret_…`);
//   · una llave privada PEM.
//
//   npm run scan:secrets            revisa el repositorio
//   npm run scan:secrets -- --self-test   comprueba que el escáner detecta lo que debe
//
// No imprime nunca el secreto encontrado: solo archivo, línea y tipo.

import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');

const JWT = /eyJ[A-Za-z0-9_-]{10,}\.([A-Za-z0-9_-]{10,})\.[A-Za-z0-9_-]{10,}/g;
const SB_SECRET = /sb_secret_[A-Za-z0-9_-]{20,}/g;
const PEM = /-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/g;

export function findSecrets(text) {
  const hits = [];
  const lines = text.split(/\r?\n/);
  lines.forEach((line, i) => {
    for (const m of line.matchAll(JWT)) {
      try {
        const payload = JSON.parse(Buffer.from(m[1], 'base64url').toString('utf8'));
        if (payload && payload.role === 'service_role') hits.push({ line: i + 1, kind: 'JWT con rol service_role' });
      } catch {
        /* no es un JWT legible: se ignora */
      }
    }
    if (SB_SECRET.test(line)) hits.push({ line: i + 1, kind: 'clave secreta de Supabase (sb_secret_)' });
    SB_SECRET.lastIndex = 0;
    if (PEM.test(line)) hits.push({ line: i + 1, kind: 'llave privada PEM' });
    PEM.lastIndex = 0;
  });
  return hits;
}

function selfTest() {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const jwt = (role) => `eyJ${b64({ alg: 'HS256' }).slice(3)}.${b64({ iss: 'supabase', role })}.${'x'.repeat(20)}`;
  const cases = [
    ['JWT service_role se detecta', `KEY=${jwt('service_role')}`, 1],
    ['JWT anon NO se marca (es pública por diseño)', `KEY=${jwt('anon')}`, 0],
    ['sb_secret_ se detecta', `KEY=sb_secret_${'a'.repeat(30)}`, 1],
    // La muestra se arma en tiempo de ejecución: escrita literal, el escáner se detectaría a sí mismo
    ['llave privada PEM se detecta', ['-----BEGIN', 'PRIVATE KEY-----'].join(' '), 1],
    ['texto normal no se marca', 'service_role nunca llega al navegador', 0],
  ];
  let bad = 0;
  for (const [name, text, expected] of cases) {
    const got = findSecrets(text).length;
    const ok = got === expected;
    if (!ok) bad++;
    console.log(`${ok ? 'OK     ' : 'FALLA  '}${name}`);
  }
  process.exit(bad ? 1 : 0);
}

if (process.argv.includes('--self-test')) selfTest();

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const files = execSync('git ls-files', { cwd: root, encoding: 'utf8' }).split(/\r?\n/).filter(Boolean);
  const SKIP = /\.(png|jpe?g|gif|ico|woff2?|ttf|pdf|zip|lock)$|package-lock\.json$/i;
  let total = 0;
  for (const f of files) {
    if (SKIP.test(f)) continue;
    let text;
    try {
      text = readFileSync(join(root, f), 'utf8');
    } catch {
      continue;
    }
    for (const h of findSecrets(text)) {
      total++;
      console.log(`SECRETO  ${f}:${h.line}  ${h.kind}`);
    }
  }
  if (total) {
    console.log(`\n${total} posible(s) secreto(s). Retíralos del repositorio y rota la clave.`);
    process.exit(1);
  }
  console.log(`Sin secretos en ${files.length} archivos versionados (la clave anon es pública por diseño).`);
}
