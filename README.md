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

## Seguidor de tareas (E7)

Integrado desde *CAFEMIN Task Tracker* (se absorbió el código, no hay fork) y alineado a las reglas duras. Rutas con `#/tareas`, `#/tareas/reportes`, `/rutinas`, `/notas`, `/catalogos` y `/ajustes`; los reportes llevan en la URL su estado (filtros por identificador; **la búsqueda por texto nunca viaja en el enlace**).

- **Roles:** `task_manager` y `volunteer` conviven con los cuatro de casos (los roles se acumulan, `ADR-0007`). Sin rol de casos no se lee ni una fila de `person` ni de `case`.
- **Baja lógica:** ninguna tabla de tareas admite `DELETE`; archivar es definitivo. Toda escritura deja `audit_event`.
- **Evidencia fotográfica:** bucket **privado** `task-evidence`; se guarda la ruta, nunca una URL. El navegador reduce la foto (1600 px) y le quita la ubicación; ver una foto pasa por `fn_task_evidence_access` (deja evento) y firma una URL de 60 s.
- **Pool, rutinas, notas de turno y ajustes** (`task_setting`, solo dirección). Lo tomado y no empezado vuelve al pool al abrirlo; no depende de `pg_cron`.
- **Tareas ligadas a un caso:** solo viaja el folio; el nombre sale de un catálogo neutro y no hay texto libre. Las crea quien opera expedientes, desde la pestaña *Tareas* del expediente (`fn_create_case_task`, `fn_set_task_case`).
- **Códigos de error:** SQLSTATE `TK001` a `TK028`, traducidos en `errors.task.*` de `src/locales/es.json`.
- Lo que hace cada rol, en lenguaje de producto: `10_producto/estado_funciones_roles.md` (documentación fuera del repositorio).

## Auditoría de interfaz

```bash
npm run build && npm run audit:ui
```

Recorre la aplicación compilada con `playwright-core` y el Edge o Chrome del sistema (no descarga navegadores; la dependencia es solo de desarrollo). Prueba los 6 roles (los 4 de casos más coordinación de tareas y voluntariado) en 5 anchos (360, 390, 768, 1024, 1440 px): desbordamiento horizontal, contenido que empieza en más del 25 % de la pantalla, texto menor de 12 px, contraste AA medido, controles sin nombre accesible, etiquetas huérfanas, áreas táctiles menores de 44 px, y los modales (`role="dialog"`, Escape, foco). Recorre además, solo con teclado (sin ratón), login → alta de expediente → entrada de bitácora hasta sus botones finales (no los pulsa: la auditoría no escribe datos; `AUDIT_DEBUG=1` imprime el orden de Tab). También recorre las secciones del expediente y los pasos del alta. Debe terminar en «✓ Sin hallazgos» antes de cerrar un ciclo de interfaz. Si cambias un texto de `es.json`, revisa que el auditor no lo busque con las mayúsculas anteriores.

## Reglas para escribir funciones SQL

Toda función `security definer` **se salta RLS**: si no repite la regla de acceso, la regla no existe. Una función nueva debe (1) comprobar sesión, rol operativo y organización (`fn_assert_same_org`), (2) ser ejecutable sólo por `authenticated`, (3) fijar su `search_path` y (4) llevar su prueba negativa en `supabase/tests/rls_negative.sql`. Si escribe en `audit_event`, **nunca guarda valores personales**: sólo nombres de campos (`fn_audit_trigger_fields`) o identificadores.

## Cabeceras de seguridad

`public/_headers` (CSP, `frame-ancestors`, `Referrer-Policy`, `X-Content-Type-Options`…) lo aplica Cloudflare Workers al servir `dist`. El origen de Supabase está escrito en `connect-src` e `img-src`: **si cambia el proyecto (p. ej. producción), cámbialo ahí**.

## Pruebas unitarias

```bash
npm run test:unit
```

Vitest sobre la lógica **pura** del Seguidor de tareas (reportes, enlace compartible, CSV, flujo de estados, claves de catálogo): 62 pruebas junto a cada módulo (`src/lib/*.test.ts`): reportes, enlace compartible, CSV, flujo de estados, claves de catálogo y reglas de evidencia fotográfica. Es lo que se puede equivocar en silencio —promedios, cortes de semana, orden, escape de fórmulas, tamaño y tipo de foto— y por eso vive aislado de React y de Supabase para poder revisarlo sin navegador ni base.

## Pruebas de seguridad

```bash
npm run test:rls
```

