import React, { useEffect, useState } from 'react';
import { t } from '../lib/i18n';
import { friendlyError } from '../lib/errors';
import { dataApi } from '../lib/data';
import { useToast } from '../lib/toast';
import { DisabledReason, describedBy } from './DisabledReason';

// Autorizaciones firmadas en físico (ciclo «Ingreso y expediente»): fotografía de identificación visual, acuerdos de convivencia y
// responsabilidad sobre niñas, niños y adolescentes. Vacío = «No registrado»; «No» es una respuesta explícita. Registrarlas por primera
// vez no pide motivo; cambiar una ya registrada, sí (Ethos C8), y queda en la auditoría. Sin la de fotografía no se puede subir ninguna.
type Tri = boolean | null | undefined;
const word = (v: Tri) => (v === true ? t('common.yes') : v === false ? t('common.no') : t('common.not_recorded'));

export const CaseAuthorizationsPanel: React.FC<{
  caseId: string;
  photo: Tri;
  coexistence: Tri;
  nna: Tri;
  canEdit: boolean;
  onChanged: () => Promise<void>;
}> = ({ caseId, photo, coexistence, nna, canEdit, onChanged }) => {
  const uid = React.useId();
  const toast = useToast();
  const [editing, setEditing] = useState(false);
  const [p, setP] = useState(photo === true);
  const [c, setC] = useState(coexistence === true);
  const [n, setN] = useState<'' | 'yes' | 'no'>(nna === true ? 'yes' : nna === false ? 'no' : '');
  const [reasonText, setReasonText] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    setP(photo === true); setC(coexistence === true); setN(nna === true ? 'yes' : nna === false ? 'no' : '');
  }, [photo, coexistence, nna]);

  const nnaValue = n === '' ? null : n === 'yes';
  const registered = photo != null || coexistence != null || nna != null;
  const changed = p !== (photo === true) || c !== (coexistence === true) || nnaValue !== (nna ?? null) || photo == null || coexistence == null;
  const hadValue = (photo != null && p !== photo) || (coexistence != null && c !== coexistence) || (nna != null && nnaValue !== nna);
  const blocked = !changed ? t('cases.authorizations.reason_same') : hadValue && reasonText.trim() === '' ? t('team.reason_missing') : null;

  const save = async (e: React.FormEvent) => {
    e.preventDefault();
    if (blocked || busy) return;
    setBusy(true);
    setError(null);
    try {
      await dataApi.setCaseAuthorizations(caseId, p, c, nnaValue, reasonText);
      toast.success(t('cases.authorizations.saved'));
      setEditing(false);
      setReasonText('');
      await onChanged();
    } catch (err) {
      setError(friendlyError(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <section aria-labelledby={`${uid}-t`} className="space-y-3 rounded-2xl border border-gray-200 bg-white p-6 shadow-sm">
      <h3 id={`${uid}-t`} className="text-sm font-bold uppercase tracking-wider text-carbon">{t('cases.authorizations.title')}</h3>
      <p className="text-sm text-gray-700">{t('cases.authorizations.hint')}</p>
      <dl className="grid grid-cols-1 gap-2 text-sm sm:grid-cols-3">
        <div><dt className="text-gray-700">{t('cases.authorizations.photo')}</dt><dd className="font-semibold text-carbon">{word(photo)}</dd></div>
        <div><dt className="text-gray-700">{t('cases.authorizations.coexistence')}</dt><dd className="font-semibold text-carbon">{word(coexistence)}</dd></div>
        <div><dt className="text-gray-700">{t('cases.authorizations.nna')}</dt><dd className="font-semibold text-carbon">{nna == null ? t('cases.authorizations.nna_na') : word(nna)}</dd></div>
      </dl>
      {canEdit && !editing && (
        <button type="button" onClick={() => setEditing(true)} className="inline-flex min-h-11 items-center rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50">
          {registered ? t('cases.authorizations.edit') : t('cases.authorizations.register')}
        </button>
      )}
      {canEdit && editing && (
        <form onSubmit={save} className="space-y-3 rounded-xl border border-gray-200 bg-gray-50 p-4">
          <label className="flex min-h-11 cursor-pointer items-start gap-2 text-sm text-carbon">
            <input type="checkbox" checked={p} onChange={(e) => setP(e.target.checked)} className="mt-0.5 h-5 w-5 shrink-0 accent-turquesa" />
            <span>{t('intake.physical.photo')}</span>
          </label>
          <label className="flex min-h-11 cursor-pointer items-start gap-2 text-sm text-carbon">
            <input type="checkbox" checked={c} onChange={(e) => setC(e.target.checked)} className="mt-0.5 h-5 w-5 shrink-0 accent-turquesa" />
            <span>{t('intake.physical.coexistence')}</span>
          </label>
          <div>
            <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-n`}>{t('intake.physical.nna')}</label>
            <select id={`${uid}-n`} name={`${uid}-n`} autoComplete="off" value={n} onChange={(e) => setN(e.target.value as '' | 'yes' | 'no')}
              className="min-h-11 w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-turquesa focus:outline-none">
              <option value="">{t('cases.authorizations.nna_na')}</option>
              <option value="yes">{t('common.yes')}</option>
              <option value="no">{t('common.no')}</option>
            </select>
          </div>
          <div>
            <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-m`}>{t('cases.authorizations.reason')}</label>
            <input id={`${uid}-m`} name={`${uid}-m`} autoComplete="off" maxLength={300} value={reasonText} onChange={(e) => setReasonText(e.target.value)}
              className="min-h-11 w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-turquesa focus:outline-none" />
          </div>
          {error && <p role="alert" className="rounded-lg border border-alerta-dark/40 bg-alerta-bg/40 p-3 text-sm font-semibold text-alerta-dark">{error}</p>}
          <DisabledReason id={uid} reason={blocked} />
          <div className="flex flex-wrap gap-2">
            <button type="submit" disabled={!!blocked || busy} {...describedBy(uid, blocked)}
              className="inline-flex min-h-11 items-center rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon shadow-sm hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50">
              {busy ? t('case_extra.saving') : t('cases.authorizations.save')}
            </button>
            <button type="button" onClick={() => setEditing(false)} className="inline-flex min-h-11 items-center rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50">
              {t('common.cancel')}
            </button>
          </div>
        </form>
      )}
    </section>
  );
};
