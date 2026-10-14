import React, { useState } from 'react';
import { X } from 'lucide-react';
import { t } from '../lib/i18n';
import { friendlyError } from '../lib/errors';
import { ModalShell } from './ModalShell';
import { DisabledReason, describedBy } from './DisabledReason';

// Modal corto de UN dato (religión, referencia heredada, detalle de un marcador): un campo y, solo si ya había un
// valor registrado, el motivo del cambio. Nunca más de tres campos (norma de modales). El motivo se pide cuando el
// valor cambia: lo corregido queda en el registro de cambios, no se sobrescribe en silencio (Ethos C8).
interface SmallFieldModalProps {
  title: string;
  hint?: string;
  label: string;
  initialValue: string;
  maxLength: number;
  multiline?: boolean;
  /** Ya había un valor registrado: cambiarlo o quitarlo exige motivo */
  reasonWhenChanged: boolean;
  /** Se permite dejar el campo vacío (quita el dato) */
  allowClear: boolean;
  onSubmit: (value: string, reason: string) => Promise<void>;
  onClose: () => void;
}

const INPUT = 'w-full rounded-lg border border-gray-300 p-3 text-base focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa';

export const SmallFieldModal: React.FC<SmallFieldModalProps> = ({
  title,
  hint,
  label,
  initialValue,
  maxLength,
  multiline = false,
  reasonWhenChanged,
  allowClear,
  onSubmit,
  onClose,
}) => {
  const uid = React.useId();
  const [value, setValue] = useState(initialValue);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const changed = value.trim() !== initialValue.trim();
  const needsReason = reasonWhenChanged && changed;
  const blocked: string | null = !changed
    ? t('case_extra.unchanged')
    : value.trim() === '' && !allowClear
      ? t('case_extra.value_missing')
      : needsReason && reason.trim() === ''
        ? t('case_extra.reason_missing')
        : null;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (blocked || busy) return;
    setBusy(true);
    setError(null);
    try {
      await onSubmit(value.trim(), reason.trim());
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
          <h3 className="font-title text-base font-bold text-carbon">{title}</h3>
          <button type="button" onClick={onClose} className="rounded-lg p-1.5 text-gray-500 hover:bg-gray-100" aria-label={t('common.close')}>
            <X className="h-5 w-5" aria-hidden="true" />
          </button>
        </div>
        <form onSubmit={submit} className="space-y-4 overflow-y-auto px-6 py-5">
          {hint && <p className="text-sm text-gray-700">{hint}</p>}
          <div>
            <label className="block text-sm font-semibold text-gray-800" htmlFor={`${uid}-v`}>{label}</label>
            {multiline ? (
              <textarea id={`${uid}-v`} className={`mt-1 ${INPUT}`} rows={4} maxLength={maxLength} value={value} onChange={(e) => setValue(e.target.value)} />
            ) : (
              <input id={`${uid}-v`} className={`mt-1 ${INPUT}`} maxLength={maxLength} value={value} onChange={(e) => setValue(e.target.value)} />
            )}
          </div>
          {needsReason && (
            <div>
              <label className="block text-sm font-semibold text-gray-800" htmlFor={`${uid}-r`}>{t('case_extra.reason_label')}</label>
              <p className="text-sm text-gray-600">{t('case_extra.reason_hint')}</p>
              <input id={`${uid}-r`} className={`mt-1 ${INPUT}`} value={reason} onChange={(e) => setReason(e.target.value)} />
            </div>
          )}
          {error && (
            <p role="alert" className="rounded-lg border border-alerta-dark/40 bg-alerta-bg/40 p-3 text-sm font-semibold text-alerta-dark">{error}</p>
          )}
          <div className="border-t border-gray-100 pt-3">
            <DisabledReason id={uid} reason={blocked} className="mb-2" />
            <div className="flex items-center justify-end gap-3">
              <button type="button" onClick={onClose} className="min-h-11 rounded-lg border border-gray-300 px-4 text-sm font-semibold text-gray-700 hover:bg-gray-50">
                {t('common.cancel')}
              </button>
              <button
                type="submit"
                disabled={!!blocked || busy}
                {...describedBy(uid, blocked)}
                className="min-h-11 rounded-lg bg-carbon px-5 text-sm font-bold text-white hover:bg-black disabled:cursor-not-allowed disabled:opacity-50"
              >
                {busy ? t('case_extra.saving') : t('case_extra.save')}
              </button>
            </div>
          </div>
        </form>
      </div>
    </ModalShell>
  );
};
