import React, { useState } from 'react';
import { X } from 'lucide-react';
import { t } from '../lib/i18n';
import { friendlyError } from '../lib/errors';
import { StatusValue } from '../types/database';
import { ModalShell } from './ModalShell';
import { DisabledReason, describedBy } from './DisabledReason';

// Plan al ingreso (E14 fase 4b): un valor del mismo diccionario que la situación jurídica actual. Cambiarlo o quitarlo
// pide motivo. Dos campos a lo más: el valor y, si ya había uno, el motivo.
interface Props {
  values: StatusValue[];
  initialValueId: string | null;
  onSubmit: (valueId: string | null, reason: string) => Promise<void>;
  onClose: () => void;
}

const CONTROL = 'mt-1 w-full rounded-lg border border-gray-300 p-3 text-base focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa';

export const IntakePlanModal: React.FC<Props> = ({ values, initialValueId, onSubmit, onClose }) => {
  const uid = React.useId();
  const [valueId, setValueId] = useState(initialValueId ?? '');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const changed = valueId !== (initialValueId ?? '');
  const needsReason = !!initialValueId && changed;
  const blocked: string | null = !changed ? t('case_extra.unchanged') : needsReason && reason.trim() === '' ? t('case_extra.reason_missing') : null;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (blocked || busy) return;
    setBusy(true);
    setError(null);
    try {
      await onSubmit(valueId || null, reason.trim());
      onClose();
    } catch (err) {
      setError(friendlyError(err));
      setBusy(false);
    }
  };

  return (
    <ModalShell onClose={onClose} className="fixed inset-0 z-50 flex items-center justify-center bg-carbon/60 p-4 backdrop-blur-sm">
      <div className="flex max-h-[90vh] w-full max-w-lg flex-col rounded-xl bg-white shadow-2xl">
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4">
          <h3 className="font-title text-base font-bold text-carbon">{t('plan.title')}</h3>
          <button type="button" onClick={onClose} className="rounded-lg p-1.5 text-gray-500 hover:bg-gray-100" aria-label={t('common.close')}>
            <X className="h-5 w-5" aria-hidden="true" />
          </button>
        </div>
        <form onSubmit={submit} className="space-y-4 overflow-y-auto px-6 py-5">
          <p className="text-sm text-gray-700">{t('plan.hint')}</p>
          <div>
            <label className="block text-sm font-semibold text-gray-800" htmlFor={`${uid}-v`}>{t('plan.field')}</label>
            <select id={`${uid}-v`} className={CONTROL} value={valueId} onChange={(e) => setValueId(e.target.value)}>
              <option value="">{t('common.not_recorded')}</option>
              {values.map((v) => <option key={v.id} value={v.id}>{v.label_es}</option>)}
            </select>
          </div>
          {needsReason && (
            <div>
              <label className="block text-sm font-semibold text-gray-800" htmlFor={`${uid}-r`}>{t('case_extra.reason_label')}</label>
              <p className="text-sm text-gray-600">{t('case_extra.reason_hint')}</p>
              <input id={`${uid}-r`} className={CONTROL} value={reason} onChange={(e) => setReason(e.target.value)} />
            </div>
          )}
          {error && <p role="alert" className="rounded-lg border border-alerta-dark/40 bg-alerta-bg/40 p-3 text-sm font-semibold text-alerta-dark">{error}</p>}
          <div className="border-t border-gray-100 pt-3">
            <DisabledReason id={uid} reason={blocked} className="mb-2" />
            <div className="flex items-center justify-end gap-3">
              <button type="button" onClick={onClose} className="min-h-11 rounded-lg border border-gray-300 px-4 text-sm font-semibold text-gray-700 hover:bg-gray-50">{t('common.cancel')}</button>
              <button type="submit" disabled={!!blocked || busy} {...describedBy(uid, blocked)}
                className="min-h-11 rounded-lg bg-carbon px-5 text-sm font-bold text-white hover:bg-black disabled:cursor-not-allowed disabled:opacity-50">
                {busy ? t('case_extra.saving') : t('case_extra.save')}
              </button>
            </div>
          </div>
        </form>
      </div>
    </ModalShell>
  );
};
