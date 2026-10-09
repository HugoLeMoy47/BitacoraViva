import React from 'react';
import { PlayCircle, X } from 'lucide-react';
import { t } from '../lib/i18n';
import { RoutineTemplate, RoutineTemplateItem } from '../types/database';
import { ModalShell } from './ModalShell';

// Iniciar el turno (BV-7.11): se elige una rutina y se reciben de golpe sus tareas, ya asignadas a quien
// la inicia. Una vez por rutina y por día: la base lo exige (un reintento de red o dos aparatos abiertos
// no duplican la jornada de nadie).

interface StartRoutineModalProps {
  routines: RoutineTemplate[];
  items: RoutineTemplateItem[];
  busyId: string | null;
  onStart: (id: string) => void;
  onClose: () => void;
}

export const StartRoutineModal: React.FC<StartRoutineModalProps> = ({ routines, items, busyId, onStart, onClose }) => (
  <ModalShell onClose={onClose} className="fixed inset-0 z-50 flex items-center justify-center bg-carbon/60 p-4 backdrop-blur-sm">
    <div className="flex max-h-[90vh] w-full max-w-lg flex-col rounded-xl bg-white shadow-2xl">
      <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4">
        <div className="flex items-center gap-2">
          <PlayCircle className="h-5 w-5 text-turquesa-dark" aria-hidden="true" />
          <h3 className="text-base font-bold text-carbon">{t('tasks.routines.start_title')}</h3>
        </div>
        <button type="button" onClick={onClose} aria-label={t('common.close')} className="flex h-11 w-11 items-center justify-center rounded-lg text-gray-600 hover:bg-gray-100">
          <X className="h-5 w-5" aria-hidden="true" />
        </button>
      </div>

      <div className="space-y-3 overflow-y-auto px-6 py-5">
        <p className="text-xs text-gray-600">{t('tasks.routines.start_hint')}</p>
        {routines.length === 0 ? (
          <p className="rounded-lg border border-dashed border-gray-300 px-3 py-6 text-center text-sm text-gray-600">{t('tasks.routines.start_empty')}</p>
        ) : (
          <ul className="space-y-2.5">
            {routines.map((r) => {
              const count = items.filter((i) => i.routine_template_id === r.id && !i.archived_at).length;
              return (
                <li key={r.id} className="rounded-xl border border-gray-200 p-3.5">
                  <p className="break-words text-sm font-semibold text-carbon">{r.name}</p>
                  {r.description && <p className="mt-0.5 break-words text-xs text-gray-600">{r.description}</p>}
                  <div className="mt-3 flex flex-wrap items-center justify-between gap-2">
                    <span className="text-xs text-gray-600">{t('tasks.routines.step_count').replace('{n}', String(count))}</span>
                    <button
                      type="button"
                      onClick={() => onStart(r.id)}
                      disabled={busyId === r.id || count === 0}
                      className="inline-flex min-h-11 items-center gap-2 rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon hover:bg-turquesa-hover disabled:opacity-50"
                    >
                      <PlayCircle className="h-4 w-4" aria-hidden="true" />
                      {t('tasks.routines.start')}
                    </button>
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </div>
  </ModalShell>
);
