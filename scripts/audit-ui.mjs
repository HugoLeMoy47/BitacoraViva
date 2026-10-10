// Auditor de interfaz repetible: recorre cada pantalla de cada rol en 5 tamaños de pantalla y
// verifica los criterios del plan de revisión UX/UI (30_entrega/plan-ciclo-revision-ux-ui.md §5):
// desbordes, texto menor de 12 px, áreas táctiles, nombres accesibles, etiquetas de formulario,
// claves de traducción sin resolver, jerarquía de encabezados, contraste medido, espacio que
// ocupa el encabezado en celular, foco visible y comportamiento del modal.
//
//   npm run build && npm run audit:ui
//
// Usa el Edge o Chrome instalados (playwright-core no descarga navegadores) y las cuentas de
// demostración, y SÓLO LEE: no captura ni modifica datos. Sale con código 1 si algo falla.

import { chromium } from 'playwright-core';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const PORT = 4179;
const BASE = process.env.AUDIT_URL || `http://localhost:${PORT}`;

const VIEWPORTS = [
  { name: '360', width: 360, height: 740, touch: true },
  { name: '390', width: 390, height: 844, touch: true },
  { name: '768', width: 768, height: 1024, touch: true },
  { name: '1024', width: 1024, height: 768, touch: false },
  { name: '1440', width: 1440, height: 900, touch: false },
];

const ROLES = [
  { key: 'director', button: 'Dirección', routes: ['operacion', 'expedientes', 'expedientes/ASF-2026-0001', 'tareas', 'tareas/reportes', 'tareas/rutinas', 'tareas/notas', 'tareas/catalogos', 'tareas/ajustes', 'indicadores', 'areas', 'auditoria', 'autoridad', 'configuracion', 'acerca'] },
  { key: 'caseworker', button: 'Trabajo Social / caso', routes: ['expedientes', 'expedientes/ASF-2026-0001', 'tareas', 'tareas/notas', 'indicadores', 'acerca'] },
  { key: 'intake', button: 'Oficial de ingreso', routes: ['expedientes', 'tareas', 'indicadores', 'acerca'] },
  { key: 'viewer', button: 'Observador / auditor', routes: ['indicadores', 'acerca'] },
  // Seguidor de tareas (E7): roles que sólo operan tareas y no reciben ni una fila del expediente
  { key: 'task_manager', button: 'Coordinación de tareas', routes: ['tareas', 'tareas/reportes', 'tareas/rutinas', 'tareas/notas', 'acerca'] },
  { key: 'volunteer', button: 'Voluntariado', routes: ['tareas', 'tareas/notas', 'acerca'] },
];

