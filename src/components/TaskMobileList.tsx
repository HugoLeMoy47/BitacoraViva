import React from 'react';
import { Coffee, Star } from 'lucide-react';
import { t } from '../lib/i18n';
import { TASK_STATUSES } from '../lib/taskFlow';
import { Task, TaskStatus } from '../types/database';

// El tablero, para un teléfono: una columna a la vez y el avance por botón en la tarjeta.
// No es un tablero con columnas más angostas (tres de 220 px no entran en 360 y a 160 el texto deja
// de caber); lo que no sobrevive a la pantalla chica es el modelo de interacción, porque arrastrar
// presupone ver origen y destino a la vez. Un toque con el destino escrito en el botón es más
// rápido que cualquier tablero, también con una sola mano.

interface TaskMobileListProps {
  groups: Record<TaskStatus, Task[]>;
  active: TaskStatus;
  onChangeActive: (status: TaskStatus) => void;
  renderCard: (task: Task) => React.ReactNode;
  /** Quien no gestiona y ya terminó todo recibe un mensaje de logro en lugar de una lista vacía */
  isManagement: boolean;
}

export const TaskMobileList: React.FC<TaskMobileListProps> = ({ groups, active, onChangeActive, renderCard, isManagement }) => {
  const openCount = groups.pending.length + groups.in_progress.length;
  const nothing = openCount === 0 && groups.done.length === 0;
  const allDone = !isManagement && openCount === 0 && groups.done.length > 0;
  const list = groups[active];

  return (
    <div>
      {/* Botones con aria-pressed y no pestañas: lo que hacen es filtrar la lista de abajo */}
      <div role="group" aria-label={t('tasks.filter_status')} className="mb-4 grid grid-cols-3 gap-1 rounded-xl bg-gray-100 p-1">
        {TASK_STATUSES.map((status) => {
          const selected = status === active;
          return (
            <button
              key={status}
              type="button"
              aria-pressed={selected}
              onClick={() => onChangeActive(status)}
              className={`flex min-h-11 flex-col items-center justify-center rounded-lg px-1 leading-tight transition ${
                selected ? 'bg-white text-carbon shadow-sm' : 'text-gray-600 hover:text-carbon'
              }`}
            >
              <span className="text-sm font-semibold">{t(`tasks.status_${status}`)}</span>
              <span className={`font-mono text-xs ${selected ? 'font-bold text-turquesa-dark' : 'text-gray-600'}`}>{groups[status].length}</span>
            </button>
          );
        })}
      </div>

      {list.length > 0 ? (
        <ul className="space-y-2.5">{list.map(renderCard)}</ul>
      ) : allDone ? (
        <div className="px-4 py-10 text-center">
          <Star className="mx-auto mb-2 h-8 w-8 text-turquesa-dark" aria-hidden="true" />
          <p className="text-sm font-semibold text-carbon">{t('tasks.all_done_title')}</p>
          <p className="mx-auto mt-1 max-w-xs text-xs text-gray-600">{t('tasks.all_done_body')}</p>
        </div>
      ) : nothing ? (
        <div className="px-4 py-10 text-center">
          <Coffee className="mx-auto mb-2 h-8 w-8 text-turquesa-dark" aria-hidden="true" />
          <p className="text-sm font-semibold text-carbon">{t(isManagement ? 'tasks.empty_manager_title' : 'tasks.empty_member_title')}</p>
          <p className="mx-auto mt-1 max-w-xs text-xs text-gray-600">{t(isManagement ? 'tasks.empty_manager_body' : 'tasks.empty_member_body')}</p>
        </div>
      ) : (
        <p className="py-10 text-center text-sm text-gray-600">{t('tasks.empty_status')}</p>
      )}
    </div>
  );
};
