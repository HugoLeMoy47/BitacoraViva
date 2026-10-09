import { Task, TaskStatus } from '../types/database';
import { TASK_STATUSES, isOverdue } from './taskFlow';

// Agregaciones de los reportes de tareas (BV-7.8).
//
// Funciones PURAS a propósito: reciben tareas y devuelven datos planos. Las vistas sólo dibujan lo que
// sale de aquí, de modo que la lógica que puede estar mal —conteos, cortes de semana, promedios— se
// puede revisar sin navegador. Una sola barra de filtros gobierna TODO (resumen, agrupaciones y
// exportación): las pestañas son formas de agrupar el mismo conjunto, no filtros; sin esa regla el
// botón de exportar descargaría 42 filas mientras la pantalla muestra 12.

/** Valor sintético: «sin persona asignada». No sale de los datos. */
export const UNASSIGNED = 'unassigned';

export type Period = 'all' | '30' | '90';
export const PERIODS: Period[] = ['all', '30', '90'];

export interface ReportFilters {
  /** Texto libre. NO viaja en el enlace: puede contener el nombre de una persona atendida (R-17). */
  search: string;
  period: Period;
  /** '' = todas · UNASSIGNED · id de la persona */
  person: string;
  status: '' | TaskStatus;
  /** id del área de trabajo */
  workArea: string;
  /** id de la categoría */
  category: string;
}

export const EMPTY_FILTERS: ReportFilters = { search: '', period: 'all', person: '', status: '', workArea: '', category: '' };

export function hasActiveFilters(f: ReportFilters): boolean {
  return f.search.trim() !== '' || f.period !== 'all' || f.person !== '' || f.status !== '' || f.workArea !== '' || f.category !== '';
}

/**
 * Quita acentos y pasa a minúsculas: buscar «bano» tiene que encontrar «Baños»; exigir el acento
 * convierte el buscador en un examen de ortografía.
 */