// ---- Comprobaciones que corren dentro de la página ----
const pageAudit = `(opts) => {
  const out = [];
  const add = (rule, detail) => out.push({ rule, detail: String(detail).slice(0, 90) });
  const vw = innerWidth;
  const visible = (e) => {
    if (e.closest('.sr-only, [hidden], [aria-hidden="true"]')) return false;
    const r = e.getBoundingClientRect(), cs = getComputedStyle(e);
    return r.width > 0 && r.height > 0 && cs.visibility !== 'hidden' && cs.display !== 'none';
  };

  // 1. Desborde horizontal de la página
  const de = document.documentElement;
  if (de.scrollWidth > vw + 1) add('overflow-x', 'la página desborda ' + (de.scrollWidth - vw) + ' px');

  // 2. Texto menor de 12 px
  const small = new Set();
  document.querySelectorAll('body *').forEach((e) => {
    if (!visible(e)) return;
    const hasText = [...e.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim());
    if (hasText && parseFloat(getComputedStyle(e).fontSize) < 12) small.add(e.tagName + ':' + e.textContent.trim().slice(0, 25));
  });
  small.forEach((s) => add('texto-menor-12px', s));

  // 3. Áreas táctiles
  const minSize = opts.touch ? 40 : 24;
  document.querySelectorAll('button, a[href], select, textarea, [role=tab], [role=menuitem], input:not([type=hidden]):not([type=checkbox]):not([type=radio])').forEach((e) => {
    if (!visible(e)) return;
    const r = e.getBoundingClientRect();
    const inline = e.tagName === 'A' && e.closest('p, li, td, span') && getComputedStyle(e).display === 'inline';
    if (inline) return;
    if (r.height < minSize || r.width < minSize) add('area-tactil', ((e.getAttribute('aria-label') || e.textContent || e.tagName).trim().slice(0, 28)) + ' ' + Math.round(r.width) + 'x' + Math.round(r.height));
  });

  // 4. Nombre accesible
  const nameOf = (e) => {
    const aria = e.getAttribute('aria-label'); if (aria && aria.trim()) return aria.trim();
    const lb = e.getAttribute('aria-labelledby'); if (lb) { const t = lb.split(' ').map((id) => document.getElementById(id)?.textContent || '').join(' ').trim(); if (t) return t; }
    if (e.labels && e.labels.length) { const t = [...e.labels].map((l) => l.textContent).join(' ').trim(); if (t) return t; }
    const txt = (e.textContent || '').trim(); if (txt) return txt;
    const title = e.getAttribute('title'); if (title) return title;
    const img = e.querySelector('img[alt]'); if (img && img.alt.trim()) return img.alt.trim();
    return '';
  };
  document.querySelectorAll('button, a[href], input:not([type=hidden]), select, textarea, [role=tab], [role=menuitem]').forEach((e) => {
    if (!visible(e)) return;
    if (!nameOf(e)) add('sin-nombre-accesible', e.tagName + (e.type ? '[' + e.type + ']' : '') + ' ' + String(e.className).slice(0, 40));
  });

  // 5. Etiquetas de formulario huérfanas
  document.querySelectorAll('label').forEach((l) => {
    if (!visible(l) || !l.textContent.trim()) return;
    if (!l.control && !l.querySelector('input, select, textarea')) add('etiqueta-huerfana', l.textContent.trim().slice(0, 40));
  });

  // 6. Claves de traducción sin resolver y marcadores a la vista
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  let n;
  while ((n = walker.nextNode())) {
    const tx = n.textContent.trim();
    if (/^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)+$/.test(tx) && n.parentElement && visible(n.parentElement)) add('clave-i18n-sin-resolver', tx);
  }

  // 7. Encabezados: un h1 y sin saltos
  const hs = [...document.querySelectorAll('h1,h2,h3,h4,h5,h6')].filter(visible).map((h) => +h.tagName[1]);
  if (hs.filter((x) => x === 1).length !== 1) add('encabezados', 'h1 en pantalla: ' + hs.filter((x) => x === 1).length);
  for (let i = 1; i < hs.length; i++) if (hs[i] - hs[i - 1] > 1) { add('encabezados', 'salto h' + hs[i - 1] + ' → h' + hs[i]); break; }

  // 8. IDs duplicados
  const seen = new Set();
  document.querySelectorAll('[id]').forEach((e) => { if (seen.has(e.id)) add('id-duplicado', e.id); seen.add(e.id); });

  // 9. Espacio del encabezado en celular
  const main = document.querySelector('main');
  if (opts.mobile && main) {
    const pct = Math.round((main.getBoundingClientRect().top / innerHeight) * 100);
    if (pct > 25) add('cromo-superior', 'el contenido empieza al ' + pct + ' % de la pantalla');
  }

  // 10. Contraste medido (texto frente a su fondo efectivo)
  const parse = (c) => { const m = c.match(/rgba?\\(([^)]+)\\)/); if (!m) return null; const p = m[1].split(/[ ,/]+/).filter(Boolean).map(Number); return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 }; };
  const lum = ({ r, g, b }) => { const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }; return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b); };
  const over = (top, bottom) => ({ r: top.r * top.a + bottom.r * (1 - top.a), g: top.g * top.a + bottom.g * (1 - top.a), b: top.b * top.a + bottom.b * (1 - top.a), a: 1 });
  const bgOf = (el) => { let layers = []; for (let e = el; e; e = e.parentElement) { const cs = getComputedStyle(e); if (cs.backgroundImage !== 'none') return null; const c = parse(cs.backgroundColor); if (c && c.a > 0) { layers.push(c); if (c.a >= 1) break; } } let base = { r: 255, g: 255, b: 255, a: 1 }; for (let i = layers.length - 1; i >= 0; i--) base = over(layers[i], base); return base; };
  const bad = new Map();
  document.querySelectorAll('body *').forEach((e) => {
    if (!visible(e) || e.disabled || e.closest('[disabled], svg')) return;
    if (![...e.childNodes].some((x) => x.nodeType === 3 && x.textContent.trim())) return;
    const cs = getComputedStyle(e); if (parseFloat(cs.opacity) < 1) return;
    const fg = parse(cs.color); const bg = bgOf(e); if (!fg || !bg) return;
    const f = fg.a < 1 ? over(fg, bg) : fg;
    const l1 = lum(f), l2 = lum(bg); const ratio = (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
    const size = parseFloat(cs.fontSize), bold = parseInt(cs.fontWeight, 10) >= 700;
    const need = size >= 24 || (size >= 18.66 && bold) ? 3 : 4.5;
    if (ratio < need) { const k = cs.color + ' sobre ' + cs.backgroundColor; if (!bad.has(k)) bad.set(k, { ratio: ratio.toFixed(2), text: e.textContent.trim().slice(0, 28) }); }
  });
  bad.forEach((v, k) => add('contraste-bajo', v.ratio + ':1 «' + v.text + '» ' + k));

  return out;
}`;

