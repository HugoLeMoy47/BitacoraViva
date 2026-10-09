import React, { useEffect, useMemo, useState } from 'react';
import { t } from '../lib/i18n';
import { useToast } from '../lib/toast';
import { replaceQuery } from '../lib/router';
import { buildCsv, csvFileName, downloadCsv } from '../lib/csv';
import {
  DEFAULT_TAB,
  INITIAL_SORT,
  REPORT_TABS,
  ReportState,
  ReportTab,
  readLink,
  sanitizeFilters,
  writeLink,
} from '../lib/taskReportLink';
import {
  EMPTY_FILTERS,
  Lookups,
  ReportFilters,
  SortState,
  UNASSIGNED,
  applyFilters,
  globalMetrics,
  groupCounts,
  hasActiveFilters,
  localDateKey,
  personKey,
  personMetrics,
  recurringTasks,
  sortTasks,
  statusSummary,
  weeklySeries,
} from '../lib/taskReports';
import { Task, TaskCategory, WorkArea } from '../types/database';
import { Tabs } from './Tabs';
import { ReportFilterBar } from './ReportFilterBar';
import { ReportOverview, groupItems, statusLegend } from './ReportOverview';
import { BarLegend, ReportBars } from './ReportBars';
import { ReportTaskTable } from './ReportTaskTable';

// Reportes de tareas (BV-7.8): cuatro vistas del MISMO conjunto filtrado (resumen, por estado, por
// persona y por fecha). El estado de la vista (pestaña, filtros y orden) vive en la URL para poder
// compartirla; la búsqueda por texto, no (riesgo R-17). Sólo cuentan las tareas que no están archivadas.

interface TaskReportsViewProps {
  tasks: Task[];
  categories: TaskCategory[];
  workAreas: WorkArea[];
  userNames: Record<string, string>;
  /** Cadena de consulta con la que se abrió la pantalla (enlace compartido) */
  initialQuery: string;
  /** Prefijo del nombre del archivo exportado */
  filePrefix: string;
}

const weekLabel = (d: Date): string =>
  new Intl.DateTimeFormat('es-MX', { day: 'numeric', month: 'short' }).format(d).replace(/\./g, '');

