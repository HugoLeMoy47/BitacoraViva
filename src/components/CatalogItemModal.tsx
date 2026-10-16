import React, { useState } from 'react';
import { X } from 'lucide-react';
import { t } from '../lib/i18n';
import { friendlyError } from '../lib/errors';
import { CatalogItem } from '../types/database';
import { ModalShell } from './ModalShell';
import { DisabledReason, describedBy } from './DisabledReason';

// Un dato que se elige de un diccionario editable y se precisa con un detalle (idioma, religión). Tres campos a lo más:
// el valor, el detalle (solo si el valor lo admite) y, si ya había algo registrado, el motivo del cambio.
// Sin consentimiento sensible solo se ofrece «La persona no quiso responder»: es una respuesta, no un dato (D-14).
interface Props {
  title: string;
  hint: string;
  items: CatalogItem[];
  sensitiveOk: boolean;
  initialItemId: string | null;
  initialDetail: string;
  /** Sin detalle (estudios, estado civil, departamento): solo el valor y, si ya había uno, el motivo */
  withDetail?: boolean;
  onSubmit: (itemId: string | null, detail: string, reason: string) => Promise<void>;
  onClose: () => void;
}

const CONTROL = 'mt-1 w-full rounded-lg border border-gray-300 p-3 text-base focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa';

export const CatalogItemModal: React.FC<Props> = ({ title, hint, items, sensitiveOk, initialItemId, initialDetail, withDetail = true, onSubmit, onClose }) => {
  const uid = React.useId();
  const [itemId, setItemId] = useState(initialItemId ?? '');
  const [detail, setDetail] = useState(initialDetail);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const offered = items.filter((i) => i.is_active && (sensitiveOk || i.key === 'no_response'));
  const chosen = items.find((i) => i.id === itemId);
  const detailOk = withDetail && !!chosen && chosen.key !== 'no_response';
  const hadValue = !!initialItemId || initialDetail !== '';
  const changed = itemId !== (initialItemId ?? '') || (detailOk ? detail.trim() : '') !== initialDetail.trim();
  const needsReason = hadValue && changed;
  const blocked: string | null = !changed
    ? t('case_extra.unchanged')
    : needsReason && reason.trim() === ''
      ? t('case_extra.reason_missing')
      : null;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (blocked || busy) return;
    setBusy(true);
    setError(null);
    try {
      await onSubmit(itemId || null, detailOk ? detail.trim() : '', reason.trim());
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
          <p className="text-sm text-gray-700">{hint}</p>
          {!sensitiveOk && <p className="text-sm font-semibold text-gray-800">{t('diccionarios.only_no_response')}</p>}
          <div>
            <label className="block text-sm font-semibold text-gray-800" htmlFor={`${uid}-v`}>{t('diccionarios.field_value')}</label>
            <select id={`${uid}-v`} className={CONTROL} value={itemId} onChange={(e) => setItemId(e.target.value)}>
              <option value="">{t('common.not_recorded')}</option>
              {offered.map((i) => <option key={i.id} value={i.id}>{i.label_es}</option>)}
            </select>
          </div>
          {detailOk && (
            <div>
              <label className="block text-sm font-semibold text-gray-800" htmlFor={`${uid}-d`}>{t('diccionarios.field_detail')}</label>
              <input id={`${uid}-d`} className={CONTROL} maxLength={120} value={detail} onChange={(e) => setDetail(e.target.value)} autoComplete="off" />
            </div>
          )}
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
