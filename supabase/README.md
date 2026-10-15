# Base de datos (Supabase / Postgres)

Aquí vive **todo** el esquema, la seguridad y la lógica de escritura del producto. Dos ideas para leer este directorio:

1. **La seguridad vive en la base** (Regla Dura 1): RLS en toda tabla de negocio y funciones `security definer` que repiten la regla de acceso. La interfaz solo *informa*; no protege.
2. **Las migraciones no se editan una vez aplicadas** (Regla Dura 10). Un cambio es una migración nueva. Por eso este directorio es una historia: para saber cómo es una función *hoy*, busca su última definición (`grep -n "fn_nombre" migrations/*.sql` y toma la más reciente).

```
supabase/
  migrations/             el esquema, en orden cronológico (el índice está abajo)
  seed.sql                semilla de la DEMO (60 expedientes ficticios, cuentas demo, catálogos); nunca en producción
  demo/reset_demo.sql     vaciado para reiniciar la demo
  tests/rls_negative.sql  pruebas negativas: una sola transacción que se revierte
  config.toml             configuración de la base local (CI)
```

## Cómo se prueba

```bash
npm run test:rls                                       # contra la demo, en una transacción que se revierte
npm run test:rls -- --local                            # contra una base local efímera (como hace el CI)
npm run test:rls -- --include=20261021000001           # prueba una migración nueva SIN empujarla: se aplica dentro de la transacción de prueba
```

Una prueba nueva se escribe **antes** que la migración (en rojo) y se ve pasar a verde con ella. `supabase db push` es un paso aparte y **siempre pide confirmación del Product Owner**: primero `--dry-run`, y el push va antes de fusionar el pull request.

## Índice de migraciones

Una línea por migración. «E#» es la épica del backlog; «E14» es el empalme con la hoja de casos de CAFEMIN.

### Fundación y núcleo (14 sep – 2 oct)
| Migración | Qué introduce |
|---|---|
| `20260914000001_foundation` | Organizaciones, áreas, usuarios y roles, auditoría (E1) |
| `20261002000001_status_and_cases` | Ejes de estatus historizados, persona, expediente, marcadores de vulnerabilidad (E2, E3) |
| `20261002000002_journal_and_sharing` | Bitácora de área inmutable, compartición con motivo, adjuntos (E4) |
| `20261002000003_consent_and_arco` | Consentimientos, aviso de privacidad, derechos ARCO y anonimización (E5) |

### Endurecimiento y modo demo (6 – 7 oct)
| Migración | Qué introduce |
|---|---|
| `20261006000001_revoke_destructive_grants` | Quita `DELETE`/`UPDATE` indebidos a los roles de aplicación (Reglas 3 y 4) |
| `20261006000002_create_case_with_person` | Alta atómica de persona + expediente + marcadores |
| `20261006000003_fix_audit_event_writes` | Corrección de escrituras a `audit_event` |
| `20261007000001_viewer_and_tenant_hardening` | El observador no ve datos identificables; aislamiento por organización |
| `20261007000002_app_environment` | Etiqueta de entorno demo / producción |
| `20261007000003_extended_aggregate_metrics` | Indicadores agregados con umbral n ≥ 5 |
| `20261007000004_case_status_append_only` | El estatus no se sobrescribe: se cierra y se abre otro (Regla 7) |
| `20261007000005_rpc_access_guards` | Las funciones `security definer` repiten la regla de acceso |
| `20261007000006_intake_consent_gate` | Paso cero del alta: aviso y consentimiento explícito |
| `20261007000007_metrics_period_and_trend` | Indicadores con periodo, comparación y tendencia |
| `20261007000008_organization_configuration` | Identidad de la organización, aviso y textos de consentimiento (E9) |
| `20261007000009_org_identity_single_audit` | Un solo evento de auditoría por cambio de identidad |

