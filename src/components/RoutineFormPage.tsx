import React, { useId, useRef, useState } from 'react';
import { ArrowDown, ArrowLeft, ArrowUp, CheckCircle2, Plus, Trash2 } from 'lucide-react';
import { t } from '../lib/i18n';
import { RoutineDraft } from '../lib/tasks';
import { RoutineTemplate, RoutineTemplateItem, TaskCategory, WorkArea } from '../types/database';
import { DiscardConfirm, useBeforeUnloadGuard } from './LeaveGuard';
import { DisabledReason, describedBy } from './DisabledReason';

// Alta y edición de una plantilla de rutina y sus pasos (BV-7.11), como PÁGINA (no modal): siete campos y una lista de
// pasos. Sólo gestión (la base lo exige).
// Los pasos se pueden reordenar y quitar con botones, no sólo arrastrando: un gesto no puede ser la única forma.

interface RoutineFormPageProps {
  routine: RoutineTemplate | null;
  items: RoutineTemplateItem[];
  categories: TaskCategory[];
  workAreas: WorkArea[];
  busy: boolean;
  /** Vuelve a las rutinas (se llama tras confirmar si había cambios sin guardar) */
  onCancel: () => void;
  onSubmit: (draft: RoutineDraft) => void;
}

interface Step {
  /** Llave estable de React (los pasos nuevos aún no tienen id) */
  uid: number;
  id?: string;
  name: string;
  details: string;
  photo_required: boolean;
}

const FIELD = 'mt-1 w-full min-h-11 rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa';
const LABEL = 'block text-sm font-semibold text-gray-700';
const ICON_BTN = 'flex h-11 w-11 items-center justify-center rounded-lg border border-gray-300 bg-white text-gray-700 hover:bg-gray-50 disabled:opacity-40';
const ICON_BTN_SPACE = 'h-11 w-11';

