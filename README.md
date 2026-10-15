# Bitácora Viva

Plataforma de gestión de casos de atención humanitaria para el tercer sector (albergues, casas del migrante), multi-organización desde el diseño. Este repositorio es **el código**. La fuente de verdad del producto (Ethos, glosario, modelo de datos, backlog, deudas técnicas, decisiones) está en la **memoria documental**:

- En equipo nekosurf: `D:\hugol\OneDrive\07_Freejolitos\50_Productos\BitacoraViva`
- En equipo nekoblue: `C:\Users\hugol\OneDrive\07_Freejolitos\50_Productos\BitacoraViva`

> **Entorno actual: DEMO.** Todos los datos son ficticios. No se debe capturar información de personas reales hasta cerrar la lista de bloqueo (`20_arquitectura/privacidad-y-cumplimiento.md` §4).

## Por dónde empezar

1. **[`docs/arquitectura-en-una-pagina.md`](docs/arquitectura-en-una-pagina.md)** — qué es el producto, cómo se arman sus piezas y dónde está cada cosa. Diez minutos.
2. **`CLAUDE.md`** de este repositorio y `30_entrega/handoff-agente-desarrollo.md` (memoria documental) — las **diez reglas duras**. Si el repositorio y la memoria documental divergen, manda la memoria documental.
3. **[`supabase/README.md`](supabase/README.md)** — la base de datos: cómo se prueba y un índice de qué introdujo cada migración.

Esta página solo explica **cómo correrlo y operarlo**; no repite el producto.

## Stack

React 19 · TypeScript · Vite · Tailwind · Supabase (Postgres + Auth + Storage, con RLS) · frontend servido por un Worker de Cloudflare (archivos estáticos).

## Puesta en marcha

```bash
npm ci
npm run dev          # servidor local
npm run build        # tsc -b && vite build
npm run test:unit    # lógica pura (Vitest)
npm run test:rls     # pruebas de seguridad de la base (ver «Pruebas»)
```

El frontend lee `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY` **en tiempo de compilación**. `.env.production` y `wrangler.jsonc` ya apuntan al proyecto Supabase de la demo (la clave `anon` es pública por diseño). Para desarrollar contra esa base, crea `.env.local` con los mismos dos valores. **Nunca** pongas la clave `service_role` en el navegador ni en el repositorio (Regla Dura 2).

## Verificaciones automáticas

Todas corren en el CI; conviene correrlas antes de abrir un pull request.

| Comando | Qué asegura |
|---|---|
| `npm run build` | Tipos y compilación |
| `npm run check:i18n` | Toda clave de traducción usada existe en `src/locales/es.json` (Regla Dura 9) |
| `npm run check:literals` | Ningún texto visible escrito a mano en los componentes (Regla Dura 9) |
| `npm run check:modales` | Un modal es para decisiones cortas: más de 3 campos va en una página |
| `npm run check:errores` | Cada error de la base tiene su código `BVnnn` y su texto |
| `npm run scan:secrets` | Sin `service_role` ni llaves en el repositorio (Regla Dura 2) |
| `npm run test:unit` | Lógica pura: reportes, CSV, fechas flexibles, grupos por edad, diccionarios… |
| `npm run test:rls` | Pruebas negativas de la base (ver abajo) |
| `npm run audit:ui` | Auditor de interfaz con navegador (ver abajo) |
| `npm run primer-uso` | Recorrido de primer uso (RNF-14) con tres tareas guiadas |

## Pruebas de seguridad de la base

```bash
npm run test:rls                      # contra el proyecto enlazado (la demo)
npm run test:rls -- --local           # contra una base local efímera (lo que hace el CI)
npm run test:rls -- --include=<migración>   # prueba una migración SIN empujarla
```

Son cientos de pruebas **negativas** («esto debe estar prohibido y lo está»): aislamiento entre organizaciones, `viewer` sin datos identificables, ausencia de `DELETE`, `audit_event` append-only, bitácora inmutable, estatus que no se sobrescribe, funciones cerradas a `anon`, a quien no tiene rol y a otras organizaciones. Corren **dentro de una transacción que siempre se revierte**: crean su propio escenario (dos organizaciones y un usuario de cada rol) y no dejan rastro. El resultado final dice cuántas pasan; deben pasar todas antes de cerrar un ciclo.

