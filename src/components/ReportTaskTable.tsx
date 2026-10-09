import React, { useState } from 'react';
import { ArrowDown, ArrowUp, ArrowUpDown } from 'lucide-react';
import { t } from '../lib/i18n';
import { formatDate } from '../lib/format';
import { usePhoneScreen } from '../lib/usePhoneScreen';
import { SORT_FIELDS, SortField, SortState } from '../lib/taskReports';
import { Task } from '../types/database';

// Listado de tareas del reporte, ordenable por columna. En pantallas de escritorio es una tabla; por
// debajo de 640 px, una lista de fichas donde cada dato lleva su etiqueta: cuatro columnas con nombres
// de tarea largos no caben en 254 px a un tamaño que se lea, y una tabla que se desplaza de lado
// esconde columnas sin avisar.

interface ReportTaskTableProps {
  tasks: Task[];
  sort: SortState;
  onSort: (next: SortState) => void;
  personName: (id: string | null) => string;
  categoryLabel: (id: string | null) => string;
  workAreaLabel: (id: string | null) => string;
}

const PAGE = 50;

const StatusChip: React.FC<{ status: Task['status'] }> = ({ status }) => (
  <span
    className={`inline-block whitespace-nowrap rounded-full px-2 py-0.5 text-xs font-semibold ${
      status === 'done' ? 'bg-claro text-carbon' : status === 'in_progress' ? 'bg-turquesa/25 text-carbon' : 'bg-gray-100 text-carbon'
    }`}
  >
    {t(`tasks.status_${status}`)}
  </span>
);

const COLUMNS: SortField[] = ['task', 'status', 'person', 'category', 'workArea', 'created', 'due', 'done'];