export const RoutineFormPage: React.FC<RoutineFormPageProps> = ({ routine, items, categories, workAreas, busy, onCancel, onSubmit }) => {
  const uid = useId();
  const seq = useRef(0);
  const nextUid = () => ++seq.current;

  const [name, setName] = useState(routine?.name ?? '');
  const [description, setDescription] = useState(routine?.description ?? '');
  const [workAreaId, setWorkAreaId] = useState(routine?.work_area_id ?? '');
  const [categoryId, setCategoryId] = useState(routine?.task_category_id ?? '');
  const [steps, setSteps] = useState<Step[]>(() =>
    routine
      ? items
          .filter((i) => i.routine_template_id === routine.id && !i.archived_at)
          .sort((a, b) => a.sort_order - b.sort_order)
          .map((i) => ({ uid: nextUid(), id: i.id, name: i.name, details: i.details ?? '', photo_required: i.photo_required }))
      : [{ uid: nextUid(), name: '', details: '', photo_required: false }]
  );

  // ¿Hay cambios sin guardar? Al salir se pide confirmación
  const stepsKey = (list: Step[]) => JSON.stringify(list.map(({ name, details, photo_required }) => ({ name, details, photo_required })));
  const initialSteps = useRef(stepsKey(steps));
  const dirty =
    name !== (routine?.name ?? '') ||
    description !== (routine?.description ?? '') ||
    workAreaId !== (routine?.work_area_id ?? '') ||
    categoryId !== (routine?.task_category_id ?? '') ||
    stepsKey(steps) !== initialSteps.current;
  const [confirmingLeave, setConfirmingLeave] = useState(false);
  useBeforeUnloadGuard(dirty);
  const leave = () => (dirty ? setConfirmingLeave(true) : onCancel());

  const patch = (key: number, change: Partial<Step>) => setSteps((s) => s.map((x) => (x.uid === key ? { ...x, ...change } : x)));
  const move = (index: number, delta: number) =>
    setSteps((s) => {
      const to = index + delta;
      if (to < 0 || to >= s.length) return s;
      const copy = [...s];
      [copy[index], copy[to]] = [copy[to], copy[index]];
      return copy;
    });

  const named = steps.filter((s) => s.name.trim());
  const valid = name.trim().length > 0 && named.length > 0;
  const saveReason = name.trim().length === 0 ? t('tasks.routines.reason_name') : named.length === 0 ? t('tasks.routines.reason_steps') : null;

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!valid || busy) return;
    onSubmit({
      id: routine?.id,
      name: name.trim(),
      description: description.trim() || null,
      work_area_id: workAreaId || null,
      task_category_id: categoryId || null,
      // Los pasos sin nombre se descartan: un paso vacío no es una tarea
      items: named.map((s) => ({ id: s.id, name: s.name.trim(), details: s.details.trim() || null, photo_required: s.photo_required })),
    });
  };

  return (
    <div className="mx-auto max-w-3xl space-y-5">
      <div>
        <button type="button" onClick={leave} className="inline-flex min-h-11 items-center gap-1.5 text-sm font-semibold text-turquesa-dark hover:underline">
          <ArrowLeft className="h-4 w-4" aria-hidden="true" />
          {t('tasks.page.back_to_routines')}
        </button>
        <h2 className="font-title text-2xl font-bold text-carbon">{t(routine ? 'tasks.routines.form_title_edit' : 'tasks.routines.form_title_new')}</h2>
      </div>

      <form onSubmit={submit} className="space-y-5">
        <div className="space-y-4 rounded-2xl border border-gray-200 bg-white p-5">
          <div>
            <label htmlFor={`${uid}-name`} className={LABEL}>
              {t('tasks.routines.f_name')}
            </label>
            <input id={`${uid}-name`} type="text" required maxLength={120} value={name} onChange={(e) => setName(e.target.value)} className={FIELD} />
          </div>
          <div>
            <label htmlFor={`${uid}-desc`} className={LABEL}>
              {t('tasks.routines.f_description')}
            </label>
            <textarea id={`${uid}-desc`} rows={2} maxLength={1000} value={description} onChange={(e) => setDescription(e.target.value)} className={FIELD} />
          </div>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div>
              <label htmlFor={`${uid}-area`} className={LABEL}>
                {t('tasks.routines.f_work_area')}
              </label>
              <select id={`${uid}-area`} value={workAreaId} onChange={(e) => setWorkAreaId(e.target.value)} className={FIELD}>
                <option value="">{t('tasks.f_none')}</option>
                {workAreas.filter((a) => !a.archived_at || a.id === routine?.work_area_id).map((a) => (
                  <option key={a.id} value={a.id}>{a.label_es}</option>
                ))}
              </select>
            </div>
            <div>
              <label htmlFor={`${uid}-cat`} className={LABEL}>
                {t('tasks.routines.f_category')}
              </label>
              <select id={`${uid}-cat`} value={categoryId} onChange={(e) => setCategoryId(e.target.value)} className={FIELD}>
                <option value="">{t('tasks.f_none')}</option>
                {categories.filter((c) => !c.archived_at || c.id === routine?.task_category_id).map((c) => (
                  <option key={c.id} value={c.id}>{c.label_es}</option>
                ))}
              </select>
            </div>
          </div>

        </div>

        <fieldset className="space-y-3 rounded-2xl border border-gray-200 bg-white p-5">
            <legend className="px-1 text-base font-bold text-carbon">{t('tasks.routines.steps')}</legend>
            <p className="text-xs text-amber-900">{t('tasks.routines.steps_warning')}</p>
            <ol className="space-y-3">
              {steps.map((step, index) => (
                <li key={step.uid} className="rounded-xl border border-gray-200 bg-gray-50 p-3">
                  <div className="flex items-start gap-2">
                    <span className="mt-2.5 w-6 shrink-0 text-center font-mono text-xs text-gray-600" aria-hidden="true">{index + 1}</span>
                    <div className="min-w-0 flex-1 space-y-2">
                      <label htmlFor={`${uid}-s${step.uid}-name`} className={LABEL}>
                        {t('tasks.routines.f_step_name').replace('{n}', String(index + 1))}
                      </label>
                      <input
                        id={`${uid}-s${step.uid}-name`}
                        type="text"
                        maxLength={120}
                        value={step.name}
                        onChange={(e) => patch(step.uid, { name: e.target.value })}
                        className={FIELD}
                      />
                      <label htmlFor={`${uid}-s${step.uid}-det`} className={LABEL}>
                        {t('tasks.routines.f_step_details')}
                      </label>
                      <textarea
                        id={`${uid}-s${step.uid}-det`}
                        rows={2}
                        maxLength={1000}
                        value={step.details}
                        onChange={(e) => patch(step.uid, { details: e.target.value })}
                        className={FIELD}
                      />
                      <label className="flex min-h-11 items-center gap-3 text-sm text-carbon">
                        <input type="checkbox" checked={step.photo_required} onChange={(e) => patch(step.uid, { photo_required: e.target.checked })} className="h-5 w-5 rounded border-gray-300 text-turquesa-dark" />
                        <span>{t('tasks.routines.f_step_photo')}</span>
                      </label>
                    </div>
                    <div className="flex shrink-0 flex-col gap-1.5">
                      {index > 0 ? (
                        <button type="button" onClick={() => move(index, -1)} aria-label={t('tasks.routines.move_up')} className={ICON_BTN}>
                          <ArrowUp className="h-4 w-4" aria-hidden="true" />
                        </button>
                      ) : (
                        <span className={ICON_BTN_SPACE} aria-hidden="true" />
                      )}
                      {index < steps.length - 1 ? (
                        <button type="button" onClick={() => move(index, 1)} aria-label={t('tasks.routines.move_down')} className={ICON_BTN}>
                          <ArrowDown className="h-4 w-4" aria-hidden="true" />
                        </button>
                      ) : (
                        <span className={ICON_BTN_SPACE} aria-hidden="true" />
                      )}
                      {steps.length > 1 ? (
                        <button type="button" onClick={() => setSteps((s) => s.filter((x) => x.uid !== step.uid))} aria-label={t('tasks.routines.remove_step')} className={ICON_BTN}>
                          <Trash2 className="h-4 w-4" aria-hidden="true" />
                        </button>
                      ) : (
                        <span className={ICON_BTN_SPACE} aria-hidden="true" />
                      )}
                    </div>
                  </div>
                </li>
              ))}
            </ol>
            <button
              type="button"
              onClick={() => setSteps((s) => [...s, { uid: nextUid(), name: '', details: '', photo_required: false }])}
              className="inline-flex min-h-11 items-center gap-2 rounded-lg border border-gray-300 bg-white px-3 text-sm font-medium text-gray-700 hover:bg-gray-50"
            >
              <Plus className="h-4 w-4" aria-hidden="true" />
              {t('tasks.routines.add_step')}
            </button>
          </fieldset>


        {confirmingLeave && <DiscardConfirm onDiscard={onCancel} onKeep={() => setConfirmingLeave(false)} />}

        <div className="sticky bottom-[calc(3.5rem+env(safe-area-inset-bottom))] z-30 -mx-4 border-t border-gray-200 bg-white/95 px-4 py-3 backdrop-blur md:bottom-0 md:mx-0 md:rounded-2xl md:border">
          <DisabledReason id="rutina" reason={saveReason} className="mb-2" />
          <div className="flex items-center justify-between gap-3">
            <button type="button" onClick={leave} className="min-h-11 rounded-lg border border-gray-300 bg-white px-4 text-sm font-semibold text-gray-700 hover:bg-gray-50">
              {t('common.cancel')}
            </button>
            <button
              type="submit"
              disabled={!valid || busy}
              aria-busy={busy || undefined}
              {...describedBy('rutina', saveReason)}
              className="inline-flex min-h-11 items-center gap-2 rounded-lg bg-turquesa px-5 text-sm font-semibold text-carbon hover:bg-turquesa-hover disabled:cursor-not-allowed disabled:opacity-50"
            >
              <CheckCircle2 className="h-4 w-4" aria-hidden="true" />
              {busy ? t('toast.saving') : t('tasks.routines.save')}
            </button>
          </div>
        </div>
      </form>
    </div>
  );
};
