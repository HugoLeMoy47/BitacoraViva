// Lee supabase/migrations/*.sql y devuelve las tablas con columnas, claves y referencias.
// Cubre CREATE TABLE y los ALTER TABLE ... ADD/DROP/RENAME COLUMN más los que cambian el esquema vigente.
import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'

const dir = new URL('../../supabase/migrations/', import.meta.url)
const files = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()
const tables = new Map()
const clean = (s) => s.replace(/--.*$/gm, '')
const nm = (s) => s.replace(/"/g, '').replace(/^public\./, '')

function parseColumn(line) {
  const m = line.match(/^\s*"?([a-z_0-9]+)"?\s+([a-z_]+(?:\(\d+(?:,\d+)?\))?(?:\[\])?)(.*)$/i)
  if (!m) return null
  const [, name, rawType, rest] = m
  const ref = rest.match(/references\s+([a-z_."]+)\s*\(([a-z_]+)\)/i)
  return {
    name, type: rawType.toLowerCase(),
    pk: /primary key/i.test(rest), uk: /\bunique\b/i.test(rest),
    notNull: /not null/i.test(rest) || /primary key/i.test(rest),
    ref: ref ? `${nm(ref[1]).replace('.', '_')}.${ref[2]}` : null,
  }
}

for (const f of files) {
  const sql = clean(readFileSync(join(dir.pathname.replace(/^\/([A-Za-z]:)/, '$1'), f), 'utf8'))
  for (const m of sql.matchAll(/create table(?: if not exists)?\s+([a-z_."]+)\s*\(([\s\S]*?)\n\);/gi)) {
    const name = nm(m[1]); if (name.includes('.')) continue
    const cols = []; const composite = []
    let depth = 0, buf = ''
    const lines = []
    for (const ch of m[2]) { // separa por comas de primer nivel
      if (ch === '(') depth++; if (ch === ')') depth--
      if (ch === ',' && depth === 0) { lines.push(buf); buf = '' } else buf += ch
    }
    lines.push(buf)
    for (const l of lines.map((x) => x.trim()).filter(Boolean)) {
      const fk = l.match(/^foreign key\s*\(([^)]+)\)\s*references\s+([a-z_."]+)\s*\(([^)]+)\)/i)
      if (fk) { composite.push({ cols: fk[1].split(',').map((s) => s.trim()), table: nm(fk[2]), to: fk[3].split(',')[0].trim() }); continue }
      if (/^(unique|check|primary key|constraint)\b/i.test(l)) continue
      const c = parseColumn(l); if (c) cols.push(c)
    }
    for (const fk of composite) {
      const c = cols.find((x) => x.name === fk.cols[0]); if (c) c.ref = `${fk.table}.${fk.to}`
    }
    tables.set(name, cols)
  }
  for (const m of sql.matchAll(/alter table\s+(?:if exists\s+)?([a-z_."]+)\s+([\s\S]*?);/gi)) {
    const t = nm(m[1]); const cols = tables.get(t); if (!cols) continue
    for (const part of m[2].split(/,\s*(?=add column|drop column|alter column|rename column)/i)) {
      const add = part.match(/add column(?: if not exists)?\s+([\s\S]+)/i)
      if (add) { const c = parseColumn(add[1].trim()); if (c && !cols.find((x) => x.name === c.name)) cols.push(c) }
      const afk = part.match(/foreign key\s*\(([^)]+)\)\s*references\s+([a-z_."]+)\s*\(([^)]+)\)/i)
      if (afk) { const c = cols.find((x) => x.name === afk[1].split(',')[0].trim()); if (c) c.ref = `${nm(afk[2])}.${afk[3].split(',')[0].trim()}` }
      const drop = part.match(/drop column(?: if exists)?\s+"?([a-z_]+)"?/i)
      if (drop) { const i = cols.findIndex((x) => x.name === drop[1]); if (i >= 0) cols.splice(i, 1) }
      const ren = part.match(/rename column\s+([a-z_]+)\s+to\s+([a-z_]+)/i)
      if (ren) { const c = cols.find((x) => x.name === ren[1]); if (c) c.name = ren[2] }
    }
  }
  for (const m of sql.matchAll(/alter table\s+([a-z_."]+)\s+rename column\s+([a-z_]+)\s+to\s+([a-z_]+)/gi)) {
    const c = tables.get(nm(m[1]))?.find((x) => x.name === m[2]); if (c) c.name = m[3]
  }
  for (const m of sql.matchAll(/drop table(?: if exists)?\s+([a-z_."]+)/gi)) tables.delete(nm(m[1]))
}
export { tables }
if (process.argv[1].endsWith('parse-schema.mjs')) {
  for (const [t, c] of tables) console.log(t.padEnd(28), c.length, c.filter((x) => x.ref).map((x) => `${x.name}->${x.ref}`).join(' '))
}
