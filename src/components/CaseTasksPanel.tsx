import React, { useCallback, useEffect, useId, useMemo, useState } from 'react';
import { CalendarClock, Link2Off, ListChecks, Plus, User, X } from 'lucide-react';
import { t } from '../lib/i18n';
import { formatDate } from '../lib/format';
import { useCatalog } from '../lib/catalog';
import { useToast } from '../lib/toast';
import { caseTaskApi, taskErrorMessage } from '../lib/tasks';
import { CaseTaskKind, Task } from '../types/database';
import { ModalShell } from './ModalShell';

// Tareas ligadas a un caso (BV-7.16, decisión 6a). Desde aquí quien opera expedientes crea una tarea para
// el equipo de apoyo SIN pasarle datos del caso: la tarea lleva el folio y un nombre de catálogo neutro
// («Acompañamiento», «Trámite»…), nunca texto libre. El detalle vive en el expediente, al que el
// voluntariado no entra.

interface CaseTasksPanelProps {
  caseId: string;
  caseNumber: string;
}

const FIELD = 'mt-1 w-full min-h-11 rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa';
const LABEL = 'block text-xs font-semibold text-gray-700';
const SECONDARY =
  'inline-flex min-h-11 items-center gap-1.5 rounded-lg border border-gray-300 bg-white px-3 text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:opacity-50';

