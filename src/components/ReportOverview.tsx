import React from 'react';
import { t } from '../lib/i18n';
import { GroupRow, GlobalMetrics, PersonMetrics, RecurringTask, StatusCounts } from '../lib/taskReports';
import { BarItem, BarLegend, ReportBars } from './ReportBars';

// Resumen: cuánto hay, cuánto se atora y dónde. Responde lo que un listado no contesta: qué proporción
// está cerrada, cuántas van vencidas, cuánto tarda una tarea de alta a cierre, cómo se reparte el
// trabajo y —el punto del tablero de flujo— dónde se espera y dónde se trabaja.

const SEG = {
  pending: { className: 'bg-gray-400', key: 'pending' as const },
  in_progress: { className: 'bg-turquesa', key: 'in_progress' as const },
  done: { className: 'bg-turquesa-dark', key: 'done' as const },
};

const days = (value: number | null): string =>
  value === null ? t('tasks.reports.no_data') : t('tasks.reports.days').replace('{n}', value.toLocaleString('es-MX', { maximumFractionDigits: 1 }));

export const statusSegments = (c: StatusCounts) =>
  (['pending', 'in_progress', 'done'] as const).map((s) => ({ value: c[s], className: SEG[s].className, label: t(`tasks.status_${s}`) }));

export const statusLegend = (['pending', 'in_progress', 'done'] as const).map((s) => ({ className: SEG[s].className, label: t(`tasks.status_${s}`) }));

export const groupItems = (rows: GroupRow[]): BarItem[] =>
  rows.map((r) => ({
    key: r.key || 'none',
    label: r.name,
    segments: statusSegments(r.counts),
    valueText: `${r.counts.pending} · ${r.counts.in_progress} · ${r.counts.done}`,
  }));

const Tile: React.FC<{ label: string; value: React.ReactNode; tone?: 'alert' }> = ({ label, value, tone }) => (
  <div className="rounded-xl border border-gray-200 bg-white p-3.5 shadow-sm">
    <dt className="text-xs font-medium text-gray-600">{label}</dt>
    <dd className={`mt-1 text-2xl font-bold ${tone === 'alert' ? 'text-alerta-dark' : 'text-carbon'}`}>{value}</dd>
  </div>
);

const Card: React.FC<{ title: string; hint?: string; children: React.ReactNode }> = ({ title, hint, children }) => (
  <section className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm sm:p-5">
    <h3 className="text-base font-bold text-carbon">{title}</h3>
    {hint && <p className="mb-3 mt-0.5 text-xs text-gray-600">{hint}</p>}
    {!hint && <div className="mb-3" />}
    {children}
  </section>
);

interface ReportOverviewProps {
  metrics: GlobalMetrics;
  people: GroupRow[];
  personTimes: PersonMetrics[];
  recurring: RecurringTask[];
  byCategory: GroupRow[];
  byWorkArea: GroupRow[];
}

export const ReportOverview: React.FC<ReportOverviewProps> = ({ metrics, people, personTimes, recurring, byCategory, byWorkArea }) => {
  const timedPeople = personTimes.filter((p) => p.cycle !== null);
  const maxCycle = Math.max(0.1, ...timedPeople.map((p) => p.cycle ?? 0));

  return (
    <div className="space-y-4">
      <dl className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-6">
        <Tile label={t('tasks.reports.kpi_total')} value={metrics.total} />
        <Tile label={t('tasks.status_pending')} value={metrics.pending} />
        <Tile label={t('tasks.status_in_progress')} value={metrics.inProgress} />
        <Tile label={t('tasks.status_done')} value={metrics.done} />
        <Tile label={t('tasks.reports.kpi_overdue')} value={metrics.overdue} tone={metrics.overdue > 0 ? 'alert' : undefined} />
        <Tile label={t('tasks.reports.kpi_percent')} value={`${metrics.percentDone} %`} />
      </dl>

      <Card title={t('tasks.reports.flow_title')} hint={t('tasks.reports.flow_hint')}>
        <dl className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <Tile label={t('tasks.reports.flow_wait')} value={days(metrics.waitMean)} />
          <Tile label={t('tasks.reports.flow_work')} value={days(metrics.workMean)} />
          <Tile label={t('tasks.reports.flow_total')} value={days(metrics.totalMean)} />
        </dl>
        {metrics.unmeasured > 0 && (
          <p className="mt-3 rounded-lg border border-amber-200 bg-amber-50 p-2.5 text-xs text-amber-900">
            {t('tasks.reports.unmeasured').replace('{n}', String(metrics.unmeasured))}
          </p>
        )}
      </Card>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Card title={t('tasks.reports.load_person')} hint={t('tasks.reports.load_hint')}>
          <BarLegend items={statusLegend} />
          <ReportBars items={groupItems(people)} ariaLabel={t('tasks.reports.load_person')} />
        </Card>

        <Card title={t('tasks.reports.time_person')} hint={t('tasks.reports.time_hint')}>
          {timedPeople.length === 0 ? (
            <p className="text-sm text-gray-600">{t('tasks.reports.no_data')}</p>
          ) : (
            <>
              <BarLegend items={[{ className: 'bg-gray-400', label: t('tasks.reports.flow_wait') }, { className: 'bg-carbon', label: t('tasks.reports.flow_work') }]} />
              <ReportBars
                max={maxCycle}
                ariaLabel={t('tasks.reports.time_person')}
                items={timedPeople.map((p) => ({
                  key: p.key,
                  label: p.name,
                  segments: [
                    { value: p.wait ?? 0, className: 'bg-gray-400', label: t('tasks.reports.flow_wait') },
                    { value: p.work ?? 0, className: 'bg-carbon', label: t('tasks.reports.flow_work') },
                  ],
                  valueText: days(p.cycle),
                }))}
              />
            </>
          )}
        </Card>

        <Card title={t('tasks.reports.load_category')}>
          <BarLegend items={statusLegend} />
          <ReportBars items={groupItems(byCategory)} ariaLabel={t('tasks.reports.load_category')} />
        </Card>

        <Card title={t('tasks.reports.load_work_area')}>
          <BarLegend items={statusLegend} />
          <ReportBars items={groupItems(byWorkArea)} ariaLabel={t('tasks.reports.load_work_area')} />
        </Card>
      </div>

      <Card title={t('tasks.reports.recurring_title')} hint={t('tasks.reports.recurring_hint')}>
        {recurring.length === 0 ? (
          <p className="text-sm text-gray-600">{t('tasks.reports.recurring_none')}</p>
        ) : (
          <ul className="divide-y divide-gray-100">
            {recurring.slice(0, 8).map((r) => (
              <li key={r.name} className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-0.5 py-2 text-sm">
                <span className="min-w-0 break-words font-medium text-carbon">{r.name}</span>
                <span className="text-xs text-gray-600">
                  {t('tasks.reports.recurring_row').replace('{times}', String(r.times)).replace('{done}', String(r.done)).replace('{avg}', days(r.totalMean))}
                </span>
              </li>
            ))}
          </ul>
        )}
      </Card>
    </div>
  );
};
