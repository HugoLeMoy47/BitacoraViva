import { TaskStatus } from '../types/database';
import { TASK_STATUSES } from './taskFlow';
import { EMPTY_FILTERS, PERIODS, Period, ReportFilters, SORT_FIELDS, SortField, SortState, UNASSIGNED } from './taskReports';

// Estado del reporte guardado en la URL (BV-7.8): una vista filtrada se puede pegar en un correo y quien
// la abra ve exactamente lo mismo. Módulo puro: cadena de consulta entra, estado sale, y al revés; el
// historial del navegador lo toca la vista.
//
// `search` NO viaja en el enlace, y es deliberado. Los demás filtros sólo pueden tomar valores que ya
// existen en los catálogos o en el personal; el texto libre puede contener el nombre de una persona
// atendida, y una URL se pega en correos, queda en el historial y sobrevive al motivo por el que se
// compartió (riesgo R-17). Lo mismo al leer: un enlace con `q=` se ignora.

export type ReportTab = 'overview' | 'status' | 'person' | 'date';
export const REPORT_TABS: ReportTab[] = ['overview', 'status', 'person', 'date'];
export const DEFAULT_TAB: ReportTab = 'overview';

/** Orden inicial de cada pestaña. «Resumen» no tiene tabla: no tiene orden. */
export const INITIAL_SORT: Partial<Record<ReportTab, SortState>> = {
  status: { field: 'created', direction: 'desc' },
  person: { field: 'person', direction: 'asc' },
  date: { field: 'created', direction: 'desc' },
};

export interface ReportState {
  tab: ReportTab;
  filters: ReportFilters;
  sort: SortState | null;
}

/** Tope de longitud de un valor que llega de fuera: sólo evita que una URL fabricada meta texto enorme al estado. */
const MAX_VALUE = 120;
const clip = (v: string | null): string => (v ?? '').slice(0, MAX_VALUE);

/**
 * Lee el estado desde una cadena de consulta. Todo lo que tiene un conjunto cerrado de valores
 * (pestaña, periodo, estado, campo y dirección de orden) se valida contra él y, si no coincide, cae al
 * valor por defecto: un enlace mal editado abre el reporte normal, no uno roto.
 */
export function readLink(query: string): ReportState {
  const p = new URLSearchParams(query || '');
  const tabAsked = p.get('vista') as ReportTab | null;
  const tab = tabAsked && REPORT_TABS.includes(tabAsked) ? tabAsked : DEFAULT_TAB;

  const period = p.get('periodo') as Period | null;
  const status = p.get('estado') as TaskStatus | null;
  const filters: ReportFilters = {
    ...EMPTY_FILTERS,
    period: period && PERIODS.includes(period) ? period : EMPTY_FILTERS.period,
    person: clip(p.get('persona')),
    status: status && TASK_STATUSES.includes(status) ? status : '',
    workArea: clip(p.get('area')),
    category: clip(p.get('categoria')),
  };

  const base = INITIAL_SORT[tab];
  if (!base) return { tab, filters, sort: null };
  const sort: SortState = { ...base };
  const raw = p.get('orden');
  if (raw) {
    const [field, direction] = raw.split(':');
    if (SORT_FIELDS.includes(field as SortField)) {
      sort.field = field as SortField;
      sort.direction = direction === 'asc' || direction === 'desc' ? direction : 'asc';
    }
  }
  return { tab, filters, sort };
}

/** Escribe el estado como cadena de consulta, SÓLO lo que se aparta del valor por defecto. */
export function writeLink(state: ReportState): string {
  const p = new URLSearchParams();
  if (state.tab !== DEFAULT_TAB) p.set('vista', state.tab);
  const f = state.filters;
  if (f.period !== EMPTY_FILTERS.period) p.set('periodo', f.period);
  if (f.person) p.set('persona', f.person);
  if (f.status) p.set('estado', f.status);
  if (f.workArea) p.set('area', f.workArea);
  if (f.category) p.set('categoria', f.category);
  const base = INITIAL_SORT[state.tab];
  if (base && state.sort && (state.sort.field !== base.field || state.sort.direction !== base.direction)) {
    p.set('orden', `${state.sort.field}:${state.sort.direction}`);
  }
  return p.toString();
}

/**
 * Descarta los valores de persona, área o categoría que ya no existen en los datos: sin esto un enlace
 * con una persona que se fue deja el selector en blanco y la tabla en cero sin explicación. Descartarlo
 * muestra el reporte completo, que es la lectura honesta de «ese filtro ya no aplica».
 */
export function sanitizeFilters(f: ReportFilters, valid: { persons: string[]; workAreas: string[]; categories: string[] }): ReportFilters {
  const live = (value: string, list: string[]) => (value && list.includes(value) ? value : '');
  return {
    ...f,
    // «Sin asignar» no sale de los datos: es una opción sintética del selector
    person: f.person === UNASSIGNED ? UNASSIGNED : live(f.person, valid.persons),
    workArea: live(f.workArea, valid.workAreas),
    category: live(f.category, valid.categories),
  };
}
