import { supabase } from './supabase';
import { t } from './i18n';
import { friendlyError } from './errors';
import { EVIDENCE_SIGNED_URL_SECONDS, evidencePath, evidenceProblem, prepareEvidence } from './evidence';
import {
  TaskEvidence,
  RoutineTemplate,
  RoutineTemplateItem,
  ShiftKind,
  ShiftNote,
  Task,
  TaskCategory,
  TaskSetting,
  TaskStatus,
  WorkArea,
} from '../types/database';

// Capa de datos del Seguidor de tareas (E7). La seguridad vive en la base (RLS, disparadores y
// funciones): este módulo sólo lee lo que RLS devuelve y escribe en tablas cuya política y
// disparador deciden qué cambia cada rol. Reglas duras 1, 3 y 5: nada se borra (se archiva) y toda
// escritura queda en auditoría por disparador.

/** Roles que reciben tareas: sirven para poblar el selector «Asignar a». */
const TASK_ROLES = ['director', 'task_manager', 'volunteer', 'caseworker', 'intake_officer'];

export interface TaskData {
  tasks: Task[];
  categories: TaskCategory[];
  workAreas: WorkArea[];
  /** Tareas que ya tienen al menos una evidencia fotográfica */
  evidenceTaskIds: Set<string>;
  /** Personas a quienes se puede asignar una tarea (activas, con acceso a tareas) */
  assignableUserIds: string[];
  routines: RoutineTemplate[];
  routineItems: RoutineTemplateItem[];
  notes: ShiftNote[];
  /** Ajustes de operación de la organización (nulo si aún no existen) */
  setting: TaskSetting | null;
}

export const EMPTY_TASK_DATA: TaskData = {
  tasks: [],
  categories: [],
  workAreas: [],
  evidenceTaskIds: new Set(),
  assignableUserIds: [],
  routines: [],
  routineItems: [],
  notes: [],
  setting: null,
};

/** Error de la base con su código (SQLSTATE: TK001…, 42501…) para explicarlo con el siguiente paso. */
export class TaskError extends Error {
  constructor(message: string, readonly code?: string) {
    super(message);
  }
}

interface DbError {
  message: string;
  code?: string;
}

async function rows<T>(query: PromiseLike<{ data: T[] | null; error: DbError | null }>): Promise<T[]> {
  const { data, error } = await query;
  if (error) throw new TaskError(error.message, error.code);
  return data || [];
}

export async function loadTaskData(): Promise<TaskData> {
  const [tasks, categories, workAreas, evidence, roles, routines, routineItems, notes, settings] = await Promise.all([
    rows<Task>(supabase.from('task').select('*').order('created_at', { ascending: false }).limit(1000)),
    rows<TaskCategory>(supabase.from('task_category').select('*').order('sort_order').order('label_es')),
    rows<WorkArea>(supabase.from('work_area').select('*').order('sort_order').order('label_es')),
    rows<{ task_id: string }>(supabase.from('task_evidence').select('task_id').is('archived_at', null)),
    rows<{ user_id: string }>(supabase.from('user_role').select('user_id').is('revoked_at', null).in('role_name', TASK_ROLES)),
    rows<RoutineTemplate>(supabase.from('routine_template').select('*').order('name')),
    rows<RoutineTemplateItem>(supabase.from('routine_template_item').select('*').order('sort_order')),
    // RLS decide qué notas llegan: el alcance y la ventana de lectura son un ajuste de la organización
    rows<ShiftNote>(supabase.from('shift_note').select('*').order('created_at', { ascending: false }).limit(300)),
    rows<TaskSetting>(supabase.from('task_setting').select('*').limit(1)),
  ]);
  return {
    tasks,
    categories,
    workAreas,
    evidenceTaskIds: new Set(evidence.map((e) => e.task_id)),
    assignableUserIds: Array.from(new Set(roles.map((r) => r.user_id))),
    routines,
    routineItems,
    notes,
    setting: settings[0] ?? null,
  };
}
export interface TaskInput {
  name: string;
  details: string | null;
  task_category_id: string | null;
  work_area_id: string | null;
  assigned_to: string | null;
  due_at: string | null;
  photo_required: boolean;
}

/** Confirma que la escritura alcanzó una fila: si RLS no la deja ver o cambiar, no devuelve ninguna. */
async function wrote(query: PromiseLike<{ data: unknown[] | null; error: DbError | null }>): Promise<void> {
  const { data, error } = await query;
  if (error) throw new TaskError(error.message, error.code);
  if (!data || data.length === 0) throw new TaskError('row-level security', '42501');
}

