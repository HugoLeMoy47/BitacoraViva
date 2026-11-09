# Bitácora Viva — repositorio de desarrollo

La fuente de verdad de este producto NO está en este repositorio.
Vive en la carpeta compartida de OneDrive:
- En equipo nekosurf: D:\hugol\OneDrive\07_Freejolitos\50_Productos\BitacoraViva
- En equipo nekoblue:  C:\Users\hugol\OneDrive\07_Freejolitos\50_Productos\BitacoraViva

Antes de cualquier cambio, lee:
  30_entrega/handoff-agente-desarrollo.md

Las diez reglas duras están en ese documento §2. No las repitas aquí:
si divergen, el documento manda.

Esquema, entidades y nombres: 20_arquitectura/ y 00_gobernanza/glosario.md
Qué construir ahora: 10_producto/backlog.md

## Reglas operativas para el agente de código:
1. **La seguridad vive en la base de datos.** RLS en toda tabla de negocio.
2. **`service_role` nunca llega al navegador ni al repositorio.**
3. **Ningún rol de aplicación tiene `DELETE`** sobre tablas de negocio.
4. **`audit_event` es append-only.** Sin `UPDATE`, sin `DELETE`, para nadie. Solo `director` puede consultar el log (Ethos C4).
5. **Toda escritura genera evento de auditoría, por disparador en la base.**
6. **`journal_entry` nace `area_private`**, por valor por defecto de columna.
7. **El estatus no se sobrescribe.** Se cierra el vigente y se abre uno nuevo en la misma transacción. Salidas anticipadas directas con motivo obligatorio (ME-02).
8. **Los nombres salen del glosario.** UI/docs en español, código en inglés `snake_case`.
9. **Cero literales de texto en componentes.** Toda cadena visible va con clave de traducción en `src/locales/`.
10. **Cero cambios de esquema desde consola.** Todo es migración versionada en `supabase/migrations/`.

## Estado, pendientes y decisiones

Viven en Jarvis, clave `FJ-BV` (conector MCP `jarvis`).
Al empezar: `consultar_proyecto`. Al terminar: `cerrar_sesion` con liga al commit o PR.
Sin conector: anota en `40_bitacora/decisiones.md` con encabezado `## AAAA-MM-DD · título`.

## Dónde está cada cosa
- Diario largo de decisiones de diseño: `40_bitacora/decisiones.md` (OneDrive, ver rutas arriba).
- Normativa vigente: `00_gobernanza/Ethos.md` (el número de versión está en su encabezado; no se copia aquí).
- Requisitos no funcionales y modelo de datos: `20_arquitectura/`.
- Backlog: `10_producto/backlog.md`.
