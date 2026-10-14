import React, { useId, useState } from 'react';
import { ArrowLeft, CheckCircle2 } from 'lucide-react';
import { t } from '../lib/i18n';
import { TaskInput } from '../lib/tasks';
import { Task, TaskCategory, WorkArea } from '../types/database';
import { DiscardConfirm, useBeforeUnloadGuard } from './LeaveGuard';
import { DisabledReason, describedBy } from './DisabledReason';

// Alta y edición de una tarea (gestión de tareas), como PÁGINA (no modal): son siete campos. La base vuelve a exigir
// quién puede hacerlo.

interface TaskFormPageProps {
  /** Tarea a editar; nula para una nueva */
  task: Task | null;
  categories: TaskCategory[];
  workAreas: WorkArea[];
  /** Personas a quienes se puede asignar, ya con su nombre */
  assignees: { id: string; name: string }[];
  busy: boolean;
  /** Vuelve al tablero (se llama tras confirmar si había cambios sin guardar) */
  onCancel: () => void;
  onSubmit: (input: TaskInput) => void;
}

const FIELD = 'mt-1 w-full min-h-11 rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa';
const LABEL = 'block text-sm font-semibold text-gray-700';

export const TaskFormPage: React.FC<TaskFormPageProps> = ({ task, categories, workAreas, assignees, busy, onCancel, onSubmit }) => {
  const uid = useId();
  const [name, setName] = useState(task?.name ?? '');
  const [details, setDetails] = useState(task?.details ?? '');
  const [categoryId, setCategoryId] = useState(task?.task_category_id ?? '');
  const [workAreaId, setWorkAreaId] = useState(task?.work_area_id ?? '');
  const [assignedTo, setAssignedTo] = useState(task?.assigned_to ?? '');
  const [dueAt, setDueAt] = useState(task?.due_at ?? '');
  const [photoRequired, setPhotoRequired] = useState(task?.photo_required ?? false);

  // ¿Hay cambios sin guardar? Al salir se pide confirmación
  const dirty =
    name !== (task?.name ?? '') ||
    details !== (task?.details ?? '') ||
    categoryId !== (task?.task_category_id ?? '') ||
    workAreaId !== (task?.work_area_id ?? '') ||
    assignedTo !== (task?.assigned_to ?? '') ||
    dueAt !== (task?.due_at ?? '') ||
    photoRequired !== (task?.photo_required ?? false);
  const [confirmingLeave, setConfirmingLeave] = useState(false);
  useBeforeUnloadGuard(dirty);
  const leave = () => (dirty ? setConfirmingLeave(true) : onCancel());

  // Una tarea ligada a un caso no tiene texto libre: su nombre sale de un catálogo (decisión 6a)
  const linked = !!task?.case_id;
  const valid = name.trim().length > 0 && name.trim().length <= 120 && details.length <= 1000;
  const saveReason = name.trim().length === 0 ? t('tasks.reason_name') : name.trim().length > 120 ? t('tasks.reason_name_long') : details.length > 1000 ? t('tasks.reason_details_long') : null;

  // Si la persona asignada hoy ya no figura entre quienes reciben tareas, se conserva su opción
  const assigneeOptions =
    task?.assigned_to && !assignees.some((a) => a.id === task.assigned_to)
      ? [...assignees, { id: task.assigned_to, name: t('tasks.assignee_former') }]
      : assignees;

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!valid || busy) return;
    onSubmit({
      name: name.trim(),
      details: linked ? null : details.trim() || null,
      task_category_id: categoryId || null,
      work_area_id: workAreaId || null,
      assigned_to: assignedTo || null,
      due_at: dueAt || null,
      photo_required: photoRequired,
    });
  };

  return (
    <div className="mx-auto max-w-3xl space-y-5">
      <div>
        <button type="button" onClick={leave} className="inline-flex min-h-11 items-center gap-1.5 text-sm font-semibold text-turquesa-dark hover:underline">
          <ArrowLeft className="h-4 w-4" aria-hidden="true" />
          {t('tasks.page.back_to_board')}
        </button>
        <h2 className="font-title text-2xl font-bold text-carbon">{t(task ? 'tasks.form_title_edit' : 'tasks.form_title_new')}</h2>
      </div>

      <form onSubmit={submit} className="space-y-5">
        <div className="space-y-4 rounded-2xl border border-gray-200 bg-white p-5">
          <div>
            <label htmlFor={`${uid}-name`} className={LABEL}>
              {t('tasks.f_name')}
            </label>
            <input
              id={`${uid}-name`}
              type="text"
              required
              maxLength={120}
              value={name}
              readOnly={linked}
              onChange={(e) => setName(e.target.value)}
              className={`${FIELD}${linked ? ' bg-gray-50 text-gray-700' : ''}`}
            />
            <p className="mt-1 text-xs text-gray-600">{linked ? t('tasks.case.name_locked') : t('tasks.f_name_hint')}</p>
          </div>

          {!linked && (
          <div>
            <label htmlFor={`${uid}-details`} className={LABEL}>
              {t('tasks.f_details')}
            </label>
            <textarea
              id={`${uid}-details`}
              rows={4}
              maxLength={1000}
              value={details}
              onChange={(e) => setDetails(e.target.value)}
              className={FIELD}
            />
            {/* Riesgo R-17: el texto libre lo lee el voluntariado, que no tiene acceso al expediente */}
            <p className="mt-1 text-xs text-amber-900">{t('tasks.f_details_warning')}</p>
          </div>
          )}

          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div>
              <label htmlFor={`${uid}-category`} className={LABEL}>
                {t('tasks.f_category')}
              </label>
              <select id={`${uid}-category`} value={categoryId} onChange={(e) => setCategoryId(e.target.value)} className={FIELD}>
                <option value="">{t('tasks.f_none')}</option>
                {categories.filter((c) => !c.archived_at || c.id === task?.task_category_id).map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.label_es}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label htmlFor={`${uid}-area`} className={LABEL}>
                {t('tasks.f_work_area')}
              </label>
              <select id={`${uid}-area`} value={workAreaId} onChange={(e) => setWorkAreaId(e.target.value)} className={FIELD}>
                <option value="">{t('tasks.f_none')}</option>
                {workAreas.filter((a) => !a.archived_at || a.id === task?.work_area_id).map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.label_es}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label htmlFor={`${uid}-assignee`} className={LABEL}>
                {t('tasks.f_assignee')}
              </label>
              <select id={`${uid}-assignee`} value={assignedTo} onChange={(e) => setAssignedTo(e.target.value)} className={FIELD}>
                <option value="">{t('tasks.f_pool')}</option>
                {assigneeOptions.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name}
                  </option>
                ))}
              </select>
              <p className="mt-1 text-xs text-gray-600">{t('tasks.f_pool_hint')}</p>
            </div>
            <div>
              <label htmlFor={`${uid}-due`} className={LABEL}>
                {t('tasks.f_due')}
              </label>
              <input id={`${uid}-due`} type="date" value={dueAt} onChange={(e) => setDueAt(e.target.value)} className={FIELD} />
            </div>
          </div>

          <label className="flex min-h-11 items-center gap-3 rounded-lg border border-gray-200 bg-gray-50 px-3 text-sm text-carbon">
            <input type="checkbox" checked={photoRequired} onChange={(e) => setPhotoRequired(e.target.checked)} className="h-5 w-5 rounded border-gray-300 text-turquesa-dark" />
            <span>{t('tasks.f_photo')}</span>
          </label>

        </div>

        {confirmingLeave && <DiscardConfirm onDiscard={onCancel} onKeep={() => setConfirmingLeave(false)} />}

        <div className="sticky bottom-[calc(3.5rem+env(safe-area-inset-bottom))] z-30 -mx-4 border-t border-gray-200 bg-white/95 px-4 py-3 backdrop-blur md:bottom-0 md:mx-0 md:rounded-2xl md:border">
          <DisabledReason id="tarea" reason={saveReason} className="mb-2" />
          <div className="flex items-center justify-between gap-3">
            <button type="button" onClick={leave} className="min-h-11 rounded-lg border border-gray-300 bg-white px-4 text-sm font-semibold text-gray-700 hover:bg-gray-50">
              {t('common.cancel')}
            </button>
            <button
              type="submit"
              disabled={!valid || busy}
              aria-busy={busy || undefined}
              {...describedBy('tarea', saveReason)}
              className="inline-flex min-h-11 items-center gap-2 rounded-lg bg-turquesa px-5 text-sm font-semibold text-carbon hover:bg-turquesa-hover disabled:cursor-not-allowed disabled:opacity-50"
            >
              <CheckCircle2 className="h-4 w-4" aria-hidden="true" />
              {busy ? t('toast.saving') : t(task ? 'tasks.f_save' : 'tasks.f_create')}
            </button>
          </div>
        </div>
      </form>
    </div>
  );
};
