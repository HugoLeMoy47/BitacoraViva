import { supabase } from './supabase';
import { t } from './i18n';
import { friendlyError } from './errors';
import { Task, TaskCategory, TaskStatus, WorkArea } from '../types/database';

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
}

export const EMPTY_TASK_DATA: TaskData = {
  tasks: [],
  categories: [],
  workAreas: [],
  evidenceTaskIds: new Set(),
  assignableUserIds: [],
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
  const [tasks, categories, workAreas, evidence, roles] = await Promise.all([
    rows<Task>(supabase.from('task').select('*').order('created_at', { ascending: false }).limit(1000)),
    rows<TaskCategory>(supabase.from('task_category').select('*').order('sort_order').order('label_es')),
    rows<WorkArea>(supabase.from('work_area').select('*').order('sort_order').order('label_es')),
    rows<{ task_id: string }>(supabase.from('task_evidence').select('task_id').is('archived_at', null)),
    rows<{ user_id: string }>(supabase.from('user_role').select('user_id').is('revoked_at', null).in('role_name', TASK_ROLES)),
  ]);
  return {
    tasks,
    categories,
    workAreas,
    evidenceTaskIds: new Set(evidence.map((e) => e.task_id)),
    assignableUserIds: Array.from(new Set(roles.map((r) => r.user_id))),
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

/** Explica un error con el siguiente paso. Los códigos TK de la base tienen texto propio. */
export function taskErrorMessage(e: unknown): string {
  if (e instanceof TaskError && e.code?.startsWith('TK')) {
    const key = `errors.task.${e.code.toLowerCase()}`;
    const text = t(key);
    if (text !== key) return text;
  }
  const raw = e instanceof Error ? e.message : String(e);
  return friendlyError(raw);
}