export const taskApi = {
  create: (organizationId: string, input: TaskInput) =>
    wrote(supabase.from('task').insert({ organization_id: organizationId, ...input }).select('id')),

  update: (id: string, input: TaskInput) => wrote(supabase.from('task').update(input).eq('id', id).select('id')),

  setStatus: (id: string, status: TaskStatus) =>
    wrote(supabase.from('task').update({ status }).eq('id', id).select('id')),

  /** Baja lógica: definitiva (Regla Dura 3). Ninguna tarea se borra. */
  archive: (id: string) =>
    wrote(supabase.from('task').update({ archived_at: new Date().toISOString() }).eq('id', id).select('id')),
};

/** Llama una función de la base. Las que tocan el pool, las rutinas y los ajustes validan rol y organización por dentro. */
async function call<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) throw new TaskError(error.message, error.code);
  return data as T;
}

// ---- Pool de tareas abiertas (BV-7.10)
// Tomar es atómico (bloqueo de fila: dos personas no toman la misma) y respeta el tope de la organización.
// Soltar es el inverso, y sólo de lo que la persona tomó por su cuenta y no empezó.
export const poolApi = {
  claim: (taskId: string) => call('fn_claim_open_task', { p_task_id: taskId }),
  release: (taskId: string) => call('fn_release_task', { p_task_id: taskId }),
  /** Lo tomado y vencido vuelve al pool. Corre al abrir el pool, sin depender de pg_cron. */
  releaseExpired: () => call<number>('fn_release_expired_claims', {}),
};

// ---- Plantillas de rutina (BV-7.11)

export interface RoutineItemDraft {
  /** Presente si ya existe: se actualiza en lugar de crearse */
  id?: string;
  name: string;
  details: string | null;
  photo_required: boolean;
}

export interface RoutineDraft {
  id?: string;
  name: string;
  description: string | null;
  work_area_id: string | null;
  task_category_id: string | null;
  items: RoutineItemDraft[];
}

export const routineApi = {
  /** Iniciar una rutina: crea las tareas de la plantilla, asignadas a quien la inicia (una vez por día). */
  start: (templateId: string) => call<{ routine: string; tasks_created: number }>('fn_start_routine', { p_template_id: templateId }),

  /**
   * Guarda una plantilla y sus pasos. Son varias escrituras (cada una con su política y su auditoría), no una
   * sola transacción: si una falla a medias, la plantilla queda con lo que alcanzó a guardarse, a la vista y
   * editable, y volver a guardar la deja completa porque cada paso se actualiza por su identificador.
   */
  async save(organizationId: string, draft: RoutineDraft, existing: RoutineTemplateItem[]): Promise<void> {
    const header = {
      name: draft.name.trim(),
      description: draft.description?.trim() || null,
      work_area_id: draft.work_area_id,
      task_category_id: draft.task_category_id,
    };
    let templateId = draft.id;
    if (templateId) {
      await wrote(supabase.from('routine_template').update(header).eq('id', templateId).select('id'));
    } else {
      const { data, error } = await supabase.from('routine_template').insert({ organization_id: organizationId, ...header }).select('id').single();
      if (error) throw new TaskError(error.message, error.code);
      templateId = (data as { id: string }).id;
    }

    // Los pasos que ya no están se dan de baja (no se borran)
    const keep = new Set(draft.items.map((i) => i.id).filter((x): x is string => !!x));
    for (const old of existing.filter((e) => e.routine_template_id === templateId && !e.archived_at && !keep.has(e.id))) {
      await wrote(supabase.from('routine_template_item').update({ archived_at: new Date().toISOString() }).eq('id', old.id).select('id'));
    }
    for (const [i, item] of draft.items.entries()) {
      const fields = { name: item.name.trim(), details: item.details?.trim() || null, photo_required: item.photo_required, sort_order: i + 1 };
      if (item.id) {
        await wrote(supabase.from('routine_template_item').update(fields).eq('id', item.id).select('id'));
      } else {
        await wrote(supabase.from('routine_template_item').insert({ organization_id: organizationId, routine_template_id: templateId, ...fields }).select('id'));
      }
    }
  },

  archive: (id: string) => wrote(supabase.from('routine_template').update({ archived_at: new Date().toISOString() }).eq('id', id).select('id')),
};

