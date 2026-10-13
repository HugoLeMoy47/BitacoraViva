// Recorrido de primer uso (RNF-14): tres tareas hechas como las haría una persona que nunca vio el sistema,
// con navegador real, midiendo lo que cuestan: clics, caracteres escritos, pantallas por las que pasa,
// veces que tiene que desplazar la página para llegar a un control, y si un botón estaba deshabilitado
// cuando lo buscó (con o sin motivo visible).
//
//   npm run build && npm run primer-uso
//
// OJO: la tarea 1 y la 2 ESCRIBEN datos (un expediente de prueba y una entrada de bitácora) en la base
// a la que apunte la compilación (la demo, normalmente). Variables: AUDIT_URL para usar un servidor ya
// levantado; PRIMER_USO_OUT para guardar el informe en Markdown.
//
// El tiempo que reporta es de máquina, no de persona: el piso de pasos y clics es lo que importa.
// La prueba con una persona real queda en guion-prueba-primer-uso.md.

import { spawn } from 'node:child_process';
import { existsSync, readFileSync, statSync, writeFileSync, mkdirSync } from 'node:fs';
import http from 'node:http';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright-core';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(root, 'dist');
const PORT = 4195;
const BASE = process.env.AUDIT_URL || `http://localhost:${PORT}`;
const OUT = process.env.PRIMER_USO_OUT;
const SHOTS = process.env.PRIMER_USO_SHOTS;
if (SHOTS) mkdirSync(SHOTS, { recursive: true });

const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.json': 'application/json' };
let server = null;
if (!process.env.AUDIT_URL) {
  if (!existsSync(join(dist, 'index.html'))) { console.error('Falta compilar: npm run build'); process.exit(1); }
  server = http.createServer((req, res) => {
    let p = join(dist, decodeURIComponent(req.url.split('?')[0]));
    if (!existsSync(p) || statSync(p).isDirectory()) p = join(dist, 'index.html');
    res.writeHead(200, { 'Content-Type': TYPES[extname(p)] || 'application/octet-stream' });
    res.end(readFileSync(p));
  });
  await new Promise((r) => server.listen(PORT, r));
}

const browser = await chromium.launch({ channel: 'msedge', headless: true }).catch(() => chromium.launch({ channel: 'chrome', headless: true }));

// ---- Instrumento: cada acción cuenta y se anota lo que le habría costado a una persona ----
function makeTask(page, name) {
  const t = { name, clicks: 0, chars: 0, screens: new Set(), scrolls: 0, blockedNoReason: 0, blockedWithReason: 0, notes: [], ok: false, ms: 0 };
  const started = Date.now();
  const heading = async () => page.evaluate(() => (document.querySelector('[role=dialog] h1,[role=dialog] h2,[role=dialog] h3') || document.querySelector('main h1,main h2,h1'))?.textContent?.trim() ?? '');
  const seen = async () => { t.screens.add((await heading()) + '|' + (await page.evaluate(() => location.hash))); };
  // Una persona ve el control antes de pulsarlo: si está fuera de la pantalla, desplaza (cuesta una acción)
  const reach = async (loc, label) => {
    await loc.first().waitFor({ state: 'visible', timeout: 15000 }).catch(() => { throw new Error(`no aparece «${label}»`); });
    const inView = await loc.first().evaluate((e) => { const r = e.getBoundingClientRect(); return r.top >= 0 && r.bottom <= innerHeight && r.left >= 0 && r.right <= innerWidth; });
    if (!inView) { t.scrolls++; t.notes.push(`desplazar para llegar a «${label}»`); await loc.first().scrollIntoViewIfNeeded(); }
    if (await loc.first().isDisabled().catch(() => false)) {
      const reason = await loc.first().evaluate((e) => { const ids = (e.getAttribute('aria-describedby') || '').split(' ').filter(Boolean); return ids.map((id) => document.getElementById(id)?.textContent?.trim() || '').join(' ').trim(); });
      if (reason) { t.blockedWithReason++; t.notes.push(`«${label}» deshabilitado, dice: «${reason}»`); } else { t.blockedNoReason++; t.notes.push(`«${label}» deshabilitado SIN motivo`); }
      throw new Error(`«${label}» deshabilitado`);
    }
  };
  const api = {
    t,
    async click(loc, label) { await reach(loc, label); await loc.first().click(); t.clicks++; await page.waitForTimeout(350); await seen(); },
    async type(loc, text, label) { await reach(loc, label); await loc.first().click(); t.clicks++; await loc.first().fill(text); t.chars += text.length; await seen(); },
    async goto(hash) { await page.evaluate((h) => { location.hash = h; }, hash); await page.waitForTimeout(900); await seen(); },
    note(msg) { t.notes.push(msg); },
    async shot(file) { if (SHOTS) await page.screenshot({ path: join(SHOTS, file) }); },
    finish(ok) { t.ok = ok; t.ms = Date.now() - started; return t; },
  };
  return api;
}

