# Bitácora Viva

Plataforma de gestión de casos de atención humanitaria para el tercer sector. Este repositorio es **el código**; la fuente de verdad del producto (Ethos, glosario, modelo, backlog, deudas, bitácora de decisiones) está en la memoria documental:

- En equipo nekosurf: `D:\hugol\OneDrive\07_Freejolitos\50_Productos\BitacoraViva`
- En equipo nekoblue: `C:\Users\hugol\OneDrive\07_Freejolitos\50_Productos\BitacoraViva`

Antes de cambiar nada, lee `CLAUDE.md` de este repositorio y `30_entrega/handoff-agente-desarrollo.md` (las diez reglas duras). Esta página sólo explica **cómo correrlo y operarlo**; no repite el producto.

> **Entorno actual: DEMO.** Todos los datos son ficticios. No se debe capturar información de personas reales hasta cerrar la lista de bloqueo (`20_arquitectura/privacidad-y-cumplimiento.md` §4).

## Stack

React 19 · TypeScript · Vite · Tailwind · Supabase (Postgres + Auth, con RLS) · despliegue del frontend en Cloudflare Workers (activos estáticos).

## Puesta en marcha

```bash
npm ci
npm run dev        # servidor local
npm run build      # tsc -b && vite build
npm run check:i18n # toda clave usada existe en src/locales/es.json (Regla Dura 9)
npm run audit:ui   # auditor de interfaz (ver «Auditoría de interfaz»)
```

El frontend lee `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY` **en tiempo de compilación**. `.env.production` y `wrangler.jsonc` ya apuntan al proyecto Supabase de la demo (la clave `anon` es pública por diseño). Para desarrollar contra esa base, crea `.env.local` con los mismos dos valores. **Nunca** pongas la clave `service_role` en el navegador ni en el repositorio (Regla Dura 2).

## Base de datos

Todo cambio de esquema es una **migración versionada** en `supabase/migrations/` (Regla Dura 10): nada se cambia desde la consola de Supabase.

```bash
npx supabase login
npx supabase link --project-ref <ref>   # una sola vez por máquina
npx supabase db push                     # aplica las migraciones pendientes
```

- Proyecto de la demo: `lbmytnjvpkjepsaiqymd` (`us-west-2`, Postgres 17).
- `supabase/seed.sql` es **exclusivo de demo**: siembra 60 expedientes sintéticos, 4 cuentas demo y marca el entorno como `demo` (`app_config`). Nunca se ejecuta en producción.
- Una base sin la fila de entorno se considera `production`: la interfaz no muestra el aviso de demo ni ofrece cuentas de acceso rápido.

## Auditoría de interfaz

```bash
npm run build && npm run audit:ui
```

Recorre la aplicación compilada con `playwright-core` y el Edge o Chrome del sistema (no descarga navegadores; la dependencia es solo de desarrollo). Prueba los 6 roles (los 4 de casos más coordinación de tareas y voluntariado) en 5 anchos (360, 390, 768, 1024, 1440 px): desbordamiento horizontal, contenido que empieza en más del 25 % de la pantalla, texto menor de 12 px, contraste AA medido, controles sin nombre accesible, etiquetas huérfanas, áreas táctiles menores de 44 px, y los modales (`role="dialog"`, Escape, foco). Recorre además, solo con teclado (sin ratón), login → alta de expediente → entrada de bitácora hasta sus botones finales (no los pulsa: la auditoría no escribe datos; `AUDIT_DEBUG=1` imprime el orden de Tab). También recorre las secciones del expediente y los pasos del alta. Debe terminar en «✓ Sin hallazgos» antes de cerrar un ciclo de interfaz. Si cambias un texto de `es.json`, revisa que el auditor no lo busque con las mayúsculas anteriores.

## Reglas para escribir funciones SQL

Toda función `security definer` **se salta RLS**: si no repite la regla de acceso, la regla no existe. Una función nueva debe (1) comprobar sesión, rol operativo y organización, (2) ser ejecutable sólo por `authenticated` y (3) llevar su prueba negativa en `supabase/tests/rls_negative.sql`.