### Seguidor de tareas (E7, 9 oct)
| Migración | Qué introduce |
|---|---|
| `20261009000001_task_roles` | Roles `task_manager` y `volunteer` (ADR-0007) |
| `20261009000002_task_tables` | Tablas de tareas con RLS, auditoría y baja lógica |
| `20261009000003_task_functions` | Pool, rutinas, ajustes y acceso a evidencia |
| `20261009000004_task_storage` | Bucket privado de evidencia fotográfica |
| `20261009000005_active_account_guard` | Cuenta desactivada = sin acceso al expediente |
| `20261009000006_task_realtime` | Tiempo real en el tablero |
| `20261009000007_task_case_link` | Vínculo tarea–caso (solo el folio viaja) |

### Auditoría de endurecimiento (11 – 14 oct)
| Migración | Qué introduce |
|---|---|
| `20261011000001_hardening_compartmentalization` | Compartimentación por área; auditoría sin valores personales (ADR-0008) |
| `20261011000002_core_writes_by_function_only` | El núcleo se escribe solo por funciones |
| `20261011000003_anonymize_pseudonymize_third_parties` | Anonimizar también pseudonimiza a terceros |
| `20261011000004_aggregate_metrics_no_subtraction` | Indicadores sin re-identificación por resta |
| `20261011000005_clarification_inherits_sharing` | La aclaración llega a quien recibió la entrada original |
| `20261011000006_metrics_exact_for_staff` | Cifras exactas para el personal; redondeadas para el observador |
| `20261012000001_subfolio` | Subfolio de niñez y adolescencia acompañadas (BV-3.2) |
| `20261012000002_motivo_estatus_inicial` | El motivo inicial de un estatus es una clave de traducción |
| `20261014000001_errores_con_codigo` | Errores de dominio con código estable `BVnnn` (E13 fase 1) |
| `20261014000002_cybersec_hardening` | Auditoría encadenada SHA-256, lecturas auditadas, matriz de campos sensibles (ADR-0009) |

### Empalme con la hoja de casos de CAFEMIN (E14, 15 – 21 oct)
| Migración | Qué introduce |
|---|---|
| `20261015000001_e14_fase1_persona_documentos` | Documentos de la persona, religión, detalle de marcadores, referencia heredada |
| `20261015000002_catalogo_geografico_inegi` | Estados y municipios oficiales (INEGI) |
| `20261015000003_cero_valores_supuestos` | Ningún valor por omisión inventado; bloqueo de campos sensibles sin consentimiento (D-14) |
| `20261016000001_e14_fase2_fechas_flexibles` | Cuatro fechas del caso con precisión día / mes / año |
| `20261016000002_e14_fase2b_alojamiento_con_fecha` | Ingreso y egreso del albergue con su estatus |
| `20261017000001_e14_fase3_familia_paralela` | Unidad familiar paralela, con tipos editables |
| `20261018000001_e14_fase4a_diccionarios_idioma_religion` | Diccionarios editables (`catalog_item`); idioma y religión como valor + detalle |
| `20261019000001_e14_fase4b_necesidades_y_plan_juridico` | Necesidades específicas como casillas; plan al ingreso |
| `20261020000001_e14_fase4_bitacora_por_area` | Tipos de entrada nuevos, línea de servicio, procedencia de lo importado |
| `20261021000001_e14_fase5_derivados` | Grupos por edad configurables (solo por edad, sin sexo) |

## Convenciones que conviene saber

- **Errores de dominio:** `raise exception '…' using errcode = 'BVnnn'`. Cada código tiene su texto en `src/locales/es.json` (`errors.db.*`) y su fila en `30_entrega/catalogo-codigos-de-error.md` (memoria documental). `npm run check:errores` lo verifica. Las tareas usan `TK001`–`TK028`.
- **Nada se borra:** los datos se *cierran* con motivo (`valid_to`, `closed_by`, `change_reason`) o se anonimizan. Ningún rol de aplicación tiene `DELETE` sobre tablas de negocio.
- **Toda escritura deja auditoría** por disparador (`fn_audit_trigger_fields` registra *qué campos* cambiaron, nunca los valores).
- **Nombres:** tablas, columnas y funciones en inglés `snake_case`, tomados del glosario; textos visibles en español.
