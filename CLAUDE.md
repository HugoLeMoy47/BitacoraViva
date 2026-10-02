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

## Normativa y alineación vigente (Octubre 2026):
- Ethos: v1.2 (Biometría fuera de alcance E-01; nota de trabajo protegida `is_work_note` excluida de ARCO E-02; requerimientos de autoridad para directores E-03; umbral de agregación $n \ge 5$ E-05).
- Requisitos No Funcionales: v1.0 vigente (Timeout sesión 30 min RNF-04; retención auditoría 5 años RNF-05; prioridad responsive móvil/tablet en captura y escritorio en dashboards RNF-08).
- Modelo de Datos: Ficha de identificación, contexto de ingreso y marcadores de vulnerabilidad adoptan el estándar validado en campo de MAP-OIM v3 (MD-01 resuelto).
