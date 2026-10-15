import React, { useState } from 'react';
import { CalendarDays, X } from 'lucide-react';
import { t } from '../lib/i18n';
import { friendlyError } from '../lib/errors';
import { dataApi } from '../lib/data';
import { useToast } from '../lib/toast';
import { DatePrecision, formatFlexDate, startsInFuture, toStoredDate } from '../lib/flexDate';
import { CaseDate, CaseDateKind } from '../types/database';
import { ModalShell } from './ModalShell';
import { DisabledReason, describedBy } from './DisabledReason';
import { FlexibleDateInput } from './FlexibleDateInput';

// Las cuatro fechas del caso (E14 fase 2): ingreso y egreso a la nación y al albergue, cada una con la precisión que
// se conoce. Lo corregido o quitado se cierra con su motivo y queda en el historial; nada se borra.
export const DATE_KINDS: CaseDateKind[] = ['nation_entry', 'nation_exit', 'shelter_entry', 'shelter_exit'];

interface PanelProps {
  caseId: string;
  dates: CaseDate[];
  /** Texto «Mmmm, yyyy» que traía el caso antes de E14: se muestra solo si no hay fecha de ingreso a la nación */
  legacyEntryText?: string | null;
  canEdit: boolean;
  onChanged: () => Promise<void>;
}

const BTN = 'mt-1 inline-flex min-h-11 items-center rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50';

export const CaseDatesPanel: React.FC<PanelProps> = ({ caseId, dates, legacyEntryText, canEdit, onChanged }) => {
  const [editing, setEditing] = useState<CaseDateKind | null>(null);
  const current = (k: CaseDateKind) => dates.find((d) => d.kind === k && !d.valid_to);
  const history = dates.filter((d) => d.valid_to);

  return (
    <div>
      <h3 className="mb-4 border-b pb-2 text-sm font-bold uppercase tracking-wider text-carbon">{t('dates.title')}</h3>
      <p className="mb-3 text-sm text-gray-600">{t('dates.subtitle')}</p>
      <div className="grid grid-cols-1 gap-4 text-xs md:grid-cols-2">
        {DATE_KINDS.map((k) => {
          const d = current(k);
          return (
            <div key={k}>
              <span className="block text-gray-500">{t(`dates.kind.${k}`)}</span>
              <span className="text-sm font-semibold text-carbon">
                {d ? formatFlexDate(d.value, d.precision) : k === 'nation_entry' && legacyEntryText ? `${legacyEntryText} (${t('dates.legacy_note')})` : t('common.not_recorded')}
              </span>
              {canEdit && (
                <button type="button" onClick={() => setEditing(k)} className={BTN}>
                  <CalendarDays className="mr-1.5 h-4 w-4" aria-hidden="true" />
                  {d ? t('dates.change') : t('dates.register')}
                </button>
              )}
            </div>
          );
        })}
      </div>

      {history.length > 0 && (
        <details className="mt-3 text-sm text-gray-700">
          <summary className="cursor-pointer font-semibold">{t('dates.history')} ({history.length})</summary>
          <ul className="mt-2 space-y-1.5">
            {history.map((d) => (
              <li key={d.id} className="rounded-lg border border-gray-200 p-2">
                <span className="font-semibold">{t(`dates.kind.${d.kind}`)}</span>: {formatFlexDate(d.value, d.precision)}
                {d.change_reason ? <span className="block text-gray-600">{t('dates.closed_because')} {d.change_reason}</span> : null}
              </li>
            ))}
          </ul>
        </details>
      )}

      {editing && (
        <DateModal caseId={caseId} kind={editing} existing={current(editing)} onClose={() => setEditing(null)} onChanged={onChanged} />
      )}
    </div>
  );
};

