// Genera los candidatos JSON de Archify para el modelo de datos, a partir de las migraciones.
// Uso: node docs/diagramas/generar-erd.mjs   (luego: archify finalize erd <json> <html>)
import { mkdirSync, writeFileSync } from 'node:fs'
import { tables } from './parse-schema.mjs'

const TRANSVERSAL = new Set(['organization', 'user_profile', 'auth_users'])
const MAPAS = [
  {
    id: 'erd-identidad', title: 'Modelo de datos · Identidad, permisos y auditoría',
    dominios: [
      ['identidad', ['organization', 'user_profile', 'auth_users', 'user_invitation']],
      ['roles y permisos', ['role', 'user_role', 'area', 'capability', 'capability_grant']],
      ['auditoría y operación', ['audit_event', 'authority_request', 'app_config']],
    ],
    notas: [
      ['cyan', 'Aislamiento por organización', ['Toda tabla de negocio lleva organization_id y RLS por fila.', 'user_profile cuelga de auth.users (Supabase Auth).']],
      ['amber', 'Roles que se acumulan', ['user_role guarda el rol y, si aplica, el área; se revoca sin borrar (revoked_at).', 'capability_grant concede una capacidad a un rol o a un área, nunca a ambos.']],
      ['emerald', 'Auditoría append-only', ['audit_event no admite UPDATE ni DELETE; encadena eventos con prev_hash y event_hash.', 'Solo director puede consultarla.']],
    ],
  },
  {
    id: 'erd-persona-caso', title: 'Modelo de datos · Persona y caso',
    dominios: [
      ['persona', ['person', 'person_document', 'person_occupation', 'document_type']],
      ['caso', ['case', 'case_date', 'case_vulnerability_marker']],
      ['catálogos de ingreso', ['intake_channel', 'entry_route', 'geo_state', 'geo_municipality', 'catalog_item']],
    ],
    notas: [
      ['cyan', 'Folio y subfolio', ['case.parent_case_id enlaza el subfolio de una niña, niño o adolescente acompañado con el caso de la persona adulta responsable.', 'previous_case_id encadena reingresos.']],
      ['amber', 'Nada se sobrescribe', ['Documentos, ocupaciones y fechas se cierran con valid_to y change_reason; se abre un registro nuevo.', 'person se anonimiza (is_anonymized), no se borra.']],
      ['emerald', 'Catálogos', ['Los diccionarios (idioma, religión, ocupación, necesidades) viven en catalog_item, editables por organización.', 'La geografía sigue el catálogo INEGI (estado y municipio).']],
    ],
  },
  {
    id: 'erd-estatus-familia', title: 'Modelo de datos · Estatus, familia y ficha social',
    dominios: [
      ['estatus multieje', ['status_axis', 'status_value', 'case_status', 'age_band']],
      ['familia', ['family_type', 'family_unit', 'family_member']],
      ['ficha social', ['social_question', 'social_answer', 'case_need']],
    ],
    notas: [
      ['cyan', 'Estatus historizado', ['Cada eje (jurídico, estancia, albergue, expediente, etapa) guarda su valor vigente y el histórico.', 'Cambiar de estatus cierra el vigente (valid_to) y abre otro con motivo obligatorio.']],
      ['amber', 'Familia paralela', ['family_unit agrupa casos; family_member enlaza cada caso con su familia y su papel.', 'Un caso puede cambiar de familia sin perder historia.']],
      ['emerald', 'Ficha social', ['social_question es un catálogo editable; social_answer guarda cada respuesta con su vigencia.', 'case_need registra las necesidades detectadas contra catalog_item.']],
    ],
  },
  {
    id: 'erd-bitacora-privacidad', title: 'Modelo de datos · Bitácora, consentimiento y ARCO',
    dominios: [
      ['bitácora', ['journal_entry', 'sharing_event', 'attachment']],
      ['consentimiento', ['privacy_notice', 'consent_text', 'consent']],
      ['derechos ARCO', ['arco_request']],
    ],
    notas: [
      ['cyan', 'Bitácora inmutable y privada', ['journal_entry nace area_private; una corrección crea otra entrada (superseded_by_id).', 'Compartir entre áreas exige motivo y deja un sharing_event que dirección reconoce.']],
      ['amber', 'Consentimiento', ['consent registra el tipo (cuidado general, datos sensibles, compartición interna, uso secundario) y se revoca sin borrarse.', 'Sin consentimiento no se captura un campo sensible.']],
      ['emerald', 'ARCO', ['arco_request registra acceso, rectificación, cancelación u oposición, con motivo obligatorio.', 'La cancelación se atiende por anonimización.']],
    ],
  },
  {
    id: 'erd-tareas', title: 'Modelo de datos · Seguidor de tareas',
    dominios: [
      ['catálogos de tareas', ['task_category', 'work_area', 'case_task_kind', 'task_setting']],
      ['tareas y rutinas', ['routine_template', 'routine_template_item', 'task', 'task_evidence']],
      ['turnos', ['shift_note']],
    ],
    notas: [
      ['cyan', 'Aparte del expediente', ['Quien solo tiene rol de tareas no recibe filas de personas ni de casos.', 'task.case_id liga una tarea a un caso solo para quien tiene permiso sobre ese caso.']],
      ['amber', 'Claves compuestas', ['Las referencias llevan (id, organization_id): una tarea no puede apuntar a catálogos de otra organización.']],
      ['emerald', 'Evidencia privada', ['task_evidence guarda la ruta en un bucket privado (máximo 5 MB; jpeg, png o webp).', 'Archivar no borra: la tarea sigue en reportes y auditoría.']],
    ],
  },
]