export function normalize(text: string | null | undefined): string {
  return String(text ?? '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '');
}

export const personKey = (t: Task): string => t.assigned_to ?? UNASSIGNED;

export function applyFilters(tasks: Task[], f: ReportFilters, now: Date = new Date()): Task[] {
  const q = normalize(f.search).trim();
  let since: Date | null = null;
  if (f.period !== 'all') {
    since = new Date(now);
    since.setDate(since.getDate() - Number(f.period));
    since.setHours(0, 0, 0, 0);
  }
  return tasks.filter((t) => {
    if (q && !normalize(t.name).includes(q)) return false;
    if (f.status && t.status !== f.status) return false;
    if (f.person && personKey(t) !== f.person) return false;
    if (f.workArea && t.work_area_id !== f.workArea) return false;
    if (f.category && t.task_category_id !== f.category) return false;
    if (since) {
      const created = new Date(t.created_at);
      if (Number.isNaN(created.getTime()) || created < since) return false;
    }
    return true;
  });
}

// ------------------------------------------------------------------ conteos

export interface StatusCounts {
  pending: number;
  in_progress: number;
  done: number;
  total: number;
}

const emptyCounts = (): StatusCounts => ({ pending: 0, in_progress: 0, done: 0, total: 0 });

/** Conteo por estado, con los tres presentes aunque alguno sea cero: una barra ausente se lee como «no existe». */
export function statusSummary(tasks: Task[]): { status: TaskStatus; count: number }[] {
  return TASK_STATUSES.map((status) => ({ status, count: tasks.filter((t) => t.status === status).length }));
}

export interface GroupRow {
  key: string;
  name: string;
  counts: StatusCounts;
}

/**
 * Desglose por una dimensión (persona, categoría, área): cuántas tareas hay en cada estado.
 * Va ordenado por total descendente y, a igualdad, alfabético: el orden es estable entre recargas.
 */
export function groupCounts(tasks: Task[], keyOf: (t: Task) => string, nameOf: (key: string) => string): GroupRow[] {
  const map = new Map<string, GroupRow>();
  for (const t of tasks) {
    const key = keyOf(t);
    let row = map.get(key);
    if (!row) {
      row = { key, name: nameOf(key), counts: emptyCounts() };
      map.set(key, row);
    }
    row.counts[t.status] += 1;
    row.counts.total += 1;
  }
  return [...map.values()].sort((a, b) => b.counts.total - a.counts.total || a.name.localeCompare(b.name, 'es'));
}

// ------------------------------------------------------------------ semanas

/** Fecha local AAAA-MM-DD (nunca por UTC: a medianoche local cambiaría de día). */
export function localDateKey(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/** Lunes 00:00 (hora local) de la semana de una fecha. Lunes porque así empieza la semana laboral aquí. */
export function weekStart(date: Date | string): Date | null {
  const d = new Date(date);
  if (Number.isNaN(d.getTime())) return null;
  d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
  d.setHours(0, 0, 0, 0);
  return d;
}

export interface WeekBucket {
  start: Date;
  key: string;
  created: number;
  closed: number;
}

/**
 * Serie semanal de tareas creadas y cerradas. Se emiten TODAS las semanas del rango, también las
 * vacías: saltarse una semana sin actividad comprime el eje y hace que un hueco parezca continuidad.
 */
export function weeklySeries(tasks: Task[], weeks = 10, reference: Date = new Date()): WeekBucket[] {
  const current = weekStart(reference);
  if (!current) return [];
  const buckets: WeekBucket[] = [];
  const index = new Map<string, WeekBucket>();
  for (let i = weeks - 1; i >= 0; i--) {
    const start = new Date(current);
    start.setDate(start.getDate() - i * 7);
    const bucket = { start, key: localDateKey(start), created: 0, closed: 0 };
    buckets.push(bucket);
    index.set(bucket.key, bucket);
  }
  const add = (iso: string | null, field: 'created' | 'closed') => {
    if (!iso) return;
    const start = weekStart(iso);
    const bucket = start ? index.get(localDateKey(start)) : undefined;
    if (bucket) bucket[field] += 1; // fuera del rango se ignora: no se apila en el borde
  };
  for (const t of tasks) {
    add(t.created_at, 'created');
    add(t.done_at, 'closed');
  }
  return buckets;
}

// ------------------------------------------------------------------ desempeño
//
// Las tareas sin `started_at` quedan FUERA de los promedios y se cuentan aparte: promediar sobre
// ellas como si fueran cero inventaría un desempeño que nadie midió.

const DAY_MS = 86_400_000;

/** Diferencia en días entre dos marcas de tiempo. Nulo si falta alguna. */
export function daysBetween(from: string | null, to: string | null): number | null {
  if (!from || !to) return null;
  const a = new Date(from).getTime();
  const b = new Date(to).getTime();
  return Number.isNaN(a) || Number.isNaN(b) ? null : (b - a) / DAY_MS;
}

function mean(values: (number | null)[]): number | null {
  const ok = values.filter((v): v is number => v !== null && Number.isFinite(v));
  return ok.length === 0 ? null : ok.reduce((sum, v) => sum + v, 0) / ok.length;
}

export interface GlobalMetrics {
  total: number;
  pending: number;
  inProgress: number;
  done: number;
  overdue: number;
  percentDone: number;
  /** Días promedio entre crear y empezar (sobre las que ya empezaron) */
  waitMean: number | null;
  /** Días promedio entre empezar y cerrar (sobre las cerradas con inicio) */
  workMean: number | null;
  /** Días promedio entre crear y cerrar (sobre las cerradas) */
  totalMean: number | null;
  /** Cerradas sin marca de inicio: se nombran para que nadie lea los promedios como si las cubrieran */
  unmeasured: number;
}

export function globalMetrics(tasks: Task[], now: Date = new Date()): GlobalMetrics {
  const done = tasks.filter((t) => t.status === 'done');
  const started = tasks.filter((t) => t.started_at);
  const measurable = done.filter((t) => t.started_at);
  return {
    total: tasks.length,
    pending: tasks.filter((t) => t.status === 'pending').length,
    inProgress: tasks.filter((t) => t.status === 'in_progress').length,
    done: done.length,
    overdue: tasks.filter((t) => isOverdue(t, now)).length,
    percentDone: tasks.length ? Math.round((done.length / tasks.length) * 100) : 0,
    waitMean: mean(started.map((t) => daysBetween(t.created_at, t.started_at))),
    workMean: mean(measurable.map((t) => daysBetween(t.started_at, t.done_at))),
    totalMean: mean(done.map((t) => daysBetween(t.created_at, t.done_at))),
    unmeasured: done.filter((t) => !t.started_at).length,
  };
}

export interface PersonMetrics {
  key: string;
  name: string;
  done: number;
  open: number;
  wait: number | null;
  work: number | null;
  /** espera + trabajo = tiempo de ciclo */
  cycle: number | null;
  measured: number;
}

/**
 * Espera contra trabajo, por persona. Ambas se miden sobre la MISMA población —las tareas cerradas con
 * marca de inicio— para que su suma sea un tiempo de ciclo real: promediar la espera sobre todas las
 * iniciadas y el trabajo sólo sobre las cerradas mezclaría dos universos. Las dos van en días, así que
 * se apilan en una sola escala en vez de recurrir a dos ejes, que es la forma más común de mentir con
 * un gráfico.
 */
export function personMetrics(tasks: Task[], nameOf: (key: string) => string): PersonMetrics[] {
  const map = new Map<string, { waits: (number | null)[]; works: (number | null)[]; done: number; open: number }>();
  for (const t of tasks) {
    const key = personKey(t);
    let row = map.get(key);
    if (!row) {
      row = { waits: [], works: [], done: 0, open: 0 };
      map.set(key, row);
    }
    if (t.status === 'done') row.done += 1;
    else row.open += 1;
    if (t.status === 'done' && t.started_at) {
      row.waits.push(daysBetween(t.created_at, t.started_at));
      row.works.push(daysBetween(t.started_at, t.done_at));
    }
  }
  return [...map.entries()]
    .map(([key, r]) => {
      const wait = mean(r.waits);
      const work = mean(r.works);
      return {
        key,
        name: nameOf(key),
        done: r.done,
        open: r.open,
        wait,
        work,
        cycle: wait === null && work === null ? null : (wait ?? 0) + (work ?? 0),
        measured: r.works.length,
      };
    })
    .sort((a, b) => (b.cycle ?? -1) - (a.cycle ?? -1) || a.name.localeCompare(b.name, 'es'));
}

export interface RecurringTask {
  name: string;
  times: number;
  done: number;
  totalMean: number | null;
}

/** Tareas que se repiten, agrupadas por nombre exacto. */
export function recurringTasks(tasks: Task[], minimum = 2): RecurringTask[] {
  const map = new Map<string, { times: number; done: number; durations: (number | null)[] }>();
  for (const t of tasks) {
    const name = t.name.trim();
    if (!name) continue;
    let row = map.get(name);
    if (!row) {
      row = { times: 0, done: 0, durations: [] };
      map.set(name, row);
    }
    row.times += 1;
    if (t.status === 'done') {
      row.done += 1;
      row.durations.push(daysBetween(t.created_at, t.done_at));
    }
  }
  return [...map.entries()]
    .filter(([, r]) => r.times >= minimum)
    .map(([name, r]) => ({ name, times: r.times, done: r.done, totalMean: mean(r.durations) }))
    .sort((a, b) => b.times - a.times || a.name.localeCompare(b.name, 'es'));
}

// ------------------------------------------------------------------ orden

export type SortField = 'task' | 'status' | 'person' | 'category' | 'workArea' | 'created' | 'due' | 'done';
export interface SortState {
  field: SortField;
  direction: 'asc' | 'desc';
}
export const SORT_FIELDS: SortField[] = ['task', 'status', 'person', 'category', 'workArea', 'created', 'due', 'done'];

/** Resuelve los nombres que se ordenan (personas y catálogos viven fuera de la tarea). */
export interface Lookups {
  person: (id: string | null) => string | null;
  category: (id: string | null) => string | null;
  workArea: (id: string | null) => string | null;
}

type SortValue = { kind: 'text'; value: string | null } | { kind: 'date'; value: string | null } | { kind: 'status'; value: TaskStatus };

function sortValue(t: Task, field: SortField, lk: Lookups): SortValue {
  switch (field) {
    case 'task': return { kind: 'text', value: t.name };
    case 'status': return { kind: 'status', value: t.status };
    case 'person': return { kind: 'text', value: lk.person(t.assigned_to) };
    case 'category': return { kind: 'text', value: lk.category(t.task_category_id) };
    case 'workArea': return { kind: 'text', value: lk.workArea(t.work_area_id) };
    case 'created': return { kind: 'date', value: t.created_at };
    case 'due': return { kind: 'date', value: t.due_at };
    case 'done': return { kind: 'date', value: t.done_at };
  }
}

const comparable = (v: SortValue): number | string | null => {
  if (v.kind === 'status') return TASK_STATUSES.indexOf(v.value);
  if (v.value === null || v.value === '') return null;
  if (v.kind === 'date') {
    const ms = new Date(v.value).getTime();
    return Number.isNaN(ms) ? null : ms;
  }
  return v.value;
};

/**
 * Ordena sin mutar el arreglo original. Los vacíos van SIEMPRE al final, en ambas direcciones: un valor
 * ausente no es «el más pequeño», no existe, y arrastrarlo al principio al invertir el orden esconde las
 * filas que sí tienen dato. El estado ordena por el flujo (pendiente, en curso, hecha), no alfabéticamente.
 */
export function sortTasks(tasks: Task[], sort: SortState, lk: Lookups): Task[] {
  const sign = sort.direction === 'desc' ? -1 : 1;
  return [...tasks].sort((a, b) => {
    const va = comparable(sortValue(a, sort.field, lk));
    const vb = comparable(sortValue(b, sort.field, lk));
    if (va === null && vb === null) return a.name.localeCompare(b.name, 'es');
    if (va === null) return 1;
    if (vb === null) return -1;
    const cmp = typeof va === 'string' && typeof vb === 'string' ? va.localeCompare(vb, 'es') : Number(va) - Number(vb);
    // Desempate estable por nombre: dos recargas dan el mismo orden
    return cmp !== 0 ? cmp * sign : a.name.localeCompare(b.name, 'es');
  });
}