// ---- Evidencia fotográfica (BV-7.14, BV-7.15)
// Bucket PRIVADO: no hay URL pública. Abrir una foto pide permiso a la base (que deja evento de auditoría y
// devuelve la ruta) y sólo entonces firma una URL de 60 s (EVIDENCE_SIGNED_URL_SECONDS). Nada se actualiza ni se borra: corregir es subir otra.
export const evidenceApi = {
  list: (taskId: string) =>
    rows<TaskEvidence>(supabase.from('task_evidence').select('*').eq('task_id', taskId).is('archived_at', null).order('created_at', { ascending: false })),

  /** Reduce la foto, la sube al bucket y registra su ruta. Devuelve sólo cuando ambas cosas quedaron hechas. */
  async upload(organizationId: string, taskId: string, original: File): Promise<void> {
    const file = await prepareEvidence(original);
    const problem = evidenceProblem(file);
    if (problem) throw new TaskError(problem, `EV-${problem}`);
    const path = evidencePath(organizationId, taskId, file.type, crypto.randomUUID());
    const up = await supabase.storage.from('task-evidence').upload(path, file, { contentType: file.type, upsert: false });
    if (up.error) throw new TaskError(up.error.message, 'EV-storage');
    await wrote(supabase.from('task_evidence').insert({ organization_id: organizationId, task_id: taskId, storage_path: path, mime_type: file.type, size_bytes: file.size }).select('id'));
  },

  /** URL firmada de corta vida. La función de la base valida rol y tarea, y registra el acceso. */
  async open(evidenceId: string): Promise<string> {
    const path = await call<string>('fn_task_evidence_access', { p_evidence_id: evidenceId });
    const { data, error } = await supabase.storage.from('task-evidence').createSignedUrl(path, EVIDENCE_SIGNED_URL_SECONDS);
    if (error || !data) throw new TaskError(error?.message ?? 'sin URL', 'EV-storage');
    return data.signedUrl;
  },
};

// ---- Notas de turno (BV-7.12): se agregan, no se editan; retirar es baja lógica.

export interface ShiftNoteInput {
  body: string;
  shift: ShiftKind;
  work_area_id: string | null;
}

export const noteApi = {
  create: (organizationId: string, input: ShiftNoteInput) =>
    wrote(supabase.from('shift_note').insert({ organization_id: organizationId, body: input.body.trim(), shift: input.shift, work_area_id: input.work_area_id }).select('id')),
  retract: (id: string) => wrote(supabase.from('shift_note').update({ archived_at: new Date().toISOString() }).eq('id', id).select('id')),
};

// ---- Ajustes de operación (BV-7.13): sólo la dirección, por función de la base.
export const settingApi = {
  update: (s: Pick<TaskSetting, 'shift_note_scope' | 'shift_note_days' | 'pool_max_unstarted' | 'pool_release_days'>) =>
    call('fn_update_task_setting', {
      p_shift_note_scope: s.shift_note_scope,
      p_shift_note_days: s.shift_note_days,
      p_pool_max_unstarted: s.pool_max_unstarted,
      p_pool_release_days: s.pool_release_days,
    }),
};

// ---- Catálogos de tareas (BV-7.9): categorías y áreas de trabajo. Sólo dirección escribe (RLS).

export type CatalogKind = 'category' | 'workArea';
const CATALOG_TABLE: Record<CatalogKind, string> = { category: 'task_category', workArea: 'work_area' };

/**
 * Clave estable del catálogo a partir de la etiqueta: minúsculas, sin acentos, con guiones bajos y única
 * entre las ya existentes (también las archivadas: una clave no se reutiliza). La etiqueta se puede
 * renombrar después; la clave, no. Formato exigido por la base: `^[a-z][a-z0-9_]{1,39}$`.
 */
export function makeCatalogKey(label: string, taken: string[]): string {
  let base = label
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
  if (!/^[a-z]/.test(base)) base = `c_${base}`;
  base = base.slice(0, 34).replace(/_+$/g, '');
  // La base exige al menos 2 caracteres: una etiqueta de puros símbolos no puede dejar la clave en «c»
  if (base.length < 2) base = 'c_item';
  let key = base;
  for (let n = 2; taken.includes(key); n++) key = `${base}_${n}`;
  return key;
}

export const catalogApi = {
  create: (kind: CatalogKind, organizationId: string, label: string, takenKeys: string[]) =>
    wrote(supabase.from(CATALOG_TABLE[kind]).insert({ organization_id: organizationId, key: makeCatalogKey(label, takenKeys), label_es: label.trim() }).select('id')),

  rename: (kind: CatalogKind, id: string, label: string) =>
    wrote(supabase.from(CATALOG_TABLE[kind]).update({ label_es: label.trim() }).eq('id', id).select('id')),

  /** Baja lógica y definitiva (Regla Dura 3): las tareas que ya la usan conservan su etiqueta. */
  archive: (kind: CatalogKind, id: string) =>
    wrote(supabase.from(CATALOG_TABLE[kind]).update({ archived_at: new Date().toISOString() }).eq('id', id).select('id')),
};

/** Explica un error con el siguiente paso. Los códigos TK de la base tienen texto propio. */
export function taskErrorMessage(e: unknown): string {
  if (e instanceof TaskError && e.code?.startsWith('TK')) {
    const key = `errors.task.${e.code.toLowerCase()}`;
    const text = t(key);
    if (text !== key) return text;
  }
  if (e instanceof TaskError && e.code?.startsWith('EV-')) {
    const key = `errors.task.${e.code.toLowerCase().replace('-', '_')}`;
    const text = t(key);
    if (text !== key) return text;
  }
  const raw = e instanceof Error ? e.message : String(e);
  return friendlyError(raw);
}
