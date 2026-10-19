// Exporta la arquitectura a docs/img/arquitectura.png (la que muestra el README). Uso: node docs/diagramas/exportar-png.mjs
import { chromium } from 'playwright-core'
const b = await chromium.launch({ channel: 'msedge', headless: true }).catch(() => chromium.launch({ channel: 'chrome', headless: true }))
const p = await b.newPage({ viewport: { width: 1500, height: 900 }, deviceScaleFactor: 1.5 })
await p.goto(new URL('./arquitectura.html', import.meta.url).href)
await p.waitForTimeout(1500)
const el = await p.$('.diagram-container > svg')
console.log(!!el)
await (el ?? p).screenshot({ path: 'docs/img/arquitectura.png' })
await b.close()