`--include=<nombre completo de la migración>` aplica esa migración dentro de la misma transacción de prueba, antes del escenario, y se revierte con ella: es la forma de **probar una migración nueva antes de empujarla**. Usa el nombre completo, no el prefijo del día: las ya empujadas chocan al repetirse. Una vez empujada, `--include` ya no hace falta. Las pruebas se escriben **antes** que la migración, en rojo.

## Auditoría de interfaz

```bash
npm run build && npm run audit:ui
```

> **Compila primero.** El auditor sirve la carpeta `dist` tal como está: si no recompilas, audita una versión vieja y puede decir «sin hallazgos» sobre una interfaz que no vio.

Recorre la aplicación compilada con `playwright-core` y el Edge o Chrome del sistema (no descarga navegadores). Prueba los 6 roles en 5 anchos (360, 390, 768, 1024, 1440 px): desbordamiento horizontal, texto menor de 12 px, contraste AA, controles sin nombre accesible, áreas táctiles menores de 44 px, claves de traducción sin resolver, códigos técnicos visibles, botones deshabilitados sin decir por qué y los modales (`role="dialog"`, Escape, foco). Recorre también, solo con teclado, login → alta → entrada de bitácora, y cada pestaña de las pantallas de varias secciones. No escribe datos. Debe terminar en «✓ Sin hallazgos». `AUDIT_DEBUG=1` imprime el orden de Tab.

## Base de datos

Todo cambio de esquema es una **migración versionada** en `supabase/migrations/` (Regla Dura 10): nada se cambia desde la consola de Supabase, y una migración aplicada no se edita.

```bash
npx supabase login
npx supabase link --project-ref <ref>   # una sola vez por máquina
npx supabase db push --dry-run          # qué subiría
npx supabase db push                    # aplica las migraciones pendientes
```

- **`db push` siempre lo confirma el Product Owner**, y va **antes** de fusionar el pull request que depende de la migración.
- Proyecto de la demo: `lbmytnjvpkjepsaiqymd` (`us-west-2`, Postgres 17).
- `supabase/seed.sql` es **exclusivo de demo**: siembra 60 expedientes sintéticos, cuentas demo y marca el entorno como `demo` (`app_config`). Nunca se ejecuta en producción. Una base sin esa fila se considera `production`: la interfaz no muestra el aviso de demo ni ofrece cuentas de acceso rápido.

### Reglas para escribir funciones SQL

Toda función `security definer` **se salta RLS**: si no repite la regla de acceso, la regla no existe. Una función nueva debe (1) comprobar sesión, rol operativo y organización (`fn_assert_same_org`), (2) ser ejecutable solo por `authenticated`, (3) fijar su `search_path`, (4) lanzar errores con código `BVnnn` y (5) llevar su prueba negativa en `supabase/tests/rls_negative.sql`. Si escribe en `audit_event`, **nunca guarda valores personales**: solo nombres de campos (`fn_audit_trigger_fields`) o identificadores.

### Reiniciar la demo

```bash
npm run demo:reset -- --confirm <project-ref> --dry-run   # prueba completa y revierte
npm run demo:reset -- --confirm <project-ref>             # reinicia de verdad
```

Vacía los datos de negocio, borra las cuentas demo y vuelve a sembrar. Se niega si la base no está marcada `demo`. **Borra también la auditoría de la demo.** Es un comando de operador y no una función de la aplicación, a propósito: una función destructiva alcanzable desde un rol de aplicación contradiría las Reglas Duras 3 y 4.

## Integración continua, ramas y despliegue

**`main` está protegida:** exige que pasen *Verificación estática* y *Pruebas de seguridad (base local)*; un `git push` directo se rechaza. La *Auditoría de interfaz (base local)* corre también pero es informativa.

GitHub Actions (`.github/workflows/ci.yml`) corre en cada pull request y en cada push a `main`:

- **Verificación estática:** `scan:secrets`, `build`, `check:i18n`, `check:literals`, `check:modales`, `check:errores` y `test:unit`.
- **Pruebas de seguridad (base local):** levanta un Supabase **efímero** (todas las migraciones desde cero y la semilla) y corre `test:rls -- --local`. No toca la demo; si una migración depende de algo que solo existe en la demo, aquí falla.
- **Auditoría de interfaz (base local):** compila contra esa base y corre `audit:ui`.