const DateModal: React.FC<{
  caseId: string;
  kind: CaseDateKind;
  existing?: CaseDate;
  onClose: () => void;
  onChanged: () => Promise<void>;
}> = ({ caseId, kind, existing, onClose, onChanged }) => {
  const uid = React.useId();
  const toast = useToast();
  const [precision, setPrecision] = useState<DatePrecision>(existing?.precision ?? 'day');
  const [raw, setRaw] = useState(() => {
    if (!existing) return '';
    return existing.precision === 'year' ? existing.value.slice(0, 4) : existing.precision === 'month' ? existing.value.slice(0, 7) : existing.value;
  });
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const stored = toStoredDate(precision, raw);
  const unchanged = !!existing && !!stored && existing.value === stored && existing.precision === precision;
  const needsReason = !!existing && !!stored && !unchanged;
  const futureProblem = stored && startsInFuture(stored) ? t('dates.reason_future') : null;
  const blocked: string | null = !stored
    ? t('dates.reason_missing_value')
    : futureProblem
      ? futureProblem
      : unchanged
        ? t('case_extra.unchanged')
        : needsReason && reason.trim() === ''
          ? t('case_extra.reason_missing')
          : null;
  const removeBlocked: string | null = reason.trim() === '' ? t('dates.reason_remove') : null;

  const run = async (action: () => Promise<unknown>, doneKey: string) => {
    setBusy(true);
    setError(null);
    try {
      await action();
      toast.success(t(doneKey));
      await onChanged();
      onClose();
    } catch (err) {
      setError(friendlyError(err));
      setBusy(false);
    }
  };

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    if (blocked || busy || !stored) return;
    void run(() => dataApi.setCaseDate(caseId, kind, stored, precision, reason.trim()), 'dates.saved');
  };

  return (
    <ModalShell onClose={onClose} className="fixed inset-0 z-50 flex items-center justify-center bg-carbon/60 p-4 backdrop-blur-sm">
      <div className="flex max-h-[90vh] w-full max-w-lg flex-col rounded-xl bg-white shadow-2xl">
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4">
          <h3 className="font-title text-base font-bold text-carbon">{t(`dates.kind.${kind}`)}</h3>
          <button type="button" onClick={onClose} className="rounded-lg p-1.5 text-gray-500 hover:bg-gray-100" aria-label={t('common.close')}>
            <X className="h-5 w-5" aria-hidden="true" />
          </button>
        </div>
        <form onSubmit={submit} className="space-y-4 overflow-y-auto px-6 py-5">
          <p className="text-sm text-gray-700">{t('dates.modal_hint')}</p>
          <FlexibleDateInput
            id={uid}
            label={t(`dates.kind.${kind}`)}
            precision={precision}
            value={raw}
            onChange={(p, v) => { setPrecision(p); setRaw(v); }}
            problem={futureProblem}
          />
          {needsReason && (
            <div>
              <label className="block text-sm font-semibold text-gray-800" htmlFor={`${uid}-r`}>{t('case_extra.reason_label')}</label>
              <p className="text-sm text-gray-600">{t('case_extra.reason_hint')}</p>
              <input id={`${uid}-r`} className="mt-1 w-full rounded-lg border border-gray-300 p-3 text-base focus:border-turquesa focus:outline-none" value={reason} onChange={(e) => setReason(e.target.value)} />
            </div>
          )}
          {error && <p role="alert" className="rounded-lg border border-alerta-dark/40 bg-alerta-bg/40 p-3 text-sm font-semibold text-alerta-dark">{error}</p>}
          <div className="border-t border-gray-100 pt-3">
            <DisabledReason id={uid} reason={blocked} className="mb-2" />
            <div className="flex flex-wrap items-center justify-end gap-3">
              {existing && (
                <div className="mr-auto">
                  <button
                    type="button"
                    disabled={!!removeBlocked || busy}
                    {...describedBy(`${uid}-q`, removeBlocked)}
                    onClick={() => void run(() => dataApi.setCaseDate(caseId, kind, null, null, reason.trim()), 'dates.removed')}
                    className="min-h-11 rounded-lg border border-gray-300 px-4 text-sm font-semibold text-gray-700 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    {t('dates.remove')}
                  </button>
                </div>
              )}
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
            {existing && <DisabledReason id={`${uid}-q`} reason={removeBlocked} className="mt-2" />}
          </div>
        </form>
      </div>
    </ModalShell>
  );
};