// ---- Servidor de vista previa ----
async function waitFor(url, ms = 20000) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    try { if ((await fetch(url)).ok) return true; } catch { /* aún no */ }
    await new Promise((r) => setTimeout(r, 300));
  }
  return false;
}

let server = null;
if (!process.env.AUDIT_URL) {
  if (!existsSync(join(root, 'dist', 'index.html'))) {
    console.error('Falta compilar: ejecuta primero `npm run build`.');
    process.exit(1);
  }
  server = spawn(process.execPath, [join(root, 'node_modules', 'vite', 'bin', 'vite.js'), 'preview', '--port', String(PORT), '--strictPort'], { cwd: root, stdio: 'ignore' });
  if (!(await waitFor(BASE))) { console.error('No arrancó el servidor de vista previa.'); server.kill(); process.exit(1); }
}

// Recorrido completo sólo con teclado: login → alta de expediente → entrada de bitácora.
// Se llega a los botones finales (Abrir expediente / Asentar) pero no se pulsan: la auditoría no escribe datos.
const activeInfo = (page) => page.evaluate(() => {
  const e = document.activeElement;
  if (!e || e === document.body) return null;
  const label = e.labels && e.labels[0] ? e.labels[0].textContent : '';
  return {
    text: ((e.getAttribute('aria-label') || label || e.textContent || e.value || '') + '').replace(/\s+/g, ' ').trim(),
    tag: e.tagName, type: e.type || '', role: e.getAttribute('role') || '', value: e.value || '', name: e.name || '',
    checked: !!e.checked, inMain: !!e.closest('main'), outside: !!document.querySelector('[role=dialog]') && !e.closest('[role=dialog]'),
  };
});
async function tabTo(page, re, { max = 60, each } = {}) {
  for (let i = 0; i < max; i++) {
    await page.keyboard.press('Tab');
    const a = await activeInfo(page);
    if (process.env.AUDIT_DEBUG) console.log('  tab →', a && (a.tag + ':' + a.type + ':' + a.text.slice(0, 40)));
    if (a && re.test(a.text)) return a;
    if (a && each) await each(a);
  }
  return null;
}
async function keyboardJourney(page) {
  const out = [];
  const fail = (detail) => out.push({ rule: 'recorrido-teclado', detail });
  await page.goto(BASE + '/', { waitUntil: 'networkidle' });
  await page.evaluate(() => document.activeElement?.blur?.());
  if (!(await tabTo(page, /^Dirección$/))) return [{ rule: 'recorrido-teclado', detail: 'login: no se llega a la cuenta de Dirección con Tab' }];
  await page.keyboard.press('Enter');
  await page.waitForSelector('header', { timeout: 20000 });
  await page.waitForFunction(() => !document.body.innerText.includes('Cargando'), null, { timeout: 20000 });

  // Alta de expediente
  await page.evaluate(() => { location.hash = '#/expedientes'; document.activeElement?.blur?.(); });
  await page.waitForTimeout(900);
  if (!(await tabTo(page, /Levantar nuevo/i))) return [...out, { rule: 'recorrido-teclado', detail: 'alta: no se llega a «Levantar nuevo expediente» con Tab' }];
  await page.keyboard.press('Enter');
  await page.waitForSelector('[role=dialog]');
  const seen = new Set();
  const answer = async (a) => {
    if (a.type === 'checkbox' && !a.checked && /Entregué/.test(a.text)) await page.keyboard.press('Space');
    if (a.type === 'radio' && !seen.has(a.name)) {
      seen.add(a.name);
      for (let k = 0; k < 4; k++) {
        const cur = await activeInfo(page);
        if (cur && cur.value === 'yes' && cur.checked) break;
        if (cur && cur.value === 'yes') { await page.keyboard.press('Space'); break; }
        await page.keyboard.press('ArrowRight');
      }
    }
  };
  if (!(await tabTo(page, /Siguiente/, { each: answer }))) return [...out, { rule: 'recorrido-teclado', detail: 'alta paso 0: no se llega a «Siguiente» con Tab' }];
  await page.keyboard.press('Enter');
  await page.waitForTimeout(250);
  if (!(await tabTo(page, /Siguiente/))) fail('alta paso 1: no se llega a «Siguiente»');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(250);
  if (!(await tabTo(page, /Nombres/))) fail('alta paso 2: no se llega al campo Nombres');
  await page.keyboard.type('Prueba');
  if (!(await tabTo(page, /Primer apellido/i))) fail('alta paso 2: no se llega a Primer apellido');
  await page.keyboard.type('Auditoria');
  for (let k = 0; k < 2; k++) {
    if (!(await tabTo(page, /Siguiente/))) fail('alta paso ' + (k + 2) + ': no se llega a «Siguiente»');
    await page.keyboard.press('Enter');
    await page.waitForTimeout(250);
  }
  if (!(await tabTo(page, /Abrir expediente/i))) fail('alta paso 4: no se llega a «Abrir expediente» con Tab');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(300);
  if (await page.locator('[role=dialog]').count()) fail('alta: el modal no se cierra con Escape');

  // Entrada de bitácora en un expediente
  await page.evaluate(() => { location.hash = '#/expedientes/ASF-2026-0001'; document.activeElement?.blur?.(); });
  await page.waitForTimeout(1200);
  let found = false;
  for (let i = 0; i < 40 && !found; i++) {
    const a = await activeInfo(page);
    if (process.env.AUDIT_DEBUG) console.log('  bit →', a && (a.tag + ':' + a.role + ':' + a.text.slice(0, 40)));
    if (a && a.role === 'tab' && a.inMain) {
      for (let k = 0; k < 10; k++) {
        const c = await activeInfo(page);
        if (c && /Bitácora/i.test(c.text)) { found = true; break; }
        await page.keyboard.press('ArrowRight');
      }
      break;
    }
    await page.keyboard.press('Tab');
  }
  if (!found) return [...out, { rule: 'recorrido-teclado', detail: 'bitácora: no se llega a la pestaña Bitácora con teclado' }];
  await page.keyboard.press('Enter');
  await page.waitForTimeout(500);
  if (!(await tabTo(page, /Nueva entrada de bitácora/i))) return [...out, { rule: 'recorrido-teclado', detail: 'bitácora: no se llega a «Nueva entrada de bitácora» con Tab' }];
  await page.keyboard.press('Enter');
  await page.waitForSelector('[role=dialog]');
  const body = await tabTo(page, /Cuerpo de la intervención/i);
  if (!body) return [...out, { rule: 'recorrido-teclado', detail: 'bitácora: no se llega al cuerpo de la intervención' }];
  await page.keyboard.type('Entrada de prueba de auditoría de teclado.');
  if (!(await tabTo(page, /Revisar vista previa/i))) return [...out, { rule: 'recorrido-teclado', detail: 'bitácora: no se llega a «Revisar vista previa»' }];
  await page.keyboard.press('Enter');
  await page.waitForTimeout(300);
  if (!(await tabTo(page, /Asentar definitivamente/i))) fail('bitácora: no se llega a «Asentar definitivamente» con Tab');
  await page.keyboard.press('Escape');
  await page.waitForTimeout(300);
  if (await page.locator('[role=dialog]').count()) fail('bitácora: el modal no se cierra con Escape');
  return out;
}

