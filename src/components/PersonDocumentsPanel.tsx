import React, { useState } from 'react';
import { FileText, Plus, X } from 'lucide-react';
import { t } from '../lib/i18n';
import { friendlyError } from '../lib/errors';
import { dataApi } from '../lib/data';
import { useCatalog } from '../lib/catalog';
import { useToast } from '../lib/toast';
import { formatDate } from '../lib/format';
import { PersonDocument } from '../types/database';
import { ModalShell } from './ModalShell';
import { DisabledReason, describedBy } from './DisabledReason';

// Documentos de la persona (E14 fase 1): tipo (catálogo que administra dirección) + número abierto. Lo que se cambia
// o se quita se CIERRA con su motivo y queda en el historial; nada se borra. Un modal nunca pide más de tres campos:
// tipo, número y, solo cuando ya hay un documento de ese tipo, el motivo del cambio.
type Mode = { kind: 'add' } | { kind: 'change'; doc: PersonDocument } | { kind: 'remove'; doc: PersonDocument };

const INPUT = 'w-full rounded-lg border border-gray-300 p-3 text-base focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa';

interface PanelProps {
  personId: string;
  documents: PersonDocument[];
  /** Quien opera expedientes puede registrar; el resto solo lee */
  canEdit: boolean;
  onChanged: () => Promise<void>;
}

export const PersonDocumentsPanel: React.FC<PanelProps> = ({ personId, documents, canEdit, onChanged }) => {
  const [mode, setMode] = useState<Mode | null>(null);
  const current = documents.filter((d) => !d.valid_to);
  const history = documents.filter((d) => d.valid_to);

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center justify-between gap-2 border-b pb-2">
        <h3 className="text-sm font-bold uppercase tracking-wider text-carbon">{t('person_docs.title')}</h3>
        {canEdit && (
          <button
            type="button"
            onClick={() => setMode({ kind: 'add' })}
            className="inline-flex min-h-11 items-center gap-1.5 rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50"
          >
            <Plus className="h-4 w-4" aria-hidden="true" />
            {t('person_docs.add')}
          </button>
        )}
      </div>
      <p className="mb-3 text-sm text-gray-600">{t('person_docs.subtitle')}</p>

      {current.length === 0 ? (
        <p className="rounded-xl border border-dashed border-gray-300 p-4 text-center text-sm text-gray-600">{t('person_docs.empty')}</p>
      ) : (
        <ul className="space-y-2">
          {current.map((d) => (
            <li key={d.id} className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-gray-200 bg-gray-50/50 p-3">
              <div className="flex items-start gap-2">
                <FileText className="mt-0.5 h-4 w-4 text-turquesa-dark" aria-hidden="true" />
                <div>
                  <p className="text-sm font-bold text-carbon">{d.type_label}</p>
                  <p className="font-mono text-sm text-gray-800">{d.document_number}</p>
                </div>
              </div>
              {canEdit && (
                <div className="flex gap-2">
                  <button type="button" onClick={() => setMode({ kind: 'change', doc: d })} className="min-h-11 rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50">
                    {t('person_docs.change')}
                  </button>
                  <button type="button" onClick={() => setMode({ kind: 'remove', doc: d })} className="min-h-11 rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-gray-700 hover:bg-gray-50">
                    {t('person_docs.remove')}
                  </button>
                </div>
              )}
            </li>
          ))}
        </ul>
      )}

      {history.length > 0 && (
        <details className="mt-3 text-sm text-gray-700">
          <summary className="cursor-pointer font-semibold">{t('person_docs.history')} ({history.length})</summary>
          <ul className="mt-2 space-y-1.5">
            {history.map((d) => (
              <li key={d.id} className="rounded-lg border border-gray-200 p-2">
                <span className="font-semibold">{d.type_label}</span> · <span className="font-mono">{d.document_number}</span>
                <span className="block text-gray-600">
                  {t('person_docs.closed_on')} {formatDate(d.valid_to ?? '')}{d.change_reason ? ` — ${d.change_reason}` : ''}
                </span>
              </li>
            ))}
          </ul>
        </details>
      )}

      {mode && <DocumentModal personId={personId} mode={mode} current={current} onClose={() => setMode(null)} onChanged={onChanged} />}
    </div>
  );
};

