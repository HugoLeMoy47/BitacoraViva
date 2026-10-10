import React, { useId, useState } from 'react';
import { Archive, Check, Pencil, Plus, X } from 'lucide-react';
import { t } from '../lib/i18n';
import { CatalogKind } from '../lib/tasks';
import { normalize } from '../lib/taskReports';
import { CaseTaskKind, TaskCategory, WorkArea } from '../types/database';
import { ModalShell } from './ModalShell';

// Administración de catálogos de tareas (BV-7.9): categorías y áreas de trabajo. Sólo la dirección
// escribe (lo exige la base). Nada se borra: archivar saca el valor de los selectores nuevos pero las
// tareas que ya lo usan conservan su etiqueta. La clave interna es estable; la etiqueta se renombra.

type Item = TaskCategory | WorkArea | CaseTaskKind;

interface TaskCatalogsViewProps {
  categories: TaskCategory[];
  workAreas: WorkArea[];
  caseTaskKinds: CaseTaskKind[];
  busyId: string | null;
  saving: boolean;
  onCreate: (kind: CatalogKind, label: string, takenKeys: string[]) => Promise<boolean>;
  onRename: (kind: CatalogKind, id: string, label: string) => Promise<boolean>;
  onArchive: (kind: CatalogKind, id: string) => Promise<boolean>;
}

const BTN = 'inline-flex min-h-11 items-center gap-1.5 rounded-lg border border-gray-300 bg-white px-3 text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:opacity-50';

const CatalogSection: React.FC<{
  kind: CatalogKind;
  items: Item[];
  busyId: string | null;
  saving: boolean;
  onCreate: TaskCatalogsViewProps['onCreate'];
  onRename: TaskCatalogsViewProps['onRename'];
  onAskArchive: (item: Item) => void;
}> = ({ kind, items, busyId, saving, onCreate, onRename, onAskArchive }) => {
  const uid = useId();
  const active = items.filter((i) => !i.archived_at);
  const [draft, setDraft] = useState('');
  const [editing, setEditing] = useState<{ id: string; label: string } | null>(null);
  const [error, setError] = useState<string | null>(null);

  const duplicate = (label: string, exceptId?: string) => active.some((i) => i.id !== exceptId && normalize(i.label_es) === normalize(label));

  const add = async (e: React.FormEvent) => {
    e.preventDefault();
    const label = draft.trim();
    if (!label) return;
    if (duplicate(label)) {
      setError(t('tasks.catalogs.duplicate'));
      return;
    }
    setError(null);
    if (await onCreate(kind, label, items.map((i) => i.key))) setDraft('');
  };

  const saveRename = async () => {
    if (!editing) return;
    const label = editing.label.trim();
    if (!label) return;
    if (duplicate(label, editing.id)) {
      setError(t('tasks.catalogs.duplicate'));
      return;
    }
    setError(null);
    if (await onRename(kind, editing.id, label)) setEditing(null);
  };

  return (
    <section className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm sm:p-5">
      <h3 className="text-base font-bold text-carbon">{t(`tasks.catalogs.${kind}_title`)}</h3>
      <p className="mb-3 mt-0.5 text-xs text-gray-600">{t(`tasks.catalogs.${kind}_hint`)}</p>

      {active.length === 0 ? (
        <p className="mb-3 rounded-lg border border-dashed border-gray-300 px-3 py-4 text-center text-sm text-gray-600">{t('tasks.catalogs.empty')}</p>
      ) : (
        <ul className="mb-4 divide-y divide-gray-100">
          {active.map((item) => (
            <li key={item.id} className="flex flex-wrap items-center gap-2 py-2">
              {editing?.id === item.id ? (
                <>
                  <input
                    aria-label={t('tasks.catalogs.rename_label')}
                    value={editing.label}
                    maxLength={60}
                    onChange={(e) => setEditing({ id: item.id, label: e.target.value })}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') saveRename();
                      if (e.key === 'Escape') setEditing(null);
                    }}
                    className="min-h-11 min-w-0 flex-1 rounded-lg border border-gray-300 px-3 text-sm focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa"
                  />
                  <button type="button" onClick={saveRename} disabled={busyId === item.id || !editing.label.trim()} className={BTN}>
                    <Check className="h-4 w-4" aria-hidden="true" />
                    {t('tasks.catalogs.save')}
                  </button>
                  <button type="button" onClick={() => setEditing(null)} className={BTN}>
                    <X className="h-4 w-4" aria-hidden="true" />
                    {t('common.cancel')}
                  </button>
                </>
              ) : (
                <>
                  <span className="min-w-0 flex-1 break-words text-sm text-carbon">{item.label_es}</span>
                  <button type="button" onClick={() => { setError(null); setEditing({ id: item.id, label: item.label_es }); }} disabled={busyId === item.id} className={BTN}>
                    <Pencil className="h-4 w-4" aria-hidden="true" />
                    {t('tasks.catalogs.rename')}
                  </button>
                  <button type="button" onClick={() => onAskArchive(item)} disabled={busyId === item.id} className={BTN}>
                    <Archive className="h-4 w-4" aria-hidden="true" />
                    {t('tasks.action_archive')}
                  </button>
                </>
              )}
            </li>
          ))}
        </ul>
      )}

      <form onSubmit={add} className="flex flex-col gap-2 sm:flex-row sm:items-end">
        <label htmlFor={`${uid}-new`} className="block flex-1 text-xs font-semibold text-gray-700">
          {t('tasks.catalogs.add_label')}
          <input
            id={`${uid}-new`}
            value={draft}
            maxLength={60}
            onChange={(e) => setDraft(e.target.value)}
            className="mt-1 block min-h-11 w-full rounded-lg border border-gray-300 px-3 text-sm focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa"
          />
        </label>
        <button
          type="submit"
          disabled={saving || !draft.trim()}
          className="inline-flex min-h-11 items-center justify-center gap-2 rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon hover:bg-turquesa-hover disabled:opacity-50"
        >
          <Plus className="h-4 w-4" aria-hidden="true" />
          {t('tasks.catalogs.add')}
        </button>
      </form>
      {error && (
        <p role="alert" className="mt-2 text-xs font-medium text-alerta-dark">
          {error}
        </p>
      )}
    </section>
  );
};

