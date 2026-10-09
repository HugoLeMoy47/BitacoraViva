import React, { useId, useState } from 'react';
import { ChevronDown, ChevronUp, HandHeart } from 'lucide-react';
import { t } from '../lib/i18n';
import { Task } from '../types/database';

// Pool de tareas abiertas (BV-7.10): trabajo sin asignar que cualquier persona del equipo puede tomar.
// Un voluntario no debería esperar a que alguien le diga qué hacer. Al abrirlo se devuelve al pool lo
// que alguien tomó y no empezó dentro del plazo de la organización: quien va a tomar una tarea es
// justo quien se beneficia de que lo abandonado ya esté libre (sin depender de un programador de tareas).
//
// Consecuencia que conviene entender: tomar una tarea la esconde del resto del equipo. De ahí el tope
// opcional, la devolución automática y el botón «Soltar» (el pulgar se equivoca, con una sola mano).

interface PoolPanelProps {
  tasks: Task[];
  renderCard: (task: Task) => React.ReactNode;
  /** Se llama al abrir, para devolver lo vencido y releer */
  onOpen: () => void;
}

export const PoolPanel: React.FC<PoolPanelProps> = ({ tasks, renderCard, onOpen }) => {
  const uid = useId();
  const [open, setOpen] = useState(false);

  const toggle = () => {
    if (!open) onOpen();
    setOpen((v) => !v);
  };

  return (
    <section className="mb-5 rounded-2xl border border-gray-200 bg-white shadow-sm">
      <h3>
        <button
          type="button"
          onClick={toggle}
          aria-expanded={open}
          aria-controls={`${uid}-panel`}
          className="flex min-h-14 w-full items-center justify-between gap-3 rounded-2xl px-4 py-3 text-left"
        >
          <span className="flex items-center gap-2 text-sm font-bold text-carbon">
            <HandHeart className="h-5 w-5 text-turquesa-dark" aria-hidden="true" />
            {t('tasks.pool.title')}
            <span className="rounded-full bg-gray-100 px-2 py-0.5 font-mono text-xs text-carbon" aria-label={String(tasks.length)}>
              {tasks.length}
            </span>
          </span>
          {open ? <ChevronUp className="h-4 w-4 text-gray-600" aria-hidden="true" /> : <ChevronDown className="h-4 w-4 text-gray-600" aria-hidden="true" />}
        </button>
      </h3>
      {open && (
        <div id={`${uid}-panel`} className="border-t border-gray-100 px-4 pb-4 pt-3">
          <p className="mb-3 text-xs text-gray-600">{t('tasks.pool.hint')}</p>
          {tasks.length === 0 ? (
            <p className="rounded-lg border border-dashed border-gray-300 px-3 py-6 text-center text-sm text-gray-600">{t('tasks.pool.empty')}</p>
          ) : (
            <ul className="space-y-2.5">{tasks.map(renderCard)}</ul>
          )}
        </div>
      )}
    </section>
  );
};