const DocumentModal: React.FC<{
  personId: string;
  mode: Mode;
  current: PersonDocument[];
  onClose: () => void;
  onChanged: () => Promise<void>;
}> = ({ personId, mode, current, onClose, onChanged }) => {
  const uid = React.useId();
  const toast = useToast();
  const { documentTypes } = useCatalog();
  const types = documentTypes.filter((d) => d.is_active);
  const [typeId, setTypeId] = useState(mode.kind === 'add' ? '' : mode.doc.document_type_id);
  const [number, setNumber] = useState(mode.kind === 'change' ? mode.doc.document_number : '');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const existing = current.find((d) => d.document_type_id === typeId);
  const isRemove = mode.kind === 'remove';
  const needsReason = isRemove || (!!existing && existing.document_number !== number.trim());
  const blocked: string | null = isRemove
    ? reason.trim() === '' ? t('person_docs.need_reason') : null
    : typeId === ''
      ? t('person_docs.need_type')
      : number.trim() === ''
        ? t('person_docs.need_number')
        : existing && existing.document_number === number.trim()
          ? t('case_extra.unchanged')
          : needsReason && reason.trim() === ''
            ? t('person_docs.need_reason')
            : null;

  const title = mode.kind === 'add' ? t('person_docs.modal_add') : mode.kind === 'change' ? t('person_docs.modal_change') : t('person_docs.modal_remove');

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (blocked || busy) return;
    setBusy(true);
    setError(null);
    try {
      if (mode.kind === 'remove') await dataApi.removePersonDocument(mode.doc.id, reason.trim());
      else await dataApi.setPersonDocument(personId, typeId, number.trim(), reason.trim());
      toast.success(t(isRemove ? 'person_docs.removed' : 'person_docs.saved'));
      await onChanged();
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
          {isRemove ? (
            <>
              <p className="text-sm text-gray-700">
                <span className="font-semibold">{mode.doc.type_label}</span> · <span className="font-mono">{mode.doc.document_number}</span>
              </p>
              <p className="text-sm text-gray-700">{t('person_docs.remove_hint')}</p>
            </>
          ) : (
            <>
              <div>
                <label className="block text-sm font-semibold text-gray-800" htmlFor={`${uid}-t`}>{t('person_docs.field_type')}</label>
                {types.length === 0 ? (
                  <p className="mt-1 text-sm text-gray-700">{t('person_docs.no_types')}</p>
                ) : (
                  <select id={`${uid}-t`} className={`mt-1 ${INPUT}`} value={typeId} onChange={(e) => setTypeId(e.target.value)} disabled={mode.kind === 'change'}>
                    <option value="">{t('person_docs.field_type_placeholder')}</option>
                    {types.map((d) => <option key={d.id} value={d.id}>{d.label_es}</option>)}
                  </select>
                )}
              </div>
              <div>
                <label className="block text-sm font-semibold text-gray-800" htmlFor={`${uid}-n`}>{t('person_docs.field_number')}</label>
                <input id={`${uid}-n`} className={`mt-1 ${INPUT}`} maxLength={60} value={number} onChange={(e) => setNumber(e.target.value)} />
              </div>
            </>
          )}
          {needsReason && (
            <div>
              <label className="block text-sm font-semibold text-gray-800" htmlFor={`${uid}-r`}>
                {isRemove ? t('person_docs.remove_reason') : t('case_extra.reason_label')}
              </label>
              {!isRemove && <p className="text-sm text-gray-600">{t('person_docs.reason_hint')}</p>}
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
                {busy ? t('case_extra.saving') : isRemove ? t('person_docs.confirm_remove') : t('case_extra.save')}
              </button>
            </div>
          </div>
        </form>
      </div>
    </ModalShell>
  );
};
