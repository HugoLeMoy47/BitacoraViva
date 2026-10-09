import React, { useState } from 'react';
import { Archive, CalendarClock, Camera, Check, ChevronDown, ChevronUp, Hand, MapPin, Pencil, Play, RotateCcw, Tag, Undo2, User } from 'lucide-react';
import { t } from '../lib/i18n';
import { formatDate } from '../lib/format';
import { Advance, availableAdvance, isOverdue } from '../lib/taskFlow';
import { Task } from '../types/database';

// Tarjeta de tarea. Es la MISMA en el tablero de escritorio y en la lista de celular: cambia el
// contenedor, no lo que la tarjeta ofrece. El título se recorta a dos líneas y el detalle a dos, de
// modo que en un teléfono caben varias tareas por pantalla (con 380 px por tarjeta, catorce
// pendientes eran más de 5 000 px de recorrido).

interface TaskCardProps {
  task: Task;
  assigneeName?: string;
  categoryLabel?: string;
  workAreaLabel?: string;
  hasEvidence: boolean;
  isManagement: boolean;
  busy: boolean;
  /** Se puede arrastrar a otra columna (sólo escritorio) */
  draggable?: boolean;
  onDragStart?: (e: React.DragEvent, task: Task) => void;
  onAdvance: (task: Task, advance: Advance) => void;
  onReopen: (task: Task) => void;
  onEdit: (task: Task) => void;
  onArchive: (task: Task) => void;
  /** Pool: tomar una tarea sin asignar */
  onClaim?: (task: Task) => void;
  /** Pool: soltar lo que la persona tomó por su cuenta y no ha empezado */
  onRelease?: (task: Task) => void;
}

const SECONDARY =
  'inline-flex min-h-11 items-center gap-1.5 rounded-lg border border-gray-300 bg-white px-3 text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:opacity-50';

export const TaskCard: React.FC<TaskCardProps> = ({
  task,
  assigneeName,
  categoryLabel,
  workAreaLabel,
  hasEvidence,
  isManagement,
  busy,
  draggable = false,
  onDragStart,
  onAdvance,
  onReopen,
  onEdit,
  onArchive,
  onClaim,
  onRelease,
}) => {
  const [expanded, setExpanded] = useState(false);
  // Una tarea sin asignar es del pool (Fase 4): aquí no se avanza hasta que alguien la tome
  const advance = task.assigned_to ? availableAdvance(task, { isManagement, hasEvidence }) : null;
  const overdue = isOverdue(task);
  const photoBlocked = !!advance?.needsPhoto;
  const longDetails = (task.details?.length ?? 0) > 80;
  const photoPending = task.photo_required && !hasEvidence && task.status !== 'done';
  const canClaim = !!onClaim && !task.assigned_to && task.status === 'pending';
  // Sólo lo que la persona tomó por su cuenta (claimed_at): lo que asignó coordinación no se devuelve solo
  const canRelease = !!onRelease && !!task.claimed_at && !!task.assigned_to && task.status === 'pending';

  return (
    <li
      draggable={draggable && !busy}
      onDragStart={(e) => onDragStart?.(e, task)}
      className={`rounded-xl border border-gray-200 bg-white p-3.5 shadow-sm ${draggable ? 'cursor-grab active:cursor-grabbing' : ''}`}
    >
      <p className="break-words text-sm font-semibold leading-snug text-carbon">{task.name}</p>

      {task.details && (
        <div className="mt-1">
          <p className={`break-words text-xs text-gray-600 ${expanded ? 'whitespace-pre-line' : 'line-clamp-2'}`}>{task.details}</p>
          {longDetails && (
            <button
              type="button"
              onClick={() => setExpanded((v) => !v)}
              aria-expanded={expanded}
              className="inline-flex min-h-11 items-center gap-1 text-xs font-semibold text-turquesa-dark hover:underline"
            >
              {expanded ? <ChevronUp className="h-3.5 w-3.5" aria-hidden="true" /> : <ChevronDown className="h-3.5 w-3.5" aria-hidden="true" />}
              {t(expanded ? 'tasks.details_hide' : 'tasks.details_show')}
            </button>
          )}
        </div>
      )}

      {photoPending && (
        <p className="mt-2 flex items-center gap-1.5 rounded-lg border border-amber-200 bg-amber-50 px-2.5 py-1 text-xs font-medium text-amber-900">
          <Camera className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
          <span>{t('tasks.photo_required_note')}</span>
        </p>
      )}

      <div className="mt-2.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-gray-600">
        {categoryLabel && (
          <span className="inline-flex max-w-full items-center gap-1">
            <Tag className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
            <span className="truncate">{categoryLabel}</span>
          </span>
        )}
        {workAreaLabel && (
          <span className="inline-flex max-w-full items-center gap-1">
            <MapPin className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
            <span className="truncate">{workAreaLabel}</span>
          </span>
        )}
        {task.due_at && (
          <span className={`inline-flex items-center gap-1 ${overdue ? 'font-semibold text-alerta-dark' : ''}`}>
            <CalendarClock className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
            {t(overdue ? 'tasks.overdue' : 'tasks.due').replace('{date}', formatDate(task.due_at))}
          </span>
        )}
        {isManagement && (
          <span className="inline-flex max-w-full items-center gap-1">
            <User className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
            <span className="truncate">{assigneeName || t('tasks.unassigned')}</span>
          </span>
        )}
      </div>

      <div className="mt-3 flex flex-wrap items-center gap-2">
        {canClaim && (
          <button
            type="button"
            onClick={() => onClaim?.(task)}
            disabled={busy}
            className="inline-flex min-h-11 items-center gap-1.5 rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon hover:bg-turquesa-hover disabled:opacity-50"
          >
            <Hand className="h-4 w-4" aria-hidden="true" />
            {t('tasks.pool.take')}
          </button>
        )}
        {advance && (
          <button
            type="button"
            onClick={() => onAdvance(task, advance)}
            disabled={busy || photoBlocked}
            className="inline-flex min-h-11 items-center gap-1.5 rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon hover:bg-turquesa-hover disabled:opacity-50"
          >
            {advance.needsPhoto ? (
              <Camera className="h-4 w-4" aria-hidden="true" />
            ) : advance.to === 'in_progress' ? (
              <Play className="h-4 w-4" aria-hidden="true" />
            ) : (
              <Check className="h-4 w-4" aria-hidden="true" />
            )}
            {t(advance.labelKey)}
          </button>
        )}
        {canRelease && (
          <button type="button" onClick={() => onRelease?.(task)} disabled={busy} className={SECONDARY}>
            <Undo2 className="h-4 w-4" aria-hidden="true" />
            {t('tasks.pool.release')}
          </button>
        )}
        {isManagement && task.status === 'done' && (
          <button type="button" onClick={() => onReopen(task)} disabled={busy} className={SECONDARY}>
            <RotateCcw className="h-4 w-4" aria-hidden="true" />
            {t('tasks.action_reopen')}
          </button>
        )}
        {isManagement && (
          <>
            <button type="button" onClick={() => onEdit(task)} disabled={busy} className={SECONDARY}>
              <Pencil className="h-4 w-4" aria-hidden="true" />
              {t('tasks.action_edit')}
            </button>
            <button type="button" onClick={() => onArchive(task)} disabled={busy} className={SECONDARY}>
              <Archive className="h-4 w-4" aria-hidden="true" />
              {t('tasks.action_archive')}
            </button>
          </>
        )}
      </div>

      {photoBlocked && <p className="mt-2 text-xs text-amber-900">{t('tasks.photo_unavailable')}</p>}
    </li>
  );
};