const sqlType = (t) => t.replace('integer', 'int')

function build(m) {
  const own = m.dominios.flatMap(([, ts]) => ts).filter((t) => t !== 'auth_users')
  const stubs = new Set()
  for (const t of own) for (const c of tables.get(t)) {
    if (c.ref) { const tgt = c.ref.split('.')[0]; if (!own.includes(tgt) && !m.dominios.some(([, ts]) => ts.includes(tgt))) stubs.add(tgt) }
  }
  const entities = []
  const rel = []
  const addEntity = (t, tag, row, col) => {
    const stub = stubs.has(t) && t !== 'auth_users'
    const cols = t === 'auth_users'
      ? [{ name: 'id', type: 'uuid', pk: true }, { name: 'email', type: 'text' }]
      : stub ? tables.get(t).slice(0, 10) : tables.get(t)
    const ancho = Math.max(240, Math.ceil(54 + Math.max(...cols.map((c) => c.name.length * 6.6 + sqlType(c.type).length * 6 + 12)) / 2) * 2)
    entities.push({
      id: t, width: ancho, label: t === 'auth_users' ? 'auth.users' : t, tag, row, col,
      ...(stub ? { sublabel: 'extracto; la tabla completa está en otro diagrama' } : t === 'auth_users' ? { sublabel: 'Supabase Auth' } : {}),
      attributes: cols.map((c) => {
        const key = []
        if (c.pk) key.push('pk')
        if (c.ref && !stub) key.push('fk')
        if (c.uk && !c.pk) key.push('uk')
        return {
          name: c.name, type: sqlType(c.type),
          ...(key.length ? { key: key.length === 1 ? key[0] : key } : {}),
          ...(c.ref && !stub ? { references: c.ref } : {}),
        }
      }),
    })
  }
  m.dominios.forEach(([tag, ts], col) => ts.forEach((t, row) => addEntity(t, tag, row, col)))
  const present = new Set(entities.map((e) => e.id))
  const lastCol = m.dominios.length
  ;[...stubs].filter((s) => !present.has(s)).sort((a, b) => TRANSVERSAL.has(a) - TRANSVERSAL.has(b)).forEach((t, i) => addEntity(t, 'referencia', i, lastCol))
  const all = new Set(entities.map((e) => e.id))
  for (const t of own) for (const c of tables.get(t)) {
    if (!c.ref) continue
    const [tgt] = c.ref.split('.')
    if (!all.has(tgt)) continue
    // organization_id y las columnas de autoría hacia user_profile están en todas las tablas: se resumen en una tarjeta
    if (tgt === 'organization') continue
    if (tgt === 'user_profile' && !['user_role', 'user_invitation'].includes(t)) continue
    if (tgt === 'auth_users' && t !== 'user_profile') continue
    if (t === tgt) continue // autorreferencias: se describen en una tarjeta
    rel.push({ id: `${t}_${c.name}`, from: t, to: tgt, fromCardinality: 'many', toCardinality: 'one', ...(c.notNull ? {} : { toOptional: true }) })
  }
  for (const r of rel) {
    if (rel.filter((x) => x.from === r.from && x.to === r.to).length > 1) r.label = r.id.slice(r.from.length + 1)
  }
  return {
    schema_version: 1, diagram_type: 'erd',
    meta: { title: m.title, locale: 'es', output: `docs/diagramas/${m.id}.html`, quality_profile: 'standard' },
    layout: { mode: 'grid', gapX: 80, gapY: 40 },
    entities, relationships: rel,
    cards: [
      ...m.notas.map(([dot, title, items]) => ({ dot, title, items })),
    ],
  }
}

mkdirSync(new URL('fuente/', import.meta.url), { recursive: true })
for (const m of MAPAS) writeFileSync(new URL(`fuente/${m.id}.json`, import.meta.url), JSON.stringify(build(m), null, 2))
console.log('ok', MAPAS.length)