export const ReportTaskTable: React.FC<ReportTaskTableProps> = ({ tasks, sort, onSort, personName, categoryLabel, workAreaLabel }) => {
  const phone = usePhoneScreen();
  const [limit, setLimit] = useState(PAGE);
  const shown = tasks.slice(0, limit);

  // Primer clic: orden por omisión del campo; segundo: invierte. Fechas arrancan de más nueva a más vieja
  // y el texto de la A a la Z, porque es lo que se busca en cada caso.
  const toggle = (field: SortField) => {
    if (sort.field === field) onSort({ field, direction: sort.direction === 'asc' ? 'desc' : 'asc' });
    else onSort({ field, direction: field === 'created' || field === 'due' || field === 'done' ? 'desc' : 'asc' });
  };

  const more =
    tasks.length > limit ? (
      <button
        type="button"
        onClick={() => setLimit((n) => n + PAGE)}
        className="mt-3 inline-flex min-h-11 items-center rounded-lg border border-gray-300 bg-white px-4 text-sm font-medium text-gray-700 hover:bg-gray-50"
      >
        {t('tasks.reports.show_more').replace('{n}', String(Math.min(PAGE, tasks.length - limit)))}
      </button>
    ) : null;

  if (tasks.length === 0) {
    return <p className="rounded-xl border border-dashed border-gray-300 bg-white px-4 py-8 text-center text-sm text-gray-600">{t('tasks.reports.no_results')}</p>;
  }

  if (phone) {
    return (
      <div>
        <div className="mb-3 flex gap-2">
          <label className="block flex-1 text-xs font-semibold text-gray-700">
            {t('tasks.reports.sort_by')}
            <select
              value={sort.field}
              onChange={(e) => onSort({ field: e.target.value as SortField, direction: sort.direction })}
              className="mt-1 block min-h-11 w-full rounded-lg border border-gray-300 bg-white px-3 text-sm"
            >
              {SORT_FIELDS.map((f) => (
                <option key={f} value={f}>
                  {t(`tasks.reports.col_${f}`)}
                </option>
              ))}
            </select>
          </label>
          <button
            type="button"
            onClick={() => onSort({ field: sort.field, direction: sort.direction === 'asc' ? 'desc' : 'asc' })}
            aria-label={t(sort.direction === 'asc' ? 'tasks.reports.sort_asc' : 'tasks.reports.sort_desc')}
            className="mt-5 flex min-h-11 min-w-11 items-center justify-center rounded-lg border border-gray-300 bg-white text-gray-700"
          >
            {sort.direction === 'asc' ? <ArrowUp className="h-4 w-4" aria-hidden="true" /> : <ArrowDown className="h-4 w-4" aria-hidden="true" />}
          </button>
        </div>
        <ul className="space-y-2.5">
          {shown.map((task) => (
            <li key={task.id} className="rounded-xl border border-gray-200 bg-white p-3.5 shadow-sm">
              <div className="flex items-start justify-between gap-2">
                <p className="break-words text-sm font-semibold text-carbon">{task.name}</p>
                <StatusChip status={task.status} />
              </div>
              <dl className="mt-2 grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5 text-xs">
                <dt className="text-gray-600">{t('tasks.reports.col_person')}</dt>
                <dd className="text-carbon">{personName(task.assigned_to)}</dd>
                <dt className="text-gray-600">{t('tasks.reports.col_category')}</dt>
                <dd className="text-carbon">{categoryLabel(task.task_category_id)}</dd>
                <dt className="text-gray-600">{t('tasks.reports.col_workArea')}</dt>
                <dd className="text-carbon">{workAreaLabel(task.work_area_id)}</dd>
                <dt className="text-gray-600">{t('tasks.reports.col_created')}</dt>
                <dd className="text-carbon">{formatDate(task.created_at)}</dd>
                {task.due_at && (
                  <>
                    <dt className="text-gray-600">{t('tasks.reports.col_due')}</dt>
                    <dd className="text-carbon">{formatDate(task.due_at)}</dd>
                  </>
                )}
                {task.done_at && (
                  <>
                    <dt className="text-gray-600">{t('tasks.reports.col_done')}</dt>
                    <dd className="text-carbon">{formatDate(task.done_at)}</dd>
                  </>
                )}
              </dl>
            </li>
          ))}
        </ul>
        {more}
      </div>
    );
  }

  return (
    <div>
      {/* Sin ancho mínimo ni desplazamiento lateral: lo que se desplaza de lado esconde columnas sin avisar */}
      <div className="rounded-xl border border-gray-200 bg-white shadow-sm">
        <table className="w-full text-left text-sm">
          <thead className="border-b border-gray-200 bg-gray-50 text-xs text-gray-700">
            <tr>
              {COLUMNS.map((field) => {
                const active = sort.field === field;
                return (
                  <th
                    key={field}
                    scope="col"
                    aria-sort={active ? (sort.direction === 'asc' ? 'ascending' : 'descending') : 'none'}
                    className="px-3 py-1 font-semibold"
                  >
                    <button
                      type="button"
                      onClick={() => toggle(field)}
                      className="inline-flex min-h-11 items-center gap-1 rounded px-1 text-left hover:text-carbon"
                    >
                      {t(`tasks.reports.col_${field}`)}
                      {active ? (
                        sort.direction === 'asc' ? <ArrowUp className="h-3.5 w-3.5" aria-hidden="true" /> : <ArrowDown className="h-3.5 w-3.5" aria-hidden="true" />
                      ) : (
                        <ArrowUpDown className="h-3.5 w-3.5 text-gray-500" aria-hidden="true" />
                      )}
                    </button>
                  </th>
                );
              })}
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {shown.map((task) => (
              <tr key={task.id} className="align-top">
                <td className="max-w-xs break-words px-3 py-2.5 font-medium text-carbon">{task.name}</td>
                <td className="px-3 py-2.5">
                  <StatusChip status={task.status} />
                </td>
                <td className="px-3 py-2.5 text-carbon">{personName(task.assigned_to)}</td>
                <td className="px-3 py-2.5 text-carbon">{categoryLabel(task.task_category_id)}</td>
                <td className="px-3 py-2.5 text-carbon">{workAreaLabel(task.work_area_id)}</td>
                <td className="whitespace-nowrap px-3 py-2.5 text-carbon">{formatDate(task.created_at)}</td>
                <td className="whitespace-nowrap px-3 py-2.5 text-carbon">{formatDate(task.due_at)}</td>
                <td className="whitespace-nowrap px-3 py-2.5 text-carbon">{formatDate(task.done_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {more}
    </div>
  );
};