export const CaseTasksPanel: React.FC<CaseTasksPanelProps> = ({ caseId, caseNumber }) => {
  const toast = useToast();
  const { userNames } = useCatalog();
  const uid = useId();
  const [tasks, setTasks] = useState<Task[] | null>(null);
  const [kinds, setKinds] = useState<CaseTaskKind[]>([]);
  const [assignableIds, setAssignableIds] = useState<string[]>([]);
  const [failed, setFailed] = useState(false);
  const [creating, setCreating] = useState(false);
  const [unlinking, setUnlinking] = useState<Task | null>(null);
  const [busy, setBusy] = useState(false);
  const [kindId, setKindId] = useState('');
  const [assignedTo, setAssignedTo] = useState('');
  const [dueAt, setDueAt] = useState('');

  const load = useCallback(async () => {
    try {
      const [list, ks, ids] = await Promise.all([caseTaskApi.forCase(caseId), caseTaskApi.kinds(), caseTaskApi.assignableUserIds()]);
      setTasks(list);
      setKinds(ks);
      setAssignableIds(ids);
      setFailed(false);
    } catch (e) {
      setFailed(true);
      toast.error(taskErrorMessage(e));
    }
  }, [caseId, toast]);

  useEffect(() => {
    load();
  }, [load]);

  const assignees = useMemo(
    () => assignableIds.map((id) => ({ id, name: userNames[id] || '' })).filter((a) => a.name).sort((a, b) => a.name.localeCompare(b.name, 'es')),
    [assignableIds, userNames]
  );
  const kindLabel = useMemo(() => new Map(kinds.map((k) => [k.id, k.label_es])), [kinds]);

  const openCreate = () => {
    setKindId('');
    setAssignedTo('');
    setDueAt('');
    setCreating(true);
  };

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!kindId || busy) return;
    setBusy(true);
    try {
      await caseTaskApi.create(caseId, kindId, assignedTo || null, dueAt || null);
      toast.success(t('tasks.case.toast_created'));
      setCreating(false);
      await load();
    } catch (err) {
      toast.error(taskErrorMessage(err));
    } finally {
      setBusy(false);
    }
  };

  const confirmUnlink = async () => {
    if (!unlinking || busy) return;
    setBusy(true);
    try {
      await caseTaskApi.unlink(unlinking.id);
      toast.success(t('tasks.case.toast_unlinked'));
      setUnlinking(null);
      await load();
    } catch (err) {
      toast.error(taskErrorMessage(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          <h3 className="font-bold text-turquesa-dark">{t('tasks.case.title')}</h3>
          <p className="mt-0.5 text-xs text-gray-600">{t('tasks.case.intro').replace('{folio}', caseNumber)}</p>
        </div>
        <button
          type="button"
          onClick={openCreate}
          disabled={kinds.length === 0}
          className="inline-flex min-h-11 items-center gap-2 rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon hover:bg-turquesa-hover disabled:opacity-50"
        >
          <Plus className="h-4 w-4" aria-hidden="true" />
          {t('tasks.case.new')}
        </button>
      </div>
      {tasks !== null && kinds.length === 0 && <p className="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-900">{t('tasks.case.no_kinds')}</p>}

      {failed ? (
        <p className="rounded-lg border border-dashed border-gray-300 px-3 py-6 text-center text-sm text-gray-600">{t('tasks.case.load_failed')}</p>
      ) : tasks === null ? (
        <p className="py-6 text-center text-sm text-gray-600">{t('session.loading')}</p>
      ) : tasks.length === 0 ? (
        <p className="rounded-lg border border-dashed border-gray-300 px-3 py-6 text-center text-sm text-gray-600">{t('tasks.case.empty')}</p>
      ) : (
        <ul className="space-y-2.5">
          {tasks.map((task) => (
            <li key={task.id} className="rounded-xl border border-gray-200 bg-white p-3.5 shadow-sm">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <p className="break-words text-sm font-semibold text-carbon">{(task.case_task_kind_id && kindLabel.get(task.case_task_kind_id)) || task.name}</p>
                <span className="rounded bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-700">{t(`tasks.status_${task.status}`)}</span>
              </div>
              <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-gray-600">
                <span className="inline-flex items-center gap-1">
                  <User className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
                  {task.assigned_to ? userNames[task.assigned_to] || t('tasks.assignee_former') : t('tasks.case.unassigned')}
                </span>
                {task.due_at && (
                  <span className="inline-flex items-center gap-1">
                    <CalendarClock className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
                    {t('tasks.due').replace('{date}', formatDate(task.due_at))}
                  </span>
                )}
              </div>
              <div className="mt-2">
                <button type="button" onClick={() => setUnlinking(task)} className={SECONDARY}>
                  <Link2Off className="h-4 w-4" aria-hidden="true" />
                  {t('tasks.case.unlink')}
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}

      {creating && (
        <ModalShell onClose={() => setCreating(false)} className="fixed inset-0 z-50 flex items-center justify-center bg-carbon/60 p-4 backdrop-blur-sm">
          <div className="flex max-h-[90vh] w-full max-w-md flex-col rounded-xl bg-white shadow-2xl">
            <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4">
              <div className="flex items-center gap-2">
                <ListChecks className="h-5 w-5 text-turquesa-dark" aria-hidden="true" />
                <h3 className="text-base font-bold text-carbon">{t('tasks.case.form_title')}</h3>
              </div>
              <button type="button" onClick={() => setCreating(false)} aria-label={t('common.close')} className="flex h-11 w-11 items-center justify-center rounded-lg text-gray-600 hover:bg-gray-100">
                <X className="h-5 w-5" aria-hidden="true" />
              </button>
            </div>
            <form onSubmit={submit} className="space-y-4 overflow-y-auto px-6 py-5">
              <p className="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-900">{t('tasks.case.privacy').replace('{folio}', caseNumber)}</p>
              <div>
                <label htmlFor={`${uid}-kind`} className={LABEL}>
                  {t('tasks.case.f_kind')}
                </label>
                <select id={`${uid}-kind`} required value={kindId} onChange={(e) => setKindId(e.target.value)} className={FIELD}>
                  <option value="">{t('tasks.case.f_kind_choose')}</option>
                  {kinds.map((k) => (
                    <option key={k.id} value={k.id}>
                      {k.label_es}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label htmlFor={`${uid}-assignee`} className={LABEL}>
                  {t('tasks.f_assignee')}
                </label>
                <select id={`${uid}-assignee`} value={assignedTo} onChange={(e) => setAssignedTo(e.target.value)} className={FIELD}>
                  <option value="">{t('tasks.case.f_unassigned')}</option>
                  {assignees.map((a) => (
                    <option key={a.id} value={a.id}>
                      {a.name}
                    </option>
                  ))}
                </select>
                <p className="mt-1 text-xs text-gray-600">{t('tasks.case.f_assignee_hint')}</p>
              </div>
              <div>
                <label htmlFor={`${uid}-due`} className={LABEL}>
                  {t('tasks.f_due')}
                </label>
                <input id={`${uid}-due`} type="date" value={dueAt} onChange={(e) => setDueAt(e.target.value)} className={FIELD} />
              </div>
              <div className="flex items-center justify-end gap-3 border-t border-gray-100 pt-4">
                <button type="button" onClick={() => setCreating(false)} className="min-h-11 rounded-lg border border-gray-300 px-4 text-sm font-medium text-gray-700 hover:bg-gray-50">
                  {t('common.cancel')}
                </button>
                <button type="submit" disabled={!kindId || busy} className="min-h-11 rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon hover:bg-turquesa-hover disabled:opacity-50">
                  {t('tasks.case.create')}
                </button>
              </div>
            </form>
          </div>
        </ModalShell>
      )}

      {unlinking && (
        <ModalShell onClose={() => setUnlinking(null)} className="fixed inset-0 z-50 flex items-center justify-center bg-carbon/60 p-4 backdrop-blur-sm">
          <div className="w-full max-w-md rounded-xl bg-white shadow-2xl">
            <div className="flex items-center gap-2 border-b border-gray-100 px-6 py-4">
              <Link2Off className="h-5 w-5 text-alerta-dark" aria-hidden="true" />
              <h3 className="text-base font-bold text-carbon">{t('tasks.case.unlink_title')}</h3>
            </div>
            <div className="space-y-3 px-6 py-5 text-sm text-carbon">
              <p className="break-words font-semibold">{unlinking.name}</p>
              <p className="rounded-lg border border-gray-200 bg-gray-50 p-3 text-xs text-gray-700">{t('tasks.case.unlink_body')}</p>
            </div>
            <div className="flex items-center justify-end gap-3 border-t border-gray-100 px-6 py-4">
              <button type="button" onClick={() => setUnlinking(null)} className="min-h-11 rounded-lg border border-gray-300 px-4 text-sm font-medium text-gray-700 hover:bg-gray-50">
                {t('common.cancel')}
              </button>
              <button type="button" onClick={confirmUnlink} disabled={busy} className="inline-flex min-h-11 items-center gap-2 rounded-lg bg-carbon px-4 text-sm font-semibold text-white hover:bg-carbon-light disabled:opacity-60">
                <Link2Off className="h-4 w-4" aria-hidden="true" />
                {t('tasks.case.unlink_confirm')}
              </button>
            </div>
          </div>
        </ModalShell>
      )}
    </div>
  );
};