export const TaskReportsView: React.FC<TaskReportsViewProps> = ({ tasks, categories, workAreas, userNames, initialQuery, filePrefix }) => {
  const toast = useToast();
  const [state, setState] = useState<ReportState>(() => readLink(initialQuery));
  const { tab, filters, sort } = state;

  // ---- nombres (todo lo que el reporte rotula sale de aquí)
  const categoryName = useMemo(() => new Map(categories.map((c) => [c.id, c.label_es])), [categories]);
  const workAreaName = useMemo(() => new Map(workAreas.map((a) => [a.id, a.label_es])), [workAreas]);
  const personName = (id: string | null): string => (id ? userNames[id] || t('tasks.assignee_former') : t('tasks.unassigned'));
  const categoryLabel = (id: string | null): string => (id ? categoryName.get(id) || '—' : t('tasks.reports.no_category'));
  const workAreaLabel = (id: string | null): string => (id ? workAreaName.get(id) || '—' : t('tasks.reports.no_work_area'));
  const lookups: Lookups = {
    person: (id) => (id ? personName(id) : null),
    category: (id) => (id ? categoryLabel(id) : null),
    workArea: (id) => (id ? workAreaLabel(id) : null),
  };

  // ---- opciones de los selectores, derivadas de los datos que hay
  const options = useMemo(() => {
    const ids = (pick: (t: Task) => string | null) => Array.from(new Set(tasks.map(pick).filter((x): x is string => !!x)));
    const sorted = (list: { id: string; label: string }[]) => list.sort((a, b) => a.label.localeCompare(b.label, 'es'));
    return {
      people: sorted(ids((x) => x.assigned_to).map((id) => ({ id, label: userNames[id] || t('tasks.assignee_former') }))),
      workAreas: sorted(ids((x) => x.work_area_id).map((id) => ({ id, label: workAreaName.get(id) || '—' }))),
      categories: sorted(ids((x) => x.task_category_id).map((id) => ({ id, label: categoryName.get(id) || '—' }))),
    };
  }, [tasks, userNames, workAreaName, categoryName]);

  // Un enlace con una persona, área o categoría que ya no existe se limpia (en vez de dejar todo en cero)
  useEffect(() => {
    setState((s) => {
      const clean = sanitizeFilters(s.filters, {
        persons: options.people.map((p) => p.id),
        workAreas: options.workAreas.map((a) => a.id),
        categories: options.categories.map((c) => c.id),
      });
      return clean.person === s.filters.person && clean.workArea === s.filters.workArea && clean.category === s.filters.category ? s : { ...s, filters: clean };
    });
  }, [options]);

  // La URL refleja la vista (sin la búsqueda), sin agregar historial por cada cambio
  const query = writeLink(state);
  useEffect(() => {
    replaceQuery('tasks', 'reportes', query);
  }, [query]);

  // ---- el conjunto filtrado gobierna todo
  const filtered = useMemo(() => applyFilters(tasks, filters), [tasks, filters]);
  const metrics = useMemo(() => globalMetrics(filtered), [filtered]);
  const nameOfPerson = (key: string) => (key === UNASSIGNED ? t('tasks.unassigned') : personName(key));
  const people = useMemo(() => groupCounts(filtered, personKey, nameOfPerson), [filtered, userNames]);
  const personTimes = useMemo(() => personMetrics(filtered, nameOfPerson), [filtered, userNames]);
  const recurring = useMemo(() => recurringTasks(filtered), [filtered]);
  const byCategory = useMemo(() => groupCounts(filtered, (x) => x.task_category_id ?? '', (k) => categoryLabel(k || null)), [filtered, categoryName]);
  const byWorkArea = useMemo(() => groupCounts(filtered, (x) => x.work_area_id ?? '', (k) => workAreaLabel(k || null)), [filtered, workAreaName]);
  const weeks = useMemo(() => weeklySeries(filtered), [filtered]);
  const summary = useMemo(() => statusSummary(filtered), [filtered]);

  const effectiveSort: SortState | null = sort ?? INITIAL_SORT[tab] ?? null;
  const sorted = useMemo(() => (effectiveSort ? sortTasks(filtered, effectiveSort, lookups) : filtered), [filtered, effectiveSort?.field, effectiveSort?.direction, userNames]);

  const setTab = (next: ReportTab) => setState((s) => ({ ...s, tab: next, sort: INITIAL_SORT[next] ?? null }));
  const setFilters = (next: ReportFilters) => setState((s) => ({ ...s, filters: next }));
  const active = hasActiveFilters(filters);

  const exportCsv = () => {
    const columns = (['task', 'status', 'person', 'category', 'workArea', 'created', 'due', 'started', 'done'] as const).map((key) => ({
      key,
      title: t(`tasks.reports.col_${key}`),
    }));
    const day = (iso: string | null) => (iso ? localDateKey(new Date(iso)) : '');
    const rows = sorted.map((x) => ({
      task: x.name,
      status: t(`tasks.status_${x.status}`),
      person: x.assigned_to ? personName(x.assigned_to) : '',
      category: x.task_category_id ? categoryLabel(x.task_category_id) : '',
      workArea: x.work_area_id ? workAreaLabel(x.work_area_id) : '',
      created: day(x.created_at),
      due: x.due_at ?? '',
      started: day(x.started_at),
      done: day(x.done_at),
    }));
    downloadCsv(csvFileName(filePrefix, t(`tasks.reports.tab_${tab}`)), buildCsv(columns, rows));
  };

  const copyLink = async () => {
    try {
      await navigator.clipboard.writeText(window.location.href);
      toast.success(t(filters.search.trim() ? 'tasks.reports.link_copied_no_search' : 'tasks.reports.link_copied'));
    } catch {
      toast.error(t('tasks.reports.link_failed'));
    }
  };

  const tabItems = REPORT_TABS.map((id) => ({ id, label: t(`tasks.reports.tab_${id}`) }));

  const table = effectiveSort ? (
    <ReportTaskTable
      tasks={sorted}
      sort={effectiveSort}
      onSort={(next) => setState((s) => ({ ...s, sort: next }))}
      personName={personName}
      categoryLabel={categoryLabel}
      workAreaLabel={workAreaLabel}
    />
  ) : null;

  const weekMax = Math.max(1, ...weeks.map((w) => Math.max(w.created, w.closed)));

  return (
    <div className="space-y-4">
      <ReportFilterBar
        filters={filters}
        onChange={setFilters}
        people={options.people}
        workAreas={options.workAreas}
        categories={options.categories}
        matching={filtered.length}
        total={tasks.length}
        active={active}
        onClear={() => setFilters(EMPTY_FILTERS)}
        onExport={exportCsv}
        onCopyLink={copyLink}
      />

      <Tabs ariaLabel={t('tasks.reports.views')} items={tabItems} value={tab} onChange={(id) => setTab(id as ReportTab)} className="flex-wrap" />

      {tab === DEFAULT_TAB && (
        <ReportOverview metrics={metrics} people={people} personTimes={personTimes} recurring={recurring} byCategory={byCategory} byWorkArea={byWorkArea} />
      )}

      {tab === 'status' && (
        <div className="space-y-4">
          <section className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm sm:p-5">
            <h3 className="mb-3 text-base font-bold text-carbon">{t('tasks.reports.by_status')}</h3>
            <ReportBars
              ariaLabel={t('tasks.reports.by_status')}
              items={summary.map((s) => ({
                key: s.status,
                label: t(`tasks.status_${s.status}`),
                segments: [{ value: s.count, className: s.status === 'done' ? 'bg-turquesa-dark' : s.status === 'in_progress' ? 'bg-turquesa' : 'bg-gray-400', label: t(`tasks.status_${s.status}`) }],
                valueText: String(s.count),
              }))}
              max={Math.max(1, ...summary.map((s) => s.count))}
            />
          </section>
          {table}
        </div>
      )}

      {tab === 'person' && (
        <div className="space-y-4">
          <section className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm sm:p-5">
            <h3 className="text-base font-bold text-carbon">{t('tasks.reports.by_person')}</h3>
            <p className="mb-3 mt-0.5 text-xs text-gray-600">{t('tasks.reports.load_hint')}</p>
            <BarLegend items={statusLegend} />
            <ReportBars items={groupItems(people)} ariaLabel={t('tasks.reports.by_person')} />
          </section>
          {table}
        </div>
      )}

      {tab === 'date' && (
        <div className="space-y-4">
          <section className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm sm:p-5">
            <h3 className="text-base font-bold text-carbon">{t('tasks.reports.by_week')}</h3>
            <p className="mb-3 mt-0.5 text-xs text-gray-600">{t('tasks.reports.by_week_hint')}</p>
            <BarLegend
              items={[
                { className: 'bg-turquesa', label: t('tasks.reports.week_created') },
                { className: 'bg-carbon', label: t('tasks.reports.week_closed') },
              ]}
            />
            <ReportBars
              mode="grouped"
              max={weekMax}
              ariaLabel={t('tasks.reports.by_week')}
              items={weeks.map((w) => ({
                key: w.key,
                label: t('tasks.reports.week_of').replace('{date}', weekLabel(w.start)),
                segments: [
                  { value: w.created, className: 'bg-turquesa', label: t('tasks.reports.week_created') },
                  { value: w.closed, className: 'bg-carbon', label: t('tasks.reports.week_closed') },
                ],
                valueText: `${w.created} / ${w.closed}`,
              }))}
            />
          </section>
          {table}
        </div>
      )}

      {/* La exportación descarga exactamente lo que se ve: mismo conjunto filtrado y mismo orden */}
      <p className="text-xs text-gray-600">
        {t('tasks.reports.export_note')}
      </p>
    </div>
  );
};
