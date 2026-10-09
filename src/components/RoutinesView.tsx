import React, { useState } from 'react';
import { Archive, MapPin, Pencil, Plus, Tag } from 'lucide-react';
import { t } from '../lib/i18n';
import { RoutineDraft } from '../lib/tasks';
import { RoutineTemplate, RoutineTemplateItem, TaskCategory, WorkArea } from '../types/database';
import { ModalShell } from './ModalShell';
import { RoutineFormModal } from './RoutineFormModal';

// Plantillas de rutina (BV-7.11), para quien gestiona. Una plantilla mal armada se multiplica por cada
// persona que la inicie: por eso se revisa aquí, con sus pasos a la vista, antes de ofrecerla.

interface RoutinesViewProps {
  routines: RoutineTemplate[];
  items: RoutineTemplateItem[];
  categories: TaskCategory[];
  workAreas: WorkArea[];
  busyId: string | null;
  saving: boolean;
  onSave: (draft: RoutineDraft) => Promise<boolean>;
  onArchive: (id: string) => Promise<boolean>;
}

export const RoutinesView: React.FC<RoutinesViewProps> = ({ routines, items, categories, workAreas, busyId, saving, onSave, onArchive }) => {
  const [form, setForm] = useState<{ routine: RoutineTemplate | null } | null>(null);
  const [archiving, setArchiving] = useState<RoutineTemplate | null>(null);

  const active = routines.filter((r) => !r.archived_at);
  const stepsOf = (id: string) => items.filter((i) => i.routine_template_id === id && !i.archived_at).sort((a, b) => a.sort_order - b.sort_order);
  const categoryLabel = (id: string | null) => categories.find((c) => c.id === id)?.label_es;
  const workAreaLabel = (id: string | null) => workAreas.find((a) => a.id === id)?.label_es;

  const submit = async (draft: RoutineDraft) => {
    if (await onSave(draft)) setForm(null);
  };
  const confirmArchive = async () => {
    if (archiving && (await onArchive(archiving.id))) setArchiving(null);
  };

  return (
    <div className="space-y-4">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <p className="max-w-2xl text-sm text-gray-600">{t('tasks.routines.intro')}</p>
        <button
          type="button"
          onClick={() => setForm({ routine: null })}
          className="inline-flex min-h-11 shrink-0 items-center justify-center gap-2 rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon hover:bg-turquesa-hover"
        >
          <Plus className="h-4 w-4" aria-hidden="true" />
          {t('tasks.routines.new')}
        </button>
      </div>

      {active.length === 0 ? (
        <p className="rounded-xl border border-dashed border-gray-300 bg-white px-4 py-10 text-center text-sm text-gray-600">{t('tasks.routines.empty')}</p>
      ) : (
        <ul className="grid grid-cols-1 gap-4 lg:grid-cols-2">
          {active.map((r) => {
            const steps = stepsOf(r.id);
            return (
              <li key={r.id} className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
                <h3 className="break-words text-base font-bold text-carbon">{r.name}</h3>
                {r.description && <p className="mt-0.5 break-words text-xs text-gray-600">{r.description}</p>}
                <div className="mt-2 flex flex-wrap gap-x-3 gap-y-1 text-xs text-gray-600">
                  {workAreaLabel(r.work_area_id) && (
                    <span className="inline-flex items-center gap-1">
                      <MapPin className="h-3.5 w-3.5" aria-hidden="true" />
                      {workAreaLabel(r.work_area_id)}
                    </span>
                  )}
                  {categoryLabel(r.task_category_id) && (
                    <span className="inline-flex items-center gap-1">
                      <Tag className="h-3.5 w-3.5" aria-hidden="true" />
                      {categoryLabel(r.task_category_id)}
                    </span>
                  )}
                </div>
                <ol className="mt-3 list-decimal space-y-1 pl-5 text-sm text-carbon">
                  {steps.map((s) => (
                    <li key={s.id} className="break-words">
                      {s.name}
                      {s.photo_required && <span className="ml-1.5 rounded bg-amber-50 px-1.5 py-0.5 text-xs text-amber-900">{t('tasks.routines.photo_tag')}</span>}
                    </li>
                  ))}
                </ol>
                <div className="mt-4 flex flex-wrap gap-2">
                  <button
                    type="button"
                    onClick={() => setForm({ routine: r })}
                    disabled={busyId === r.id}
                    className="inline-flex min-h-11 items-center gap-1.5 rounded-lg border border-gray-300 bg-white px-3 text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:opacity-50"
                  >
                    <Pencil className="h-4 w-4" aria-hidden="true" />
                    {t('tasks.action_edit')}
                  </button>
                  <button
                    type="button"
                    onClick={() => setArchiving(r)}
                    disabled={busyId === r.id}
                    className="inline-flex min-h-11 items-center gap-1.5 rounded-lg border border-gray-300 bg-white px-3 text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:opacity-50"
                  >
                    <Archive className="h-4 w-4" aria-hidden="true" />
                    {t('tasks.action_archive')}
                  </button>
                </div>
              </li>
            );
          })}
        </ul>
      )}

      {form && <RoutineFormModal routine={form.routine} items={items} categories={categories} workAreas={workAreas} busy={saving} onClose={() => setForm(null)} onSubmit={submit} />}

      {archiving && (
        <ModalShell onClose={() => setArchiving(null)} className="fixed inset-0 z-50 flex items-center justify-center bg-carbon/60 p-4 backdrop-blur-sm">
          <div className="w-full max-w-md rounded-xl bg-white shadow-2xl">
            <div className="flex items-center gap-2 border-b border-gray-100 px-6 py-4">
              <Archive className="h-5 w-5 text-alerta-dark" aria-hidden="true" />
              <h3 className="text-base font-bold text-carbon">{t('tasks.routines.archive_title')}</h3>
            </div>
            <div className="space-y-3 px-6 py-5 text-sm text-carbon">
              <p className="break-words font-semibold">{archiving.name}</p>
              <p className="rounded-lg border border-alerta/20 bg-alerta-bg p-3 text-xs text-alerta-dark">{t('tasks.routines.archive_body')}</p>
            </div>
            <div className="flex items-center justify-end gap-3 border-t border-gray-100 px-6 py-4">
              <button type="button" onClick={() => setArchiving(null)} className="min-h-11 rounded-lg border border-gray-300 px-4 text-sm font-medium text-gray-700 hover:bg-gray-50">
                {t('common.cancel')}
              </button>
              <button
                type="button"
                onClick={confirmArchive}
                disabled={busyId === archiving.id}
                className="inline-flex min-h-11 items-center gap-2 rounded-lg bg-carbon px-4 text-sm font-semibold text-white hover:bg-carbon-light disabled:opacity-60"
              >
                <Archive className="h-4 w-4" aria-hidden="true" />
                {t('tasks.archive_confirm')}
              </button>
            </div>
          </div>
        </ModalShell>
      )}
    </div>
  );
};
