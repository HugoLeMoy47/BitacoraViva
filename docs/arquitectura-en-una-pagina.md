# Bitácora Viva en una página

> Esta página es un **mapa**, no la fuente de verdad. El producto, el Ethos, el glosario y las decisiones viven en la memoria documental (OneDrive; ver `CLAUDE.md`). Si algo aquí contradice a la memoria documental, manda la memoria documental.

## Qué es

Una plataforma para que **organizaciones de atención humanitaria** (albergues, casas del migrante) lleven sus casos con dignidad y rastro: quién atendió a quién, qué se hizo, qué se compartió y con qué consentimiento. Es **multi-organización** desde el diseño: varias asociaciones usan lo mismo sin ver los datos de las demás. Hoy hay un entorno **demo** con datos ficticios; todavía no se capturan datos de personas reales.

Cuatro módulos: **gestión de casos** (el núcleo), **seguidor de tareas** (voluntariado y coordinación), **monitoreo y evaluación** (hoy, los indicadores) y el ERP de recursos, que queda para después. Además, la configuración de la organización (identidad, aviso de privacidad, consentimientos) y los diccionarios editables.

## Las tres piezas

```
 Navegador (React + TypeScript)          Supabase (Postgres + Auth + Storage)         Cloudflare
 ─────────────────────────────           ───────────────────────────────────          ──────────
 src/                                    supabase/migrations/                         Worker que sirve
  pantallas y formularios   ──lee──►      tablas con RLS (solo lo permitido)          los archivos
  (solo informan)           ──escribe─►   funciones security definer:                 estáticos de dist/
                                          validan rol y organización, escriben,
                                          dejan auditoría, devuelven un error
                                          con código estable (BVnnn)
```

- **El navegador habla directo con Supabase**, con una clave pública (`anon`). No hay servidor propio de aplicación. La clave `service_role` **nunca** llega al navegador ni al repositorio.
- **La seguridad vive en la base de datos.** Que la interfaz oculte un botón no protege nada; lo que protege es RLS y las funciones. Si una regla no está en la base, no existe.
- **Cloudflare solo sirve archivos.** El despliegue lo hace GitHub Actions cuando el CI pasa en `main`, y espera la aprobación del Product Owner.

## Cómo viaja una escritura (el recorrido que más conviene entender)

1. Una pantalla (`src/components/…`) llama a un método de `src/lib/data.ts` (`api.…` / `dataApi.…`).
2. Ese método invoca una **función de la base** por RPC (`fn_…`). Casi nunca se escribe directo en una tabla.
3. La función comprueba sesión, rol y organización (`fn_assert_same_org`), valida, escribe y devuelve un resultado. Si algo falla, lanza un error con código `BVnnn`.
4. Un **disparador** deja el evento en `audit_event` (qué campos cambiaron, nunca los valores). La auditoría está encadenada con SHA-256.
5. En el navegador, `friendlyError` traduce el código a un texto con el siguiente paso (`src/locales/es.json` → `errors.db.*`) y la app vuelve a leer lo que RLS permite ver.

## Reglas que conviene recordar al tocar cualquier cosa

Las diez reglas duras están en `30_entrega/handoff-agente-desarrollo.md` (en OneDrive). Las que más se sienten al programar:

- **Nada se borra ni se sobrescribe.** Se *cierra* (con motivo) y se abre otro registro; se anonimiza en lugar de borrar. La bitácora es inmutable.
- **Lo nuevo nace privado:** una entrada de bitácora es de su área (`area_private`) hasta que alguien la comparte con motivo.
- **Ningún valor supuesto:** si falta un dato, se muestra «No registrado»; no se inventa un valor por omisión.
- **Cero textos en los componentes:** todo texto visible es una clave en `src/locales/es.json` (`npm run check:literals`).
- **Cero cambios de esquema desde la consola:** todo es una migración versionada.
- **Nombres:** código en inglés `snake_case`; interfaz y documentos en español; los nombres salen del glosario.

## Dónde está cada cosa

| Busco… | Voy a… |
|---|---|
| Una pantalla | `src/components/` (formularios largos son *páginas*, no modales) |
| Cómo se lee o se escribe un dato | `src/lib/data.ts` (lecturas bajo RLS + envoltorios de las funciones) |
| Quién ve qué pantalla | `src/lib/navigation.ts` (única fuente) y `src/lib/router.ts` (la ruta va en el hash) |
| La lógica pura y probada | `src/lib/*.ts` con su `*.test.ts` al lado (`derived`, `flexDate`, `dictionaries`, `journalTemplates`…) |
| Un texto de pantalla o un mensaje de error | `src/locales/es.json` |
| El esquema y las funciones | `supabase/migrations/` — índice en [`supabase/README.md`](../supabase/README.md) |
| Las pruebas de seguridad | `supabase/tests/rls_negative.sql` (una transacción que se revierte) |
| La semilla de la demo | `supabase/seed.sql` y `supabase/demo/reset_demo.sql` |
| Las verificaciones automáticas | `scripts/` (`check:i18n`, `check:literals`, `check:modales`, `check:errores`, `scan:secrets`, `audit:ui`) |
| El CI y el despliegue | `.github/workflows/ci.yml` y `deploy.yml` |

## Quién puede qué (en una línea por rol)

`director` administra y ve todo lo de su organización · `intake_officer` abre expedientes · `caseworker` atiende casos · `viewer` ve solo indicadores · `task_manager` coordina tareas · `volunteer` ejecuta tareas. Los roles se **acumulan** (ADR-0007) y la pertenencia a un **área** (Trabajo Social, Jurídica, Psicosocial, Médica, Coordinación) compartimenta la bitácora. Trabajo Social, además, administra los diccionarios junto con la dirección.

## Cómo se trabaja

Rama desde `main` → pruebas primero (en rojo) → cambio → pull request con los dos checks en verde (*Verificación estática* y *Pruebas de seguridad*) → si hay migración, `supabase db push` solo con confirmación del Product Owner y **antes** de fusionar → despliegue aprobado en Actions. El detalle está en el [`README`](../README.md).
