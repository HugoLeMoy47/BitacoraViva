import React, { useState } from 'react';
import { t } from '../lib/i18n';
import { friendlyError } from '../lib/errors';
import { dataApi } from '../lib/data';
import { useToast } from '../lib/toast';
import { CatalogItem } from '../types/database';
import { DisabledReason, describedBy } from './DisabledReason';

// Necesidades específicas (E14 fase 4b): una lista de casillas con lo que se marca, de un diccionario editable por dirección
// y Trabajo Social. Son datos sensibles (D-14): sin consentimiento sensible solo se puede registrar «La persona no quiso
// responder» (y desmarcar lo que ya estaba). Quitar una necesidad pide motivo; nada se borra. No es un modal: son casillas.
interface Props {
  caseId: string;
  items: CatalogItem[];
  currentIds: string[];
  sensitiveOk: boolean;
  canEdit: boolean;
  onChanged: () => Promise<void>;
}

export const CaseNeedsPanel: React.FC<Props> = ({ caseId, items, currentIds, sensitiveOk, canEdit, onChanged }) => {
  const uid = React.useId();
  const toast = useToast();
  const active = items.filter((i) => i.is_active || currentIds.includes(i.id));
  const [selected, setSelected] = useState<string[]>(currentIds);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const noResponse = active.find((i) => i.key === 'no_response');
  const removed = currentIds.filter((id) => !selected.includes(id));
  const added = selected.filter((id) => !currentIds.includes(id));
  const changed = removed.length > 0 || added.length > 0;
  const blocked: string | null = !changed
    ? t('case_extra.unchanged')
    : removed.length > 0 && reason.trim() === ''
      ? t('needs.reason_remove')
      : null;

  const toggle = (item: CatalogItem) => {
    setSelected((prev) => {
      if (prev.includes(item.id)) return prev.filter((x) => x !== item.id);
      // «No quiso responder» no se combina con otras necesidades: marcar una desmarca la otra
      return item.key === 'no_response' ? [item.id] : [...prev.filter((x) => x !== noResponse?.id), item.id];
    });
  };

  const save = async () => {
    if (blocked || busy) return;
    setBusy(true);
    setError(null);
    try {
      await dataApi.setCaseNeeds(caseId, selected, reason);
      toast.success(t('needs.saved'));
      await onChanged();
      setReason('');
    } catch (e) {
      setError(friendlyError(e));
    }
    setBusy(false);
  };

  return (
    <div>
      <h3 className="mb-4 border-b pb-2 text-sm font-bold uppercase tracking-wider text-carbon">{t('needs.title')}</h3>
      <p className="mb-3 text-sm text-gray-600">{t('needs.subtitle')}</p>

      {!canEdit ? (
        <p className="text-sm font-semibold text-carbon">
          {currentIds.length === 0 ? t('common.not_recorded') : currentIds.map((id) => items.find((i) => i.id === id)?.label_es).filter(Boolean).join(' · ')}
        </p>
      ) : (
        <>
          {!sensitiveOk && <p className="mb-2 text-sm font-semibold text-gray-800">{t('diccionarios.only_no_response')}</p>}
          <fieldset>
            <legend className="sr-only">{t('needs.title')}</legend>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
              {active.map((i) => {
                const checked = selected.includes(i.id);
                const disabled = !sensitiveOk && i.key !== 'no_response' && !checked;
                return (
                  <label key={i.id} className={`flex min-h-11 items-center gap-3 rounded-xl border p-3 text-sm ${checked ? 'border-turquesa bg-claro font-semibold text-carbon' : 'border-gray-200 text-gray-800'} ${disabled ? 'opacity-60' : 'cursor-pointer'}`}>
                    <input type="checkbox" className="h-4 w-4 rounded border-gray-300 text-turquesa" checked={checked} disabled={disabled} onChange={() => toggle(i)} />
                    <span>{i.label_es}</span>
                  </label>
                );
              })}
            </div>
          </fieldset>
          {removed.length > 0 && (
            <div className="mt-3">
              <label className="block text-sm font-semibold text-gray-800" htmlFor={`${uid}-r`}>{t('case_extra.reason_label')}</label>
              <p className="text-sm text-gray-600">{t('needs.reason_hint')}</p>
              <input id={`${uid}-r`} className="mt-1 w-full rounded-lg border border-gray-300 p-3 text-base focus:border-turquesa focus:outline-none" value={reason} onChange={(e) => setReason(e.target.value)} />
            </div>
          )}
          {error && <p role="alert" className="mt-3 rounded-lg border border-alerta-dark/40 bg-alerta-bg/40 p-3 text-sm font-semibold text-alerta-dark">{error}</p>}
          <div className="mt-3">
            <DisabledReason id={uid} reason={blocked} className="mb-2" />
            <button type="button" onClick={() => void save()} disabled={!!blocked || busy} {...describedBy(uid, blocked)}
              className="min-h-11 rounded-lg bg-carbon px-5 text-sm font-bold text-white hover:bg-black disabled:cursor-not-allowed disabled:opacity-50">
              {busy ? t('case_extra.saving') : t('needs.save')}
            </button>
          </div>
        </>
      )}
    </div>
  );
};