// Abre un modal desde su botón, lo audita y comprueba lo esencial: role=dialog con nombre, el foco entra,
// Escape lo cierra y el foco regresa al botón que lo abrió. No escribe nada.
async function checkModalOpening(page, opener, label, audit) {
  const issues = [];
  await opener.focus();
  await opener.click();
  await page.waitForSelector('[role=dialog]');
  const items = await audit();
  if (!(await page.locator('[role=dialog][aria-modal=true][aria-labelledby]').count())) issues.push({ rule: 'modal', detail: label + ': sin role=dialog, aria-modal y nombre' });
  if (!(await page.evaluate(() => document.querySelector('[role=dialog]').contains(document.activeElement)))) issues.push({ rule: 'modal', detail: label + ': el foco no entra al modal' });
  await page.keyboard.press('Escape');
  await page.waitForTimeout(300);
  if (await page.locator('[role=dialog]').count()) issues.push({ rule: 'modal', detail: label + ': no se cierra con Escape' });
  if (!(await opener.evaluate((el) => el === document.activeElement))) issues.push({ rule: 'modal', detail: label + ': el foco no regresa al botón que lo abrió' });
  return { items, issues };
}

const findings = [];
const record = (role, vp, route, items) => items.forEach((f) => findings.push({ role, vp, route, ...f }));

