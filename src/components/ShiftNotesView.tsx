import React, { useId, useState } from 'react';
import { MapPin, Moon, Send, Sun, Sunset, Undo2, User } from 'lucide-react';
import { t } from '../lib/i18n';
import { formatDate } from '../lib/format';
import { ShiftNoteInput } from '../lib/tasks';
import { ShiftKind, ShiftNote, TaskSetting, WorkArea } from '../types/database';

// Notas de turno (BV-7.12): recados en texto libre para el turno siguiente. Se agregan y no se editan,
// y retirar una es baja lógica (nada se borra). No son entradas de bitácora de un caso.
//
// Lo delicado: son notas libres sobre la operación diaria y las lee gente que puede estar sólo de paso.
// Quién las lee y desde cuándo es un ajuste de la organización, no una constante del código; aquí se le
// dice a cada persona exactamente qué está viendo, para que nadie crea que lo que ve es todo (ni que lo
// que escribe lo lee más gente de la que cree).

interface ShiftNotesViewProps {
  notes: ShiftNote[];
  workAreas: WorkArea[];
  userNames: Record<string, string>;
  setting: TaskSetting | null;
  me: string;
  isManagement: boolean;
  busyId: string | null;
  saving: boolean;
  onAdd: (input: ShiftNoteInput) => Promise<boolean>;
  onRetract: (id: string) => Promise<boolean>;
}

const SHIFTS: ShiftKind[] = ['general', 'morning', 'afternoon', 'night'];
const SHIFT_ICON: Record<ShiftKind, React.ReactNode> = {
  general: null,
  morning: <Sun className="h-3.5 w-3.5" aria-hidden="true" />,
  afternoon: <Sunset className="h-3.5 w-3.5" aria-hidden="true" />,
  night: <Moon className="h-3.5 w-3.5" aria-hidden="true" />,
};
const FIELD = 'mt-1 block min-h-11 w-full rounded-lg border border-gray-300 bg-white px-3 text-sm focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa';

