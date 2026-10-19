# Diagramas de Bitácora Viva

Diagramas HTML interactivos y autocontenidos (abren con doble clic, sin servidor), generados con la skill [Archify](https://github.com/tt-a1i/archify). Los JSON de `fuente/` son la fuente; los `.html` se regeneran.

| Diagrama | Archivo | Tipo |
|---|---|---|
| Arquitectura | `arquitectura.html` | architecture |
| Proceso de atención de un caso | `proceso-atencion.html` | workflow |
| Del cambio al despliegue | `proceso-desarrollo.html` | workflow |
| Mapa del producto | `producto.html` | tree |
| Datos: identidad, permisos y auditoría | `erd-identidad.html` | erd |
| Datos: persona y caso | `erd-persona-caso.html` | erd |
| Datos: estatus, familia y ficha social | `erd-estatus-familia.html` | erd |
| Datos: bitácora, consentimiento y ARCO | `erd-bitacora-privacidad.html` | erd |
| Datos: seguidor de tareas | `erd-tareas.html` | erd |

Son un mapa, no la fuente de verdad: si algo contradice a la memoria documental (ver `CLAUDE.md`), manda la memoria documental.

## Regenerar

Los ERD salen de `supabase/migrations/`, así que se rehacen cuando cambia el esquema:

```bash
node docs/diagramas/generar-erd.mjs
for n in erd-identidad erd-persona-caso erd-estatus-familia erd-bitacora-privacidad erd-tareas; do bash docs/diagramas/fin.sh erd $n; done
```

Los demás se editan a mano en `fuente/*.json` y se validan con `bash docs/diagramas/fin.sh <tipo> <nombre> showcase` (tipo: `architecture`, `workflow` o `tree`). `fin.sh` usa la skill instalada en `~/.claude/skills/archify` y pasa las cuatro compuertas (validar, entregar, revisar, navegador).

Para pedir un diagrama nuevo basta con decirle a Claude Code «usa Archify para dibujar…».
