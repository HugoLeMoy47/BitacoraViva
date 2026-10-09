import React from 'react';
import { Coffee, PartyPopper } from 'lucide-react';
import { t } from '../lib/i18n';
import { Progress } from '../lib/taskFlow';

// Avance de la jornada de quien recibe tareas. Sentido de logro, nunca competencia: no hay
// ranking ni comparación con otras personas; sólo lo propio, dicho con calidez.

interface VolunteerProgressProps {
  progress: Progress;
  /** Nombre completo; se usa el primero */
  fullName: string;
  organizationName: string;
}

const fill = (key: string, values: Record<string, string | number>): string =>
  Object.entries(values).reduce((text, [k, v]) => text.replace(`{${k}}`, String(v)), t(key));

export const VolunteerProgress: React.FC<VolunteerProgressProps> = ({ progress, fullName, organizationName }) => {
  const name = fullName.split(/\s+/)[0] || '';

  if (progress.total === 0) {
    return (
      <div className="mb-5 rounded-2xl border border-claro bg-claro-surface p-4 text-center">
        <Coffee className="mx-auto mb-1 h-6 w-6 text-turquesa-dark" aria-hidden="true" />
        <p className="text-sm font-semibold text-carbon">{fill('tasks.progress_empty_title', { name })}</p>
        <p className="mx-auto mt-1 max-w-md text-xs text-gray-600">{t('tasks.progress_empty_body')}</p>
      </div>
    );
  }

  if (progress.allDone) {
    return (
      <div className="mb-5 rounded-2xl border border-turquesa/40 bg-claro-surface p-4 shadow-sm sm:p-5">
        <div className="flex items-start gap-3">
          <PartyPopper className="mt-0.5 h-7 w-7 shrink-0 text-turquesa-dark" aria-hidden="true" />
          <div>
            <p className="text-base font-bold text-carbon">{fill('tasks.progress_complete_title', { name })}</p>
            <p className="mt-1 text-sm text-carbon-muted">{fill('tasks.progress_complete_body', { total: progress.total, organization: organizationName })}</p>
            <p className="mt-3 inline-flex items-center rounded-full bg-claro px-3 py-1 text-xs font-semibold text-carbon">{t('tasks.progress_complete_badge')}</p>
          </div>
        </div>
      </div>
    );
  }

  const remaining = progress.total - progress.done;
  const message =
    progress.done === 0
      ? progress.total === 1
        ? t('tasks.progress_one')
        : fill('tasks.progress_many', { total: progress.total })
      : remaining === 1
        ? t('tasks.progress_almost')
        : progress.percent >= 50
          ? fill('tasks.progress_half', { done: progress.done, total: progress.total, percent: progress.percent })
          : fill('tasks.progress_begin', { done: progress.done, total: progress.total });

  return (
    <div className="mb-5 rounded-2xl border border-gray-200 bg-white p-4 shadow-sm">
      <div className="mb-2 flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p className="text-sm font-bold text-carbon">{fill('tasks.progress_hello', { name })}</p>
          <p className="mt-0.5 text-xs text-gray-600">{message}</p>
        </div>
        <p className="text-xs font-semibold text-turquesa-dark">
          {fill('tasks.progress_summary', { done: progress.done, total: progress.total, percent: progress.percent })}
        </p>
      </div>
      <div
        className="h-3 w-full overflow-hidden rounded-full bg-gray-100"
        role="progressbar"
        aria-valuenow={progress.percent}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-label={t('tasks.progress_label')}
      >
        <div className="h-full rounded-full bg-turquesa transition-all duration-500 ease-out motion-reduce:transition-none" style={{ width: `${progress.percent}%` }} />
      </div>
    </div>
  );
};