async function login(page, button) {
  await page.goto(BASE + '/', { waitUntil: 'networkidle' });
  await page.getByRole('button', { name: button, exact: true }).first().waitFor({ state: 'visible', timeout: 25000 });
  await page.getByRole('button', { name: button, exact: true }).first().click();
  await page.waitForSelector('header', { timeout: 25000 });
  await page.waitForFunction(() => !document.body.innerText.includes('Cargando'), null, { timeout: 25000 }).catch(() => {});
}

// Ir a «Expedientes» como lo haría una persona: con el menú que ve (pestañas en escritorio, barra inferior en celular)
async function openCases(page, k) {
  const nav = page.locator('nav:visible').getByRole('button', { name: /^Expedientes/ }).or(page.locator('nav:visible').getByRole('tab', { name: /^Expedientes/ }));
  await k.click(nav, 'Expedientes');
}

// Encontrar un expediente concreto entre decenas, como lo haría una persona: con el buscador de la lista
async function openCase(page, k, folio) {
  await k.type(page.getByRole('searchbox').or(page.getByLabel(/Buscar expediente/i)).first(), folio, 'Buscar expediente');
  await k.click(page.getByText(folio, { exact: true }).locator('visible=true').first(), `el expediente ${folio}`);
}

// ---------------- Tarea 1: abrir un expediente nuevo ----------------
async function tarea1(page) {
  const k = makeTask(page, '1 · Abrir un expediente nuevo');
  try {
    await openCases(page, k);
    await k.click(page.getByRole('button', { name: /Levantar nuevo expediente/i }), 'Levantar nuevo expediente');
    await page.waitForTimeout(600);
    // Si el formulario es un modal se trabaja dentro de él; si es una página, dentro del contenido principal
    const d = (await page.locator('[role=dialog]').count()) ? page.locator('[role=dialog]') : page.locator('main');
    k.note('el formulario se abrió como ' + ((await page.locator('[role=dialog]').count()) ? 'modal' : 'página'));
    await page.waitForFunction(() => document.querySelectorAll('[role=dialog] input[type=radio], main input[type=radio]').length >= 2, null, { timeout: 15000 });
    await k.click(d.getByRole('checkbox', { name: /Entregué o leí/ }), 'Entregué o leí el aviso');
    // La persona decide cada consentimiento: otorga el general y no otorga los demás (el camino más corto)
    await k.click(d.getByText('Otorga', { exact: true }).nth(0), 'Otorga (atención general)');
    await k.click(d.getByText('No otorga', { exact: true }).nth(1), 'No otorga (datos sensibles)');
    await k.click(d.getByText('No otorga', { exact: true }).nth(2), 'No otorga (uso secundario)');
    await k.shot(`t1-paso0-${page.viewportSize().width}.png`);
    await k.click(d.getByRole('button', { name: /Siguiente/ }), 'Siguiente (consentimiento)');
    await k.click(d.getByRole('button', { name: /Siguiente/ }), 'Siguiente (contexto)');
    await k.type(d.getByLabel(/Nombres/), 'Prueba', 'Nombres');
    await k.type(d.getByLabel(/Primer apellido/i), 'PrimerUso', 'Primer apellido');
    await k.shot(`t1-paso2-${page.viewportSize().width}.png`);
    await k.click(d.getByRole('button', { name: /Siguiente/ }), 'Siguiente (persona)');
    await k.shot(`t1-paso4-${page.viewportSize().width}.png`);
    await k.click(d.getByRole('button', { name: /Abrir expediente/i }), 'Abrir expediente');
    await page.waitForFunction(() => /#\/expedientes\/[A-Z]+-\d{4}-\d+/.test(location.hash), null, { timeout: 15000 });
    k.note('quedó en el expediente nuevo: ' + (await page.evaluate(() => location.hash)));
    return k.finish(true);
  } catch (e) { k.note('se detuvo: ' + e.message); return k.finish(false); }
}

// ---------------- Tarea 2: primera entrada de bitácora ----------------
async function tarea2(page) {
  const k = makeTask(page, '2 · Escribir una entrada de bitácora');
  try {
    await openCases(page, k);
    await openCase(page, k, 'ASF-2026-0001');
    await k.click(page.getByRole('tab', { name: /Bitácora/ }), 'pestaña Bitácora');
    await k.click(page.getByRole('button', { name: /Nueva entrada de bitácora/i }), 'Nueva entrada de bitácora');
    await page.waitForTimeout(600);
    // Si el formulario es un modal se trabaja dentro de él; si es una página, dentro del contenido principal
    const d = (await page.locator('[role=dialog]').count()) ? page.locator('[role=dialog]') : page.locator('main');
    k.note('el formulario se abrió como ' + ((await page.locator('[role=dialog]').count()) ? 'modal' : 'página'));
    const texto = 'Primer uso: entrada de prueba escrita en el recorrido automatizado.';
    await k.type(d.getByLabel(/Cuerpo de la intervención/i), texto, 'Cuerpo de la intervención');
    await k.shot(`t2-modal-${page.viewportSize().width}.png`);
    await k.click(d.getByRole('button', { name: /Revisar vista previa/i }), 'Revisar vista previa');
    await k.click(d.getByRole('button', { name: /Asentar definitivamente/i }), 'Asentar definitivamente');
    await page.waitForFunction((x) => document.body.innerText.includes(x.slice(0, 30)), texto, { timeout: 15000 });
    return k.finish(true);
  } catch (e) { k.note('se detuvo: ' + e.message); return k.finish(false); }
}

// ---------------- Tarea 3: estatus actual de una persona y cuánto lleva en él ----------------
async function tarea3(page) {
  const k = makeTask(page, '3 · Ver el estatus actual y desde cuándo');
  try {
    await openCases(page, k);
    await openCase(page, k, 'ASF-2026-0001');
    // Éxito: en la pantalla (sin desplazar) se ve un estatus y su «Desde …»
    const visible = await page.evaluate(() => {
      const el = [...document.querySelectorAll('main *')].find((e) => e.children.length === 0 && /^Desde\b/.test(e.textContent.trim()));
      if (!el) return null;
      const r = el.getBoundingClientRect();
      return { enPantalla: r.top >= 0 && r.bottom <= innerHeight, texto: el.textContent.trim().slice(0, 40) };
    });
    if (!visible) throw new Error('no se ve ningún «Desde …» en el expediente');
    if (!visible.enPantalla) { k.t.scrolls++; k.note('hay que desplazar para ver desde cuándo (' + visible.texto + ')'); }
    await k.shot(`t3-expediente-${page.viewportSize().width}.png`);
    return k.finish(true);
  } catch (e) { k.note('se detuvo: ' + e.message); return k.finish(false); }
}

// ---------------- Tarea 4: abrir un subfolio (modal o página: el guion sirve para las dos) ----------------
async function tarea4(page) {
  const k = makeTask(page, '4 · Abrir un subfolio');
  try {
    await openCases(page, k);
    await openCase(page, k, 'ASF-2026-0001');
    await k.click(page.getByRole('button', { name: /Abrir subfolio/i }), 'Abrir subfolio');
    await page.waitForTimeout(600);
    // Si el formulario es un modal se trabaja dentro de él; si es una página, dentro del contenido principal
    const root = (await page.locator('[role=dialog]').count()) ? page.locator('[role=dialog]') : page.locator('main');
    k.note('el formulario se abrió como ' + ((await page.locator('[role=dialog]').count()) ? 'modal' : 'página'));
    await k.type(root.getByLabel(/Nombres/), 'Prueba', 'Nombres');
    await k.type(root.getByLabel(/Primer apellido/i), 'PrimerUso', 'Primer apellido');
    await k.type(root.locator('input[type=date]'), '2018-05-10', 'Fecha de nacimiento');
    await k.type(root.getByLabel(/Nota de justificación/i), 'Prueba de primer uso: subfolio abierto en el recorrido automatizado.', 'Nota de justificación');
    await k.shot(`t4-formulario-${page.viewportSize().width}.png`);
    await k.click(root.getByRole('button', { name: /Crear subfolio/i }), 'Crear subfolio');
    await page.waitForFunction(() => /#\/expedientes\/[A-Z]+-\d{4}-\d+-S\d+/.test(location.hash), null, { timeout: 15000 });
    k.note('quedó en el subfolio: ' + (await page.evaluate(() => location.hash)));
    return k.finish(true);
  } catch (e) { k.note('se detuvo: ' + e.message); return k.finish(false); }
}

const SCENARIOS = [
  { label: 'Escritorio 1280×800', viewport: { width: 1280, height: 800 }, mobile: false },
  { label: 'Celular 390×844', viewport: { width: 390, height: 844 }, mobile: true },
];
const ROLE = { 1: 'Oficial de ingreso', 2: 'Trabajo Social / caso', 3: 'Trabajo Social / caso', 4: 'Oficial de ingreso' };
const results = [];
for (const sc of SCENARIOS) {
  for (const [n, fn] of [[1, tarea1], [2, tarea2], [3, tarea3], [4, tarea4]]) {
    if (!(process.env.PRIMER_USO_TAREAS || '1,2,3,4').split(',').includes(String(n))) continue;
    const ctx = await browser.newContext({ viewport: sc.viewport, hasTouch: sc.mobile, isMobile: sc.mobile });
    const page = await ctx.newPage();
    try {
      await login(page, ROLE[n]);
      const r = await fn(page);
      results.push({ escenario: sc.label, rol: ROLE[n], ...r, screens: r.screens.size });
    } catch (e) {
      results.push({ escenario: sc.label, rol: ROLE[n], name: `${n}`, ok: false, clicks: 0, chars: 0, screens: 0, scrolls: 0, blockedNoReason: 0, blockedWithReason: 0, notes: ['no se pudo iniciar sesión: ' + e.message], ms: 0 });
    }
    await ctx.close();
  }
}
await browser.close();
server?.close();

// ---- Informe ----
const lines = ['# Recorrido de primer uso (automatizado)', '', `Compilación probada: ${BASE}`, '', '| Escenario | Tarea | ¿Completó? | Clics | Caracteres | Pantallas | Desplazamientos | Botón bloqueado sin motivo | Tiempo de máquina |', '|---|---|---|---|---|---|---|---|---|'];
for (const r of results) lines.push(`| ${r.escenario} | ${r.name} | ${r.ok ? 'sí' : '**NO**'} | ${r.clicks} | ${r.chars} | ${r.screens} | ${r.scrolls} | ${r.blockedNoReason} | ${(r.ms / 1000).toFixed(1)} s |`);
lines.push('', '## Observaciones', '');
for (const r of results) if (r.notes.length) lines.push(`**${r.escenario} · ${r.name}**`, ...r.notes.map((n) => `- ${n}`), '');
const report = lines.join('\n');
console.log(report);
if (OUT) writeFileSync(OUT, report + '\n');
process.exit(results.every((r) => r.ok) ? 0 : 1);