La herramienta de Supabase está fijada en `package.json` para que CI y equipo usen la misma versión.

**Flujo de trabajo**

1. Rama desde `main` actualizada: `git checkout main && git pull && git checkout -b <tipo>/<tema>` (`feat/…`, `fix/…`, `docs/…`).
2. Escribir primero la prueba (en rojo), luego el cambio. Probar en local y subir: `git push -u origin <rama>`.
3. Abrir el pull request; el CI corre sobre él.
4. Si hay migración: `db push --dry-run`, confirmación del Product Owner, `db push`, y la suite completa contra la demo ya migrada.
5. Con los dos checks obligatorios en verde, fusionar («Squash and merge») y borrar la rama.

**Despliegue.** `.github/workflows/deploy.yml` se dispara cuando el CI termina en verde sobre `main` y crea un despliegue que **espera la aprobación del Product Owner** en el entorno `production`; omite el despliegue si lo publicado ya corresponde al último commit. El pie de la aplicación muestra la **versión en ejecución** (`0.1.0 · <commit>`): compárala con el último commit de `main` para confirmar que el sitio está al día.

### Cabeceras de seguridad

`public/_headers` (CSP, `frame-ancestors`, `Referrer-Policy`, `X-Content-Type-Options`…) lo aplica Cloudflare al servir `dist`. El origen de Supabase está escrito en `connect-src` e `img-src`: **si cambia el proyecto (p. ej. producción), cámbialo ahí**.

## Seguidor de tareas (E7)

Integrado desde *CAFEMIN Task Tracker* (se absorbió el código, no hay fork). Rutas bajo `#/tareas`; los reportes llevan en la URL su estado (filtros por identificador; **la búsqueda por texto nunca viaja en el enlace**).

- **Roles:** `task_manager` y `volunteer` conviven con los cuatro de casos (los roles se acumulan, ADR-0007). Sin rol de casos no se lee ni una fila de `person` ni de `case`.
- **Baja lógica:** ninguna tabla de tareas admite `DELETE`; archivar es definitivo. Toda escritura deja `audit_event`.
- **Evidencia fotográfica:** bucket **privado** `task-evidence`; se guarda la ruta, nunca una URL. El navegador reduce la foto (1600 px) y le quita la ubicación; ver una foto pasa por `fn_task_evidence_access` (deja evento) y firma una URL de 60 s.
- **Tareas ligadas a un caso:** solo viaja el folio; el nombre sale de un catálogo neutro y no hay texto libre.
- **Errores:** SQLSTATE `TK001`–`TK028`, traducidos en `errors.task.*`.
- Lo que hace cada rol, en lenguaje de producto: `10_producto/estado_funciones_roles.md` (memoria documental).

## Estructura

```
src/
  App.tsx                 sesión, carga de datos, enrutado y manejadores de escritura
  components/             pantallas, páginas de captura y modales (un archivo por pantalla)
  lib/
    data.ts               lecturas bajo RLS (loadOrgData) y envoltorios de las funciones de la base (api / dataApi)
    session.tsx           login, roles, áreas y cierre por inactividad
    navigation.ts         pantallas permitidas por rol (única fuente) · router.ts: la ruta va en el hash
    catalog.tsx           áreas, estatus, diccionarios y grupos por edad, disponibles para toda la interfaz
    errors.ts             convierte un error de la base (BVnnn) en un texto con el siguiente paso
    derived.ts, flexDate.ts, dictionaries.ts, journalTemplates.ts, privacy.ts …   lógica pura, con su *.test.ts al lado
  locales/es.json         todas las cadenas visibles (Regla Dura 9)
  types/database.ts       tipos de lo que devuelve la base
supabase/                 esquema, semilla, reinicio de la demo y pruebas (ver su README)
scripts/                  verificaciones, pruebas de seguridad, auditor de interfaz y reinicio de la demo
docs/                     mapa del producto y la arquitectura
```

## Estado y decisiones

El estado del producto frente al MVP, al backlog y a los controles de privacidad, y las decisiones vigentes, están en la memoria documental: empieza por su `README.md` (índice) y por `40_bitacora/guia-de-decisiones.md`.