Corren 752 pruebas negativas (215 del núcleo, 363 del Seguidor de tareas E7, 74 de cuentas desactivadas y 100 del endurecimiento del 11 oct 2026: organización en ARCO, auditoría sin datos personales, compartimentación de la bitácora, estatus, escritura del núcleo solo por funciones, pseudonimización de terceros e indicadores sin re-identificación por resta) contra el proyecto enlazado, **dentro de una transacción que siempre se revierte** (crean su propio escenario: dos organizaciones, usuarios de cada rol y un usuario sin rol). Deben pasar completas antes de cerrar un ciclo. Demuestran que lo prohibido está prohibido: aislamiento entre organizaciones, `viewer` sin datos identificables, ausencia de `DELETE`, `audit_event` append-only, bitácora inmutable, estatus que no se sobrescribe, y funciones de escritura cerradas a `anon`, sin rol y a otras organizaciones.

### Probar una migración nueva antes de empujarla

```bash
npm run test:rls -- --include=20261009000007
npm run demo:reset -- --confirm <project-ref> --dry-run --include=20261009000007
```

`--include=<prefijo>` ejecuta las migraciones cuyo nombre empieza con ese prefijo **dentro de la misma transacción de prueba**, antes del escenario, y se revierten con ella: la migración se prueba contra el motor real sin pasar por `supabase db push` ni dejar rastro. Mientras una migración esté sin empujar, `test:rls` a secas falla en el escenario si las pruebas ya dependen de ella (las tablas nuevas no existen en la base); con `--include` pasa. Una vez empujada, el prefijo ya no hace falta. **Usa el nombre completo de la migración nueva**, no el prefijo del día: las ya empujadas chocan al repetirse dentro de la transacción (por ejemplo, al borrar una restricción de la que otras dependen).

## Reiniciar la demo

```bash
npm run demo:reset -- --confirm <project-ref> --dry-run   # prueba completa y revierte
npm run demo:reset -- --confirm <project-ref>             # reinicia de verdad
```

Vacía los datos de negocio, borra las cuentas demo y vuelve a sembrar. Se niega si la base no está marcada `demo`. **Borra también la auditoría de la demo.** Es un comando de operador y no una función de la aplicación a propósito: una función destructiva alcanzable desde un rol de aplicación contradiría las Reglas Duras 3 y 4.

## Integración continua

GitHub Actions (`.github/workflows/ci.yml`) corre en cada push a `main` y en cada pull request, con dos trabajos:

- **Verificación estática:** `scan:secrets` (sin `service_role` ni llaves en el repositorio, Regla Dura 2), `build` (tipos y compilación), `check:i18n` (Regla Dura 9) y `test:unit`.
- **Pruebas de seguridad (base local):** levanta Supabase **efímero** (`supabase start`: Postgres 17 con todas las migraciones desde cero y la semilla) y corre `npm run test:rls -- --local`. No toca la demo compartida ni usa tokens de ella; si una migración depende de algo que sólo existe en la demo, aquí falla.

La herramienta de Supabase está fijada en `package.json` (`supabase@2.120.0`) para que CI y equipo usen la misma versión. Localmente: `npm run scan:secrets` y, con Docker encendido, `npx supabase start` + `npm run test:rls -- --local`.

**`main` está protegida** (regla de rama de GitHub, activa desde el 11 oct 2026): exige que pasen los checks **Verificación estática** y **Pruebas de seguridad (base local)**. Un `git push` directo a `main` se rechaza. El CI **no despliega**: publicar el sitio y empujar migraciones siguen siendo pasos deliberados (R-13).

### Flujo de trabajo con ramas

1. Crear una rama desde `main` actualizada: `git checkout main && git pull && git checkout -b <tipo>/<tema>` (por ejemplo `feat/…`, `fix/…`, `docs/…`).
2. Trabajar, probar en local (`npm run build`, `npm run check:i18n`, `npm run test:unit`, y `npm run test:rls -- --include=<migración completa>` si hay migración) y subir: `git push -u origin <rama>`.
3. Abrir el pull request (GitHub muestra el enlace al empujar la rama). El CI corre sobre el pull request.
4. Con los dos checks en verde, fusionar. Elegir **«Squash and merge»** deja un commit por cambio en `main`.
5. `git checkout main && git pull` y borrar la rama.

**Migraciones:** el CI las prueba desde cero, pero **`supabase db push` sigue siendo un paso aparte, con confirmación del Product Owner**: fusionar a `main` no toca la base de la demo. Orden recomendado: probar la migración con `--include`, fusionar el pull request con el CI en verde y entonces `db push`.

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
