import React, { useId, useState } from 'react';
import { Save } from 'lucide-react';
import { t } from '../lib/i18n';
import { ShiftNoteScope, TaskSetting } from '../types/database';

// Ajustes de operación (BV-7.13), sólo dirección. Existen porque dos decisiones de este producto no
// tienen una respuesta correcta que el código pueda elegir por la organización: quién lee las notas de
// turno y qué tanto se deja acaparar el pool. La advertencia va JUNTO al control y CAMBIA según lo que se
// elija: un aviso que dice lo mismo pase lo que pase se vuelve invisible en la segunda visita.

type Values = Pick<TaskSetting, 'shift_note_scope' | 'shift_note_days' | 'pool_max_unstarted' | 'pool_release_days'>;

interface TaskSettingsViewProps {
  setting: TaskSetting | null;
  saving: boolean;
  onSave: (values: Values) => Promise<boolean>;
}

const DEFAULTS: Values = { shift_note_scope: 'all', shift_note_days: 30, pool_max_unstarted: 0, pool_release_days: 1 };
const FIELD = 'mt-1 block min-h-11 w-full rounded-lg border border-gray-300 bg-white px-3 text-sm focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa';
const SCOPES: ShiftNoteScope[] = ['all', 'area', 'own'];

/** Número entero no negativo: lo que no se pueda leer cuenta como 0 («sin tope», «sin límite»). */
const toInt = (raw: string): number => {
  const n = Math.floor(Number(raw));
  return Number.isFinite(n) && n > 0 ? n : 0;
};

export const TaskSettingsView: React.FC<TaskSettingsViewProps> = ({ setting, saving, onSave }) => {
  const uid = useId();
  const initial: Values = setting
    ? { shift_note_scope: setting.shift_note_scope, shift_note_days: setting.shift_note_days, pool_max_unstarted: setting.pool_max_unstarted, pool_release_days: setting.pool_release_days }
    : DEFAULTS;
  const [values, setValues] = useState<Values>(initial);
  const dirty = JSON.stringify(values) !== JSON.stringify(initial);
  const set = (patch: Partial<Values>) => setValues((v) => ({ ...v, ...patch }));

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (dirty && !saving) await onSave(values);
  };

  return (
    <form onSubmit={submit} className="space-y-4">
      <p className="text-sm text-gray-600">{t('tasks.settings.intro')}</p>

      <section className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm sm:p-5">
        <h3 className="text-base font-bold text-carbon">{t('tasks.settings.notes_title')}</h3>
        <p className="mb-3 mt-0.5 text-xs text-gray-600">{t('tasks.settings.notes_hint')}</p>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label htmlFor={`${uid}-scope`} className="block text-xs font-semibold text-gray-700">
              {t('tasks.settings.f_scope')}
            </label>
            <select id={`${uid}-scope`} value={values.shift_note_scope} onChange={(e) => set({ shift_note_scope: e.target.value as ShiftNoteScope })} className={FIELD}>
              {SCOPES.map((s) => (
                <option key={s} value={s}>
                  {t(`tasks.settings.scope_${s}`)}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label htmlFor={`${uid}-days`} className="block text-xs font-semibold text-gray-700">
              {t('tasks.settings.f_days')}
            </label>
            <input id={`${uid}-days`} type="number" min={0} max={3650} inputMode="numeric" value={values.shift_note_days} onChange={(e) => set({ shift_note_days: toInt(e.target.value) })} className={FIELD} />
            <p className="mt-1 text-xs text-gray-600">{t('tasks.settings.f_days_hint')}</p>
          </div>
        </div>
        {/* La advertencia cambia con la elección: describe lo que implica ESA opción */}
        <p
          role="note"
          className={`mt-3 rounded-lg border p-3 text-xs ${values.shift_note_scope === 'all' ? 'border-amber-200 bg-amber-50 text-amber-900' : 'border-gray-200 bg-gray-50 text-gray-700'}`}
        >
          {t(`tasks.settings.warn_${values.shift_note_scope}`)}
        </p>
      </section>

      <section className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm sm:p-5">
        <h3 className="text-base font-bold text-carbon">{t('tasks.settings.pool_title')}</h3>
        <p className="mb-3 mt-0.5 text-xs text-gray-600">{t('tasks.settings.pool_hint')}</p>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label htmlFor={`${uid}-max`} className="block text-xs font-semibold text-gray-700">
              {t('tasks.settings.f_max')}
            </label>
            <input id={`${uid}-max`} type="number" min={0} max={100} inputMode="numeric" value={values.pool_max_unstarted} onChange={(e) => set({ pool_max_unstarted: toInt(e.target.value) })} className={FIELD} />
            <p className="mt-1 text-xs text-gray-600">{t('tasks.settings.f_max_hint')}</p>
          </div>
          <div>
            <label htmlFor={`${uid}-release`} className="block text-xs font-semibold text-gray-700">
              {t('tasks.settings.f_release')}
            </label>
            <input id={`${uid}-release`} type="number" min={0} max={365} inputMode="numeric" value={values.pool_release_days} onChange={(e) => set({ pool_release_days: toInt(e.target.value) })} className={FIELD} />
            <p className="mt-1 text-xs text-gray-600">{t('tasks.settings.f_release_hint')}</p>
          </div>
        </div>
        <p role="note" className="mt-3 rounded-lg border border-gray-200 bg-gray-50 p-3 text-xs text-gray-700">
          {t(values.pool_max_unstarted === 0 ? 'tasks.settings.warn_pool_open' : 'tasks.settings.warn_pool_cap').replace('{n}', String(values.pool_max_unstarted))}
        </p>
      </section>

      <div className="flex justify-end">
        <button
          type="submit"
          disabled={!dirty || saving}
          className="inline-flex min-h-11 items-center gap-2 rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon hover:bg-turquesa-hover disabled:opacity-50"
        >
          <Save className="h-4 w-4" aria-hidden="true" />
          {t('tasks.settings.save')}
        </button>
      </div>
    </form>
  );
};
