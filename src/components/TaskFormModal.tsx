import React, { useId, useState } from 'react';
import { CheckCircle2, ListChecks, X } from 'lucide-react';
import { t } from '../lib/i18n';
import { TaskInput } from '../lib/tasks';
import { Task, TaskCategory, WorkArea } from '../types/database';
import { ModalShell } from './ModalShell';

// Alta y edición de una tarea (gestión de tareas). La base vuelve a exigir quién puede hacerlo.

interface TaskFormModalProps {
  /** Tarea a editar; nula para una nueva */
  task: Task | null;
  categories: TaskCategory[];
  workAreas: WorkArea[];
  /** Personas a quienes se puede asignar, ya con su nombre */
  assignees: { id: string; name: string }[];
  busy: boolean;
  onClose: () => void;
  onSubmit: (input: TaskInput) => void;
}

const FIELD = 'mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa';
const LABEL = 'block text-xs font-semibold text-gray-700';

export const TaskFormModal: React.FC<TaskFormModalProps> = ({ task, categories, workAreas, assignees, busy, onClose, onSubmit }) => {
  const uid = useId();
  const [name, setName] = useState(task?.name ?? '');
  const [details, setDetails] = useState(task?.details ?? '');
  const [categoryId, setCategoryId] = useState(task?.task_category_id ?? '');
  const [workAreaId, setWorkAreaId] = useState(task?.work_area_id ?? '');
  const [assignedTo, setAssignedTo] = useState(task?.assigned_to ?? '');
  const [dueAt, setDueAt] = useState(task?.due_at ?? '');
  const [photoRequired, setPhotoRequired] = useState(task?.photo_required ?? false);

  // Una tarea ligada a un caso no tiene texto libre: su nombre sale de un catálogo (decisión 6a)
  const linked = !!task?.case_id;
  const valid = name.trim().length > 0 && name.trim().length <= 120 && details.length <= 1000;

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
    <ModalShell onClose={onClose} className="fixed inset-0 z-50 flex items-center justify-center bg-carbon/60 p-4 backdrop-blur-sm">
      <div className="flex max-h-[90vh] w-full max-w-xl flex-col rounded-xl bg-white shadow-2xl">
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4">
          <div className="flex items-center gap-2">
            <ListChecks className="h-5 w-5 text-turquesa-dark" aria-hidden="true" />
            <h3 className="text-base font-bold text-carbon">{t(task ? 'tasks.form_title_edit' : 'tasks.form_title_new')}</h3>
          </div>
          <button type="button" onClick={onClose} aria-label={t('common.close')} className="flex h-11 w-11 items-center justify-center rounded-lg text-gray-600 hover:bg-gray-100">
            <X className="h-5 w-5" aria-hidden="true" />
          </button>
        </div>

        <form onSubmit={submit} className="space-y-4 overflow-y-auto px-6 py-5">
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

          <div className="flex items-center justify-end gap-3 border-t border-gray-100 pt-3">
            <button type="button" onClick={onClose} className="min-h-11 rounded-lg border border-gray-300 px-4 text-sm font-medium text-gray-700 hover:bg-gray-50">
              {t('common.cancel')}
            </button>
            <button
              type="submit"
              disabled={!valid || busy}
              className="inline-flex min-h-11 items-center gap-2 rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon hover:bg-turquesa-hover disabled:opacity-50"
            >
              <CheckCircle2 className="h-4 w-4" aria-hidden="true" />
              {t(task ? 'tasks.f_save' : 'tasks.f_create')}
            </button>
          </div>
        </form>
      </div>
    </ModalShell>
  );
};
