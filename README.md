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

## Reglas para escribir funciones SQL

Toda función `security definer` **se salta RLS**: si no repite la regla de acceso, la regla no existe. Una función nueva debe (1) comprobar sesión, rol operativo y organización, (2) ser ejecutable sólo por `authenticated` y (3) llevar su prueba negativa en `supabase/tests/rls_negative.sql`.

## Pruebas de seguridad

```bash
npm run test:rls
```

Corren 122 pruebas negativas contra el proyecto enlazado, **dentro de una transacción que siempre se revierte** (crean su propio escenario: dos organizaciones, usuarios de cada rol y un usuario sin rol). Deben pasar completas antes de cerrar un ciclo. Demuestran que lo prohibido está prohibido: aislamiento entre organizaciones, `viewer` sin datos identificables, ausencia de `DELETE`, `audit_event` append-only, bitácora inmutable, estatus que no se sobrescribe, y funciones de escritura cerradas a `anon`, sin rol y a otras organizaciones.

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
  components/             pantallas y modales (NewCaseModal, CaseDetailView, OperationsDashboard, IndicatorsView…)
  lib/
    data.ts               lecturas bajo RLS y envoltorios de las funciones de la base
    session.tsx           login, rol y cierre por inactividad
    environment.tsx       entorno demo/producción declarado por la base
    catalog.tsx           áreas y catálogos de estatus
  locales/es.json         todas las cadenas visibles (Regla Dura 9)
supabase/
  migrations/             esquema versionado
  seed.sql                semilla de demo (determinista)
  demo/reset_demo.sql     vaciado para el reinicio
  tests/rls_negative.sql  pruebas negativas
scripts/                  demo:reset y test:rls
```

## Estado

El estado del producto frente al MVP, al backlog y a los controles de privacidad está en `30_entrega/reporte-ciclo-2026-10-07.md` (memoria documental). Las decisiones, en `40_bitacora/decisiones.md`.