## Pruebas unitarias

```bash
npm run test:unit
```

Vitest sobre la lógica **pura** del Seguidor de tareas (reportes, enlace compartible, CSV, flujo de estados, claves de catálogo): 56 pruebas junto a cada módulo (`src/lib/*.test.ts`). Es lo que se puede equivocar en silencio —promedios, cortes de semana, orden, escape de fórmulas— y por eso vive aislado de React y de Supabase para poder revisarlo sin navegador ni base.

## Pruebas de seguridad

```bash
npm run test:rls
```

Corren 582 pruebas negativas (215 del núcleo, 293 del Seguidor de tareas E7 y 74 de cuentas desactivadas) contra el proyecto enlazado, **dentro de una transacción que siempre se revierte** (crean su propio escenario: dos organizaciones, usuarios de cada rol y un usuario sin rol). Deben pasar completas antes de cerrar un ciclo. Demuestran que lo prohibido está prohibido: aislamiento entre organizaciones, `viewer` sin datos identificables, ausencia de `DELETE`, `audit_event` append-only, bitácora inmutable, estatus que no se sobrescribe, y funciones de escritura cerradas a `anon`, sin rol y a otras organizaciones.

### Probar una migración nueva antes de empujarla

```bash
npm run test:rls -- --include=20261009
npm run demo:reset -- --confirm <project-ref> --dry-run --include=20261009
```

`--include=<prefijo>` ejecuta las migraciones cuyo nombre empieza con ese prefijo **dentro de la misma transacción de prueba**, antes del escenario, y se revierten con ella: la migración se prueba contra el motor real sin pasar por `supabase db push` ni dejar rastro. Mientras una migración esté sin empujar, `test:rls` a secas falla en el escenario si las pruebas ya dependen de ella (las tablas nuevas no existen en la base); con `--include` pasa. Una vez empujada, el prefijo ya no hace falta.

## Reiniciar la demo

```bash
npm run demo:reset -- --confirm <project-ref> --dry-run   # prueba completa y revierte
npm run demo:reset -- --confirm <project-ref>             # reinicia de verdad
```

Vacía los datos de negocio, borra las cuentas demo y vuelve a sembrar. Se niega si la base no está marcada `demo`. **Borra también la auditoría de la demo.** Es un comando de operador y no una función de la aplicación a propósito: una función destructiva alcanzable desde un rol de aplicación contradiría las Reglas Duras 3 y 4.

## Despliegue

El despliegue del frontend en Cloudflare Workers es **manual** hoy: publicar en `main` no actualiza el sitio por sí solo. Al cerrar un ciclo, verifica que el paquete publicado corresponde al último commit (riesgo `R-13` en la documentación).

## Estructura

```
src/
  App.tsx                 sesión, carga de datos y navegación
  components/             pantallas y modales (NewCaseModal, CaseDetailView, OperationsDashboard, IndicatorsView, ConfigurationView…)
  lib/
    data.ts               lecturas bajo RLS y envoltorios de las funciones de la base
    session.tsx           login, rol y cierre por inactividad
    environment.tsx       entorno demo/producción declarado por la base
    catalog.tsx           áreas y catálogos de estatus
    navigation.ts         pantallas permitidas por rol (única fuente) · router.ts: ruta en el hash
    format.ts             fechas con Intl · errors.ts: mensajes de error comprensibles · toast.tsx: avisos
  locales/es.json         todas las cadenas visibles (Regla Dura 9)
supabase/
  migrations/             esquema versionado
  seed.sql                semilla de demo (determinista)
  demo/reset_demo.sql     vaciado para el reinicio
  tests/rls_negative.sql  pruebas negativas
scripts/                  demo:reset, test:rls, check:i18n y audit:ui
```

## Estado

El estado del producto frente al MVP, al backlog y a los controles de privacidad está en `30_entrega/reporte-ciclo-2026-10-07.md` (memoria documental). Las decisiones, en `40_bitacora/decisiones.md`.