let browser;
try {
  browser = await chromium.launch({ channel: 'msedge', headless: true }).catch(() => chromium.launch({ channel: 'chrome', headless: true }));
  let pages = 0;
  const sessions = new Map();

  for (const role of ROLES) {
    for (const vp of VIEWPORTS) {
      const ctx = await browser.newContext({
        viewport: { width: vp.width, height: vp.height },
        hasTouch: vp.touch,
        isMobile: vp.touch && vp.width < 768,
        deviceScaleFactor: 1,
        // Se reutiliza la sesión del rol entre tamaños de pantalla: iniciar sesión 30+ veces agota el límite de Supabase Auth
        ...(sessions.has(role.key) ? { storageState: sessions.get(role.key) } : {}),
      });
      const page = await ctx.newPage();
      await page.goto(BASE + '/', { waitUntil: 'networkidle' });
      const loginButton = page.getByRole('button', { name: role.button, exact: true });
      if (await loginButton.isVisible().catch(() => false)) await loginButton.click();
      await page.waitForSelector('header', { timeout: 20000 });
      if (!sessions.has(role.key)) sessions.set(role.key, await ctx.storageState());
      await page.waitForFunction(() => !document.body.innerText.includes('Cargando'), null, { timeout: 20000 });

      for (const route of role.routes) {
        await page.evaluate((r) => { location.hash = '#/' + r; }, route);
        await page.waitForTimeout(900);
        await page.waitForFunction(() => !document.body.innerText.includes('Cargando'), null, { timeout: 20000 })
          .catch(async (e) => { throw new Error(`«Cargando» no desaparece: rol ${role.key}, ${vp.name}, ruta ${route}. Texto: ${(await page.evaluate(() => document.body.innerText)).replace(/\s+/g, ' ').slice(0, 300)}`, { cause: e }); });
        const items = await page.evaluate(`(${pageAudit})(${JSON.stringify({ touch: vp.touch, mobile: vp.width < 768 })})`);
        record(role.key, vp.name, route, items);
        pages++;
      }

      const auditNow = () => page.evaluate(`(${pageAudit})(${JSON.stringify({ touch: vp.touch, mobile: vp.width < 768 })})`);

      // Secciones del expediente, alta paso a paso y Digest (sólo Dirección, escritorio y celular)
      if (role.key === 'director' && (vp.name === '360' || vp.name === '1024')) {
        await page.evaluate(() => { location.hash = '#/expedientes/ASF-2026-0001'; });
        await page.waitForTimeout(1200);
        const tabCount = await page.locator('main [role=tab]').count();
        for (let i = 0; i < tabCount; i++) {
          await page.locator('main [role=tab]').nth(i).click();
          await page.waitForTimeout(500);
          record(role.key, vp.name, 'expediente/sección ' + (i + 1), await auditNow());
        }

        // Tareas ligadas al caso (E7, BV-7.16): el formulario se abre y se cancela
        const caseTasksTab = page.getByRole('tablist', { name: 'Secciones del expediente' }).getByRole('tab', { name: 'Tareas', exact: true });
        if (await caseTasksTab.count()) {
          await caseTasksTab.click();
          await page.waitForTimeout(900);
          const linkedModal = await checkModalOpening(page, page.getByRole('button', { name: /Nueva tarea ligada/i }), 'nueva tarea ligada', auditNow);
          record(role.key, vp.name, 'expediente/tarea ligada formulario', linkedModal.items);
          record(role.key, vp.name, '(modal tarea ligada)', linkedModal.issues);
        }

        // Configuración de la organización: cada sección
        await page.evaluate(() => { location.hash = '#/configuracion'; });
        await page.waitForTimeout(1200);
        const cfgTabs = await page.locator('main [role=tab]').count();
        for (let i = 0; i < cfgTabs; i++) {
          await page.locator('main [role=tab]').nth(i).click();
          await page.waitForTimeout(500);
          record(role.key, vp.name, 'configuracion/sección ' + (i + 1), await auditNow());
        }

        await page.evaluate(() => { location.hash = '#/expedientes'; });
        await page.waitForTimeout(900);
        await page.getByRole('button', { name: /Levantar Nuevo/i }).click();
        await page.waitForSelector('[role=dialog]');
        // Los textos de consentimiento cargan de forma asíncrona: sin esta espera, marcar las decisiones antes
        // de que lleguen deja «Siguiente» deshabilitado y el recorrido falla de forma intermitente
        await page.waitForFunction(() => document.querySelectorAll('[role=dialog] input[type=radio]').length >= 2, null, { timeout: 15000 });
        await page.waitForTimeout(500);
        record(role.key, vp.name, 'alta/paso 0', await auditNow());
        await page.getByRole('checkbox', { name: /Entregué o leí/ }).check();
        const yes = page.locator('[role=dialog] input[type=radio][value=yes]');
        for (let i = 0; i < (await yes.count()); i++) await yes.nth(i).locator('xpath=ancestor::label').click();
        for (let step = 1; step <= 4; step++) {
          await page.getByRole('button', { name: /Siguiente/ }).click();
          await page.waitForTimeout(250);
          if (step === 2) { /* la ficha pide nombre y apellido para avanzar */ }
          if (step === 1) {
            record(role.key, vp.name, 'alta/paso 1', await auditNow());
            await page.getByRole('button', { name: /Siguiente/ }).click();
            await page.getByLabel(/Nombres/).fill('Prueba');
            await page.getByLabel(/Primer apellido/i).fill('Auditoria');
            record(role.key, vp.name, 'alta/paso 2', await auditNow());
            await page.getByRole('button', { name: /Siguiente/ }).click();
            await page.waitForTimeout(250);
            record(role.key, vp.name, 'alta/paso 3', await auditNow());
            await page.getByRole('button', { name: /Siguiente/ }).click();
            await page.waitForTimeout(250);
            record(role.key, vp.name, 'alta/paso 4', await auditNow());
            break;
          }
        }
        await page.keyboard.press('Escape');
        await page.waitForTimeout(300);

        const bell = page.locator('header button[aria-label*="Bandeja"]');
        if (await bell.count()) {
          await bell.click();
          await page.waitForSelector('[role=dialog]');
          record(role.key, vp.name, 'digest', await auditNow());
          await page.keyboard.press('Escape');
        }
      }

      // Seguidor de tareas: cada estado de la lista de celular y los modales de captura (coordinación de tareas).
      // Sólo lee: abre el formulario y la confirmación de archivo y los cancela con Escape.
      if (role.key === 'task_manager' && (vp.name === '360' || vp.name === '1024')) {
        await page.evaluate(() => { location.hash = '#/tareas'; });
        await page.waitForTimeout(900);
        if (vp.name === '360') {
          const states = page.locator('main [role=group] button[aria-pressed]');
          const n = await states.count();
          for (let i = 0; i < n; i++) {
            await states.nth(i).click();
            await page.waitForTimeout(300);
            record(role.key, vp.name, 'tareas/estado ' + (i + 1), await auditNow());
          }
        }
        const modalIssues = [];
        const checkModal = async (opener, label) => {
          await opener.focus();
          await opener.click();
          await page.waitForSelector('[role=dialog]');
          record(role.key, vp.name, 'tareas/' + label, await auditNow());
          if (!(await page.locator('[role=dialog][aria-modal=true][aria-labelledby]').count())) modalIssues.push({ rule: 'modal', detail: label + ': sin role=dialog, aria-modal y nombre' });
          if (!(await page.evaluate(() => document.querySelector('[role=dialog]').contains(document.activeElement)))) modalIssues.push({ rule: 'modal', detail: label + ': el foco no entra al modal' });
          await page.keyboard.press('Escape');
          await page.waitForTimeout(300);
          if (await page.locator('[role=dialog]').count()) modalIssues.push({ rule: 'modal', detail: label + ': no se cierra con Escape' });
          if (!(await opener.evaluate((el) => el === document.activeElement))) modalIssues.push({ rule: 'modal', detail: label + ': el foco no regresa al botón que lo abrió' });
        };
        await checkModal(page.getByRole('button', { name: /Nueva tarea/i }), 'formulario');
        const archive = page.getByRole('button', { name: /^Archivar$/ }).first();
        if (await archive.count()) await checkModal(archive, 'archivar');
        record(role.key, vp.name, '(modal tareas)', modalIssues);

        // Reportes: cada vista (con el panel de filtros abierto en celular, donde se pliega)
        await page.evaluate(() => { location.hash = '#/tareas/reportes'; });
        await page.waitForTimeout(900);
        const filtersToggle = page.getByRole('button', { name: /^Filtros/ });
        if (await filtersToggle.count()) { await filtersToggle.click(); await page.waitForTimeout(250); }
        const reportTabs = page.locator('[role=tablist][aria-label="Vistas del reporte"] [role=tab]');
        const reportTabCount = await reportTabs.count();
        for (let i = 0; i < reportTabCount; i++) {
          await reportTabs.nth(i).click();
          await page.waitForTimeout(500);
          record(role.key, vp.name, 'tareas/reporte vista ' + (i + 1), await auditNow());
        }

        // Rutinas: el formulario de alta se abre y se cancela
        await page.evaluate(() => { location.hash = '#/tareas/rutinas'; });
        await page.waitForTimeout(900);
        const routineModal = await checkModalOpening(page, page.getByRole('button', { name: /Nueva rutina/i }), 'rutina/formulario', auditNow);
        record(role.key, vp.name, 'tareas/rutina formulario', routineModal.items);
        record(role.key, vp.name, '(modal rutina)', routineModal.issues);
      }

      // Voluntariado: pool de tareas abiertas e inicio de turno (sólo lee: abre y cancela)
      if (role.key === 'volunteer' && (vp.name === '360' || vp.name === '1024')) {
        await page.evaluate(() => { location.hash = '#/tareas'; });
        await page.waitForTimeout(1200);
        const poolToggle = page.getByRole('button', { name: /Tareas disponibles/ });
        if (await poolToggle.count()) {
          await poolToggle.click();
          await page.waitForTimeout(500);
          record(role.key, vp.name, 'tareas/pool abierto', await auditNow());
        }
        const startModal = await checkModalOpening(page, page.getByRole('button', { name: /Iniciar mi turno/i }), 'iniciar turno', auditNow);
        record(role.key, vp.name, 'tareas/iniciar turno', startModal.items);
        record(role.key, vp.name, '(modal iniciar turno)', startModal.issues);

        // Evidencia fotográfica: el modal de fotos de la primera tarea que lo ofrece (sólo abre y cancela)
        const photoOpener = page.getByRole('button', { name: /^(Agregar foto|Fotos|Tomar foto y concluir)$/ }).first();
        if (await photoOpener.count()) {
          const photoModal = await checkModalOpening(page, photoOpener, 'fotos de evidencia', auditNow);
          record(role.key, vp.name, 'tareas/fotos de evidencia', photoModal.items);
          record(role.key, vp.name, '(modal fotos)', photoModal.issues);
        } else {
          console.log("aviso: ninguna tarea ofrece el modal de fotos en "+vp.name);
        }
      }

      // Foco visible por teclado (una pantalla por combinación)
      await page.evaluate(() => { location.hash = '#/' + (document.querySelector('[role=tab]') ? 'indicadores' : 'indicadores'); });
      await page.waitForTimeout(600);
      await page.evaluate(() => { document.activeElement?.blur?.(); window.scrollTo(0, 0); });
      const focusIssues = [];
      for (let i = 0; i < 14; i++) {
        await page.keyboard.press('Tab');
        const r = await page.evaluate(() => {
          const e = document.activeElement; if (!e || e === document.body) return null;
          const cs = getComputedStyle(e);
          const outline = cs.outlineStyle !== 'none' && parseFloat(cs.outlineWidth) > 0;
          const ring = cs.boxShadow && cs.boxShadow !== 'none';
          return { ok: outline || ring, name: ((e.getAttribute('aria-label') || e.textContent || e.tagName) + '').trim().slice(0, 28) };
        });
        if (r && !r.ok) focusIssues.push({ rule: 'foco-no-visible', detail: r.name });
      }
      record(role.key, vp.name, '(teclado)', focusIssues);

      // Modal accesible (director, escritorio)
      if (role.key === 'director' && vp.name === '1024') {
        await page.evaluate(() => { location.hash = '#/expedientes'; });
        await page.waitForTimeout(900);
        const opener = page.getByRole('button', { name: /Levantar Nuevo/i });
        await opener.focus();
        await opener.click();
        const issues = [];
        if (!(await page.locator('[role=dialog][aria-modal=true]').count())) issues.push({ rule: 'modal', detail: 'no tiene role=dialog y aria-modal' });
        else {
          if (!(await page.locator('[role=dialog][aria-labelledby]').count())) issues.push({ rule: 'modal', detail: 'sin nombre accesible' });
          if (!(await page.evaluate(() => document.querySelector('[role=dialog]').contains(document.activeElement)))) issues.push({ rule: 'modal', detail: 'el foco no entra al modal' });
          await page.keyboard.press('Escape');
          await page.waitForTimeout(300);
          if (await page.locator('[role=dialog]').count()) issues.push({ rule: 'modal', detail: 'no se cierra con Escape' });
          if (!(await page.evaluate(() => document.activeElement?.textContent?.includes('Levantar')))) issues.push({ rule: 'modal', detail: 'el foco no regresa al botón que lo abrió' });
        }
        record(role.key, vp.name, '(modal)', issues);
      }
      await ctx.close();
    }
  }

  // ---- Recorrido por teclado ----
  {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
    const page = await ctx.newPage();
    record('director', '1280', '(recorrido por teclado)', await keyboardJourney(page).catch((e) => [{ rule: 'recorrido-teclado', detail: 'error: ' + String(e.message).slice(0, 120) }]));
    await ctx.close();
    pages++;
  }

  // ---- Recorrido por teclado del voluntariado: del acceso a «Comenzar tarea», sin pulsarla ----
  {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
    const page = await ctx.newPage();
    const out = [];
    try {
      await page.goto(BASE + '/', { waitUntil: 'networkidle' });
      await page.evaluate(() => document.activeElement?.blur?.());
      if (!(await tabTo(page, /^Voluntariado$/))) out.push({ rule: 'recorrido-teclado', detail: 'login: no se llega a la cuenta de Voluntariado con Tab' });
      else {
        await page.keyboard.press('Enter');
        await page.waitForSelector('header', { timeout: 20000 });
        await page.waitForFunction(() => !document.body.innerText.includes('Cargando'), null, { timeout: 20000 });
        await page.evaluate(() => { location.hash = '#/tareas'; document.activeElement?.blur?.(); });
        await page.waitForTimeout(1200);
        if (!(await tabTo(page, /Comenzar tarea|Concluir tarea/, { max: 80 }))) out.push({ rule: 'recorrido-teclado', detail: 'tareas: no se llega al botón de avanzar una tarea con Tab' });
      }
    } catch (e) {
      out.push({ rule: 'recorrido-teclado', detail: 'error: ' + String(e.message).slice(0, 120) });
    }
    record('volunteer', '1280', '(recorrido por teclado)', out);
    await ctx.close();
    pages++;
  }

  // ---- Informe ----
  const groups = new Map();
  for (const f of findings) {
    const key = `${f.rule} | ${f.detail}`;
    if (!groups.has(key)) groups.set(key, { rule: f.rule, detail: f.detail, where: new Set() });
    groups.get(key).where.add(`${f.role}@${f.vp}:${f.route}`);
  }
  console.log(`Auditoría de interfaz: ${pages} pantallas × tamaños × roles revisadas.`);
  if (groups.size === 0) {
    console.log('✓ Sin hallazgos.');
  } else {
    const byRule = new Map();
    for (const g of groups.values()) byRule.set(g.rule, (byRule.get(g.rule) || 0) + 1);
    console.log(`\n${groups.size} hallazgos distintos:`);
    for (const [rule, n] of byRule) console.log(`  ${rule}: ${n}`);
    console.log('');
    for (const g of groups.values()) {
      const w = [...g.where];
      console.log(`✗ ${g.rule} — ${g.detail}\n    en ${w.length} lugares, p. ej. ${w.slice(0, 3).join(', ')}`);
    }
  }
  process.exitCode = groups.size > 0 ? 1 : 0;
} finally {
  await browser?.close();
  server?.kill();
}
