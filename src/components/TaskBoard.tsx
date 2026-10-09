import React, { useState } from 'react';
import { t } from '../lib/i18n';
import { TASK_STATUSES } from '../lib/taskFlow';
import { Task, TaskStatus } from '../types/database';

// Tablero de escritorio y tableta: tres columnas (Pendiente, En curso, Hecha). Se puede arrastrar una
// tarjeta a otra columna, pero el arrastre es un ATAJO: todo lo que hace tiene su botón en la
// tarjeta, de modo que nadie depende de un gesto (teclado, lector de pantalla, ratón torpe).

interface TaskBoardProps {
  groups: Record<TaskStatus, Task[]>;
  renderCard: (task: Task) => React.ReactNode;
  onDropTask: (taskId: string, to: TaskStatus) => void;
}

export const TaskBoard: React.FC<TaskBoardProps> = ({ groups, renderCard, onDropTask }) => {
  const [over, setOver] = useState<TaskStatus | null>(null);

  return (
    <div className="grid grid-cols-3 gap-4" role="group" aria-label={t('tasks.board_label')}>
      {TASK_STATUSES.map((status) => (
        <section
          key={status}
          aria-labelledby={`task-col-${status}`}
          onDragOver={(e) => {
            e.preventDefault();
            setOver(status);
          }}
          onDragLeave={() => setOver((cur) => (cur === status ? null : cur))}
          onDrop={(e) => {
            e.preventDefault();
            setOver(null);
            const id = e.dataTransfer.getData('text/plain');
            if (id) onDropTask(id, status);
          }}
          className={`min-h-48 rounded-xl border p-3 transition ${over === status ? 'border-turquesa bg-claro-surface' : 'border-gray-200 bg-gray-100/60'}`}
        >
          <h3 id={`task-col-${status}`} className="mb-3 flex items-center justify-between text-sm font-bold text-carbon">
            <span>{t(`tasks.status_${status}`)}</span>
            <span className="rounded-full bg-white px-2 py-0.5 font-mono text-xs text-carbon" aria-label={`${groups[status].length}`}>
              {groups[status].length}
            </span>
          </h3>
          {groups[status].length === 0 ? (
            <p className="py-6 text-center text-xs text-gray-600">{t('tasks.column_empty')}</p>
          ) : (
            <ul className="space-y-2.5">{groups[status].map(renderCard)}</ul>
          )}
        </section>
      ))}
    </div>
  );
};