export const ShiftNotesView: React.FC<ShiftNotesViewProps> = ({ notes, workAreas, userNames, setting, me, isManagement, busyId, saving, onAdd, onRetract }) => {
  const uid = useId();
  const [body, setBody] = useState('');
  const [shift, setShift] = useState<ShiftKind>('general');
  const [workAreaId, setWorkAreaId] = useState('');
  const [confirming, setConfirming] = useState<string | null>(null);

  const areaLabel = (id: string | null) => workAreas.find((a) => a.id === id)?.label_es;
  const scope = setting?.shift_note_scope ?? 'all';
  const days = setting?.shift_note_days ?? 30;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!body.trim() || saving) return;
    const ok = await onAdd({ body, shift, work_area_id: workAreaId || null });
    if (ok) setBody('');
  };

  const retract = async (id: string) => {
    if (await onRetract(id)) setConfirming(null);
  };

  return (
    <div className="space-y-4">
      <p className="rounded-lg border border-gray-200 bg-white p-3 text-xs text-gray-700" role="note">
        {t(`tasks.notes.scope_${scope}`)} {days === 0 ? t('tasks.notes.window_all') : t('tasks.notes.window_days').replace('{n}', String(days))}
      </p>

      <form onSubmit={submit} className="space-y-3 rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
        <div>
          <label htmlFor={`${uid}-body`} className="block text-xs font-semibold text-gray-700">
            {t('tasks.notes.f_body')}
          </label>
          <textarea
            id={`${uid}-body`}
            rows={3}
            maxLength={2000}
            value={body}
            onChange={(e) => setBody(e.target.value)}
            className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa"
          />
          <p className="mt-1 text-xs text-amber-900">{t('tasks.notes.warning')}</p>
        </div>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <label className="block text-xs font-semibold text-gray-700">
            {t('tasks.notes.f_shift')}
            <select value={shift} onChange={(e) => setShift(e.target.value as ShiftKind)} className={FIELD}>
              {SHIFTS.map((s) => (
                <option key={s} value={s}>
                  {t(`tasks.notes.shift_${s}`)}
                </option>
              ))}
            </select>
          </label>
          <label className="block text-xs font-semibold text-gray-700">
            {t('tasks.notes.f_work_area')}
            <select value={workAreaId} onChange={(e) => setWorkAreaId(e.target.value)} className={FIELD}>
              <option value="">{t('tasks.f_none')}</option>
              {workAreas.filter((a) => !a.archived_at).map((a) => (
                <option key={a.id} value={a.id}>
                  {a.label_es}
                </option>
              ))}
            </select>
          </label>
        </div>
        <div className="flex justify-end">
          <button
            type="submit"
            disabled={!body.trim() || saving}
            className="inline-flex min-h-11 items-center gap-2 rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon hover:bg-turquesa-hover disabled:opacity-50"
          >
            <Send className="h-4 w-4" aria-hidden="true" />
            {t('tasks.notes.submit')}
          </button>
        </div>
      </form>

      {notes.length === 0 ? (
        <p className="rounded-xl border border-dashed border-gray-300 bg-white px-4 py-10 text-center text-sm text-gray-600">{t('tasks.notes.empty')}</p>
      ) : (
        <ul className="space-y-3">
          {notes.map((n) => {
            const mine = n.created_by === me;
            const retracted = !!n.archived_at;
            return (
              <li key={n.id} className={`rounded-xl border p-4 shadow-sm ${retracted ? 'border-gray-200 bg-gray-50' : 'border-gray-200 bg-white'}`}>
                <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-gray-600">
                  <span className="font-semibold text-carbon">{formatDate(n.note_date)}</span>
                  <span className="inline-flex items-center gap-1">
                    {SHIFT_ICON[n.shift]}
                    {t(`tasks.notes.shift_${n.shift}`)}
                  </span>
                  {areaLabel(n.work_area_id) && (
                    <span className="inline-flex items-center gap-1">
                      <MapPin className="h-3.5 w-3.5" aria-hidden="true" />
                      {areaLabel(n.work_area_id)}
                    </span>
                  )}
                  <span className="inline-flex items-center gap-1">
                    <User className="h-3.5 w-3.5" aria-hidden="true" />
                    {n.created_by ? userNames[n.created_by] || t('tasks.assignee_former') : '—'}
                  </span>
                  {retracted && <span className="rounded bg-gray-200 px-1.5 py-0.5 font-semibold text-carbon">{t('tasks.notes.retracted')}</span>}
                </div>
                <p className={`mt-2 whitespace-pre-line break-words text-sm ${retracted ? 'text-gray-600 line-through' : 'text-carbon'}`}>{n.body}</p>

                {!retracted && (mine || isManagement) && (
                  <div className="mt-3">
                    {confirming === n.id ? (
                      <div className="flex flex-wrap items-center gap-2" role="group" aria-label={t('tasks.notes.retract')}>
                        <span className="text-xs text-gray-700">{t('tasks.notes.retract_confirm')}</span>
                        <button
                          type="button"
                          onClick={() => retract(n.id)}
                          disabled={busyId === n.id}
                          className="inline-flex min-h-11 items-center rounded-lg bg-carbon px-3 text-sm font-semibold text-white hover:bg-carbon-light disabled:opacity-60"
                        >
                          {t('tasks.notes.retract_yes')}
                        </button>
                        <button type="button" onClick={() => setConfirming(null)} className="inline-flex min-h-11 items-center rounded-lg border border-gray-300 bg-white px-3 text-sm font-medium text-gray-700 hover:bg-gray-50">
                          {t('common.cancel')}
                        </button>
                      </div>
                    ) : (
                      <button
                        type="button"
                        onClick={() => setConfirming(n.id)}
                        className="inline-flex min-h-11 items-center gap-1.5 rounded-lg border border-gray-300 bg-white px-3 text-sm font-medium text-gray-700 hover:bg-gray-50"
                      >
                        <Undo2 className="h-4 w-4" aria-hidden="true" />
                        {t('tasks.notes.retract')}
                      </button>
                    )}
                  </div>
                )}
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
};
