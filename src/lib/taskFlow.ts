import { Task, TaskStatus } from '../types/database';

// El flujo de estados de una tarea, en un solo lugar.
//
// Hay DOS formas de mover una tarea —arrastrarla en el tablero de escritorio y pulsar un botón en el
// teléfono— y dos caminos que decidan por su cuenta qué movimiento es válido acaban divergiendo; el que
// se usa menos es el que se queda atrás. Estas reglas son un ESPEJO de las que la base impone
// (disparador fn_task_guard, TK001–TK003): sirven para no ofrecer un botón que la base va a rechazar.
// La que manda es la base.

export const TASK_STATUSES: TaskStatus[] = ['pending', 'in_progress', 'done'];

const RANK: Record<TaskStatus, number> = { pending: 0, in_progress: 1, done: 2 };

export function nextStatus(status: TaskStatus): TaskStatus | null {
  const i = TASK_STATUSES.indexOf(status);
  return i === -1 || i === TASK_STATUSES.length - 1 ? null : TASK_STATUSES[i + 1];
}

export interface Advance {
  to: TaskStatus;
  /** Clave de traducción del texto del botón */
  labelKey: string;
  /** El avance exige evidencia que todavía no existe */
  needsPhoto: boolean;
}

export interface FlowContext {
  /** Dirección o coordinación de tareas: reabren y cierran sin foto */
  isManagement: boolean;
  hasEvidence: boolean;
}

/** ¿Qué avance se ofrece sobre esta tarea? Null si ya está al final. */
export function availableAdvance(task: Task, ctx: FlowContext): Advance | null {
  const to = nextStatus(task.status);
  if (!to) return null;
  // La coordinación se salta la exigencia de foto (decisión de producto; la base lo permite)
  const needsPhoto = to === 'done' && task.photo_required && !ctx.hasEvidence && !ctx.isManagement;
  return {
    to,
    needsPhoto,
    labelKey: to === 'in_progress' ? 'tasks.action_start' : needsPhoto ? 'tasks.action_finish_photo' : 'tasks.action_finish',
  };
}

/** Espejo de TK002: quien no gestiona sólo avanza; la coordinación mueve en cualquier sentido. */
export function canMove(task: Task, to: TaskStatus, isManagement: boolean): boolean {
  if (task.status === to) return false;
  if (isManagement) return true;
  return RANK[to] > RANK[task.status];
}

/** Vencida: tiene fecha límite pasada y no está cerrada. `due_at` es una fecha (AAAA-MM-DD). */
export function isOverdue(task: Task, today: Date = new Date()): boolean {
  if (!task.due_at || task.status === 'done') return false;
  const y = today.getFullYear();
  const m = String(today.getMonth() + 1).padStart(2, '0');
  const d = String(today.getDate()).padStart(2, '0');
  return task.due_at < `${y}-${m}-${d}`;
}

export function groupByStatus(tasks: Task[]): Record<TaskStatus, Task[]> {
  const out: Record<TaskStatus, Task[]> = { pending: [], in_progress: [], done: [] };
  for (const t of tasks) out[t.status].push(t);
  return out;
}

export interface Progress {
  total: number;
  pending: number;
  inProgress: number;
  done: number;
  percent: number;
  allDone: boolean;
}

/** Avance de la jornada de una persona a partir de sus tareas. */
export function progressOf(tasks: Task[]): Progress {
  const total = tasks.length;
  const done = tasks.filter((t) => t.status === 'done').length;
  const inProgress = tasks.filter((t) => t.status === 'in_progress').length;
  return {
    total,
    pending: total - done - inProgress,
    inProgress,
    done,
    percent: total === 0 ? 0 : Math.round((done / total) * 100),
    allDone: total > 0 && done === total,
  };
}
