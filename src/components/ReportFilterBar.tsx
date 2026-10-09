import React, { useId, useState } from 'react';
import { Download, Filter, Link2, X } from 'lucide-react';
import { t } from '../lib/i18n';
import { usePhoneScreen } from '../lib/usePhoneScreen';
import { TASK_STATUSES } from '../lib/taskFlow';
import { PERIODS, Period, ReportFilters, UNASSIGNED } from '../lib/taskReports';

// Barra de filtros ÚNICA del reporte: gobierna el resumen, las agrupaciones y la exportación. En celular
// se pliega a un botón «Filtros»: con seis campos de 44 px la barra ocupaba toda la pantalla y se abría
// «Reportes» sin ver ni una cifra. Se abre sola cuando el enlace ya traía filtros: esconder el motivo por
// el que se ven 12 tareas y no 42 sería cambiar un problema por otro.

interface Option {
  id: string;
  label: string;
}

interface ReportFilterBarProps {
  filters: ReportFilters;
  onChange: (next: ReportFilters) => void;
  people: Option[];
  workAreas: Option[];
  categories: Option[];
  matching: number;
  total: number;
  active: boolean;
  onClear: () => void;
  onExport: () => void;
  onCopyLink: () => void;
}

const SELECT = 'mt-1 block min-h-11 w-full rounded-lg border border-gray-300 bg-white px-3 text-sm focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa';
const BUTTON = 'inline-flex min-h-11 items-center justify-center gap-2 rounded-lg border border-gray-300 bg-white px-3 text-sm font-medium text-gray-700 hover:bg-gray-50';

export const ReportFilterBar: React.FC<ReportFilterBarProps> = ({
  filters,
  onChange,
  people,
  workAreas,
  categories,
  matching,
  total,
  active,
  onClear,
  onExport,
  onCopyLink,
}) => {
  const uid = useId();
  const phone = usePhoneScreen();
  const [open, setOpen] = useState(active);
  const set = (patch: Partial<ReportFilters>) => onChange({ ...filters, ...patch });
  const showFields = !phone || open;

  return (
    <section aria-label={t('tasks.reports.filters')} className="rounded-xl border border-gray-200 bg-white p-3 shadow-sm sm:p-4">
      {phone && (
        <button
          type="button"
          aria-expanded={open}
          aria-controls={`${uid}-fields`}
          onClick={() => setOpen((v) => !v)}
          className={`${BUTTON} w-full justify-between`}
        >
          <span className="inline-flex items-center gap-2">
            <Filter className="h-4 w-4" aria-hidden="true" />
            {t('tasks.reports.filters')}
          </span>
          <span className="text-xs text-gray-600">{t(open ? 'tasks.reports.hide' : 'tasks.reports.show')}</span>
        </button>
      )}

      {showFields && (
        <div id={`${uid}-fields`} className={`grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3 ${phone ? 'mt-3' : ''}`}>
          <label className="block text-xs font-semibold text-gray-700 lg:col-span-1">
            {t('tasks.reports.f_search')}
            <input
              type="search"
              value={filters.search}
              onChange={(e) => set({ search: e.target.value })}
              autoComplete="off"
              className={SELECT}
            />
            <span className="mt-1 block text-xs font-normal text-gray-600">{t('tasks.reports.f_search_hint')}</span>
          </label>
          <label className="block text-xs font-semibold text-gray-700">
            {t('tasks.reports.f_period')}
            <select value={filters.period} onChange={(e) => set({ period: e.target.value as Period })} className={SELECT}>
              {PERIODS.map((p) => (
                <option key={p} value={p}>
                  {t(`tasks.reports.period_${p}`)}
                </option>
              ))}
            </select>
          </label>
          <label className="block text-xs font-semibold text-gray-700">
            {t('tasks.reports.f_person')}
            <select value={filters.person} onChange={(e) => set({ person: e.target.value })} className={SELECT}>
              <option value="">{t('tasks.filter_all')}</option>
              <option value={UNASSIGNED}>{t('tasks.unassigned')}</option>
              {people.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.label}
                </option>
              ))}
            </select>
          </label>
          <label className="block text-xs font-semibold text-gray-700">
            {t('tasks.reports.f_status')}
            <select value={filters.status} onChange={(e) => set({ status: e.target.value as ReportFilters['status'] })} className={SELECT}>
              <option value="">{t('tasks.reports.all_status')}</option>
              {TASK_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {t(`tasks.status_${s}`)}
                </option>
              ))}
            </select>
          </label>
          <label className="block text-xs font-semibold text-gray-700">
            {t('tasks.reports.f_work_area')}
            <select value={filters.workArea} onChange={(e) => set({ workArea: e.target.value })} className={SELECT}>
              <option value="">{t('tasks.reports.all_work_areas')}</option>
              {workAreas.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.label}
                </option>
              ))}
            </select>
          </label>
          <label className="block text-xs font-semibold text-gray-700">
            {t('tasks.reports.f_category')}
            <select value={filters.category} onChange={(e) => set({ category: e.target.value })} className={SELECT}>
              <option value="">{t('tasks.reports.all_categories')}</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.label}
                </option>
              ))}
            </select>
          </label>
        </div>
      )}

      <div className="mt-3 flex flex-col gap-2 border-t border-gray-100 pt-3 sm:flex-row sm:items-center sm:justify-between">
        <p role="status" className="text-sm text-gray-700">
          {t('tasks.reports.matching').replace('{matching}', String(matching)).replace('{total}', String(total))}
        </p>
        <div className="flex flex-wrap gap-2">
          {active && (
            <button type="button" onClick={onClear} className={BUTTON}>
              <X className="h-4 w-4" aria-hidden="true" />
              {t('tasks.reports.clear')}
            </button>
          )}
          <button type="button" onClick={onCopyLink} className={BUTTON}>
            <Link2 className="h-4 w-4" aria-hidden="true" />
            {t('tasks.reports.copy_link')}
          </button>
          <button
            type="button"
            onClick={onExport}
            disabled={matching === 0}
            className="inline-flex min-h-11 items-center justify-center gap-2 rounded-lg bg-turquesa px-3 text-sm font-semibold text-carbon hover:bg-turquesa-hover disabled:opacity-50"
          >
            <Download className="h-4 w-4" aria-hidden="true" />
            {t('tasks.reports.export_csv')}
          </button>
        </div>
      </div>
    </section>
  );
};