export const TaskCatalogsView: React.FC<TaskCatalogsViewProps> = ({ categories, workAreas, caseTaskKinds, busyId, saving, onCreate, onRename, onArchive }) => {
  const [archiving, setArchiving] = useState<{ kind: CatalogKind; item: Item } | null>(null);

  const confirm = async () => {
    if (!archiving) return;
    if (await onArchive(archiving.kind, archiving.item.id)) setArchiving(null);
  };

  return (
    <div className="space-y-4">
      <p className="text-sm text-gray-600">{t('tasks.catalogs.intro')}</p>
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <CatalogSection kind="category" items={categories} busyId={busyId} saving={saving} onCreate={onCreate} onRename={onRename} onAskArchive={(item) => setArchiving({ kind: 'category', item })} />
        <CatalogSection kind="workArea" items={workAreas} busyId={busyId} saving={saving} onCreate={onCreate} onRename={onRename} onAskArchive={(item) => setArchiving({ kind: 'workArea', item })} />
        <CatalogSection kind="caseKind" items={caseTaskKinds} busyId={busyId} saving={saving} onCreate={onCreate} onRename={onRename} onAskArchive={(item) => setArchiving({ kind: 'caseKind', item })} />
      </div>

      {archiving && (
        <ModalShell onClose={() => setArchiving(null)} className="fixed inset-0 z-50 flex items-center justify-center bg-carbon/60 p-4 backdrop-blur-sm">
          <div className="w-full max-w-md rounded-xl bg-white shadow-2xl">
            <div className="flex items-center gap-2 border-b border-gray-100 px-6 py-4">
              <Archive className="h-5 w-5 text-alerta-dark" aria-hidden="true" />
              <h3 className="text-base font-bold text-carbon">{t('tasks.catalogs.archive_title')}</h3>
            </div>
            <div className="space-y-3 px-6 py-5 text-sm text-carbon">
              <p className="break-words font-semibold">{archiving.item.label_es}</p>
              <p className="rounded-lg border border-alerta/20 bg-alerta-bg p-3 text-xs text-alerta-dark">{t('tasks.catalogs.archive_body')}</p>
            </div>
            <div className="flex items-center justify-end gap-3 border-t border-gray-100 px-6 py-4">
              <button type="button" onClick={() => setArchiving(null)} className="min-h-11 rounded-lg border border-gray-300 px-4 text-sm font-medium text-gray-700 hover:bg-gray-50">
                {t('common.cancel')}
              </button>
              <button
                type="button"
                onClick={confirm}
                disabled={busyId === archiving.item.id}
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
