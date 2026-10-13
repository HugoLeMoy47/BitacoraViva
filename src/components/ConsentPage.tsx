import { useState } from 'react';
import { ArrowLeft, FileCheck } from 'lucide-react';
import { t } from '../lib/i18n';
import { CaseWithDetails, ConsentType, ConsentStatus } from '../types/database';
import { formatDate } from '../lib/format';
import { DiscardConfirm, useBeforeUnloadGuard } from './LeaveGuard';

// Registrar una decisión de consentimiento (otorgar, revocar u oponerse), como PÁGINA (no modal): son siete campos
// y conviene ver a un lado lo que la persona ya decidió. Cada decisión queda registrada con su fecha; no se edita
// la anterior.

const INPUT = 'w-full min-h-11 rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa';
const LABEL = 'block text-sm font-semibold text-carbon mb-1';
const TYPES: ConsentType[] = ['general_care', 'sensitive_data', 'secondary_use_research'];

interface ConsentPageProps {
  caseData: CaseWithDetails;
  /** Vuelve al expediente (se llama tras confirmar si había algo escrito) */
  onCancel: () => void;
  onSaveConsent: (consent: {
    consent_type: ConsentType;
    status: ConsentStatus;
    is_minor_assent: boolean;
    legal_guardian_name?: string;
    legal_guardian_role?: string;
    authority_letter_ref?: string;
    notes?: string;
  }) => void;
}

export const ConsentPage: React.FC<ConsentPageProps> = ({ caseData, onCancel, onSaveConsent }) => {
  const [consentType, setConsentType] = useState<ConsentType>('sensitive_data');
  const [status, setStatus] = useState<ConsentStatus>('granted');
  const [isMinorAssent, setIsMinorAssent] = useState(false);
  const [guardianName, setGuardianName] = useState('');
  const [guardianRole, setGuardianRole] = useState('');
  const [authorityRef, setAuthorityRef] = useState('');
  const [notes, setNotes] = useState('');
  const [confirmingLeave, setConfirmingLeave] = useState(false);

  const dirty = !!(isMinorAssent || guardianName || guardianRole || authorityRef || notes);
  useBeforeUnloadGuard(dirty);
  const leave = () => (dirty ? setConfirmingLeave(true) : onCancel());

  // Lo que la persona ya decidió: la decisión más reciente de cada tipo
  const latest = (type: ConsentType) =>
    (caseData.consents ?? []).filter((c) => c.consent_type === type).sort((a, b) => b.granted_at.localeCompare(a.granted_at))[0];

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    onSaveConsent({
      consent_type: consentType,
      status,
      is_minor_assent: isMinorAssent,
      legal_guardian_name: guardianName.trim() || undefined,
      legal_guardian_role: guardianRole.trim() || undefined,
      authority_letter_ref: authorityRef.trim() || undefined,
      notes: notes.trim() || undefined,
    });
    onCancel();
  };

  return (
    <div className="mx-auto max-w-5xl space-y-5">
      <div>
        <button type="button" onClick={leave} className="inline-flex min-h-11 items-center gap-1.5 text-sm font-semibold text-turquesa-dark hover:underline">
          <ArrowLeft className="h-4 w-4" aria-hidden="true" />
          {t('arco.consent_page.back_to_case').replace('{folio}', caseData.case_number)}
        </button>
        <h2 className="font-title text-2xl font-bold text-carbon">{t('arco.modal_consent.title')}</h2>
        <p className="mt-1 text-sm text-gray-600">{t('arco.modal_consent.subtitle')}</p>
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,1fr)_20rem]">
        <form onSubmit={submit} className="min-w-0 space-y-5">
          <fieldset className="space-y-3 rounded-2xl border border-gray-200 bg-white p-5">
            <legend className="px-1 text-base font-bold text-carbon">{t('arco.consent_page.section_decision')}</legend>
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
              <div>
                <label className={LABEL} htmlFor="consent-type">{t('arco.modal_consent.type_label')}</label>
                <select id="consent-type" autoComplete="off" value={consentType} onChange={(e) => setConsentType(e.target.value as ConsentType)} className={INPUT}>
                  {TYPES.map((k) => (
                    <option key={k} value={k}>{t(`arco.consent_types.${k}`)}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className={LABEL} htmlFor="consent-status">{t('arco.modal_consent.status_label')}</label>
                <select id="consent-status" autoComplete="off" value={status} onChange={(e) => setStatus(e.target.value as ConsentStatus)} className={INPUT}>
                  <option value="granted">{t('arco.consent_status.granted')}</option>
                  <option value="revoked">{t('arco.consent_status.revoked')}</option>
                  <option value="opposed">{t('arco.consent_status.opposed')}</option>
                </select>
              </div>
            </div>
          </fieldset>

          {/* Salvaguarda para niñez y adolescencia */}
          <fieldset className="space-y-3 rounded-2xl border border-amber-200 bg-amber-50 p-5 text-amber-900">
            <legend className="px-1 text-base font-bold">{t('arco.consent_page.section_minor')}</legend>
            <label className="flex min-h-11 cursor-pointer items-center gap-2 text-sm font-semibold">
              <input type="checkbox" checked={isMinorAssent} onChange={(e) => setIsMinorAssent(e.target.checked)} className="h-4 w-4 rounded border-amber-300 text-turquesa" />
              {t('arco.modal_consent.is_minor_assent')}
            </label>
            {isMinorAssent && (
              <div className="space-y-3 border-t border-amber-200 pt-3">
                <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
                  <div>
                    <label className="mb-1 block text-sm font-medium" htmlFor="consent-guardian">{t('arco.modal_consent.guardian_name')}</label>
                    <input id="consent-guardian" autoComplete="off" type="text" value={guardianName} onChange={(e) => setGuardianName(e.target.value)} placeholder={t('arco.modal_consent.ph_guardian_name')} className={INPUT} />
                  </div>
                  <div>
                    <label className="mb-1 block text-sm font-medium" htmlFor="consent-role">{t('arco.modal_consent.guardian_role')}</label>
                    <input id="consent-role" autoComplete="off" type="text" value={guardianRole} onChange={(e) => setGuardianRole(e.target.value)} placeholder={t('arco.modal_consent.ph_guardian_role')} className={INPUT} />
                  </div>
                </div>
                <div>
                  <label className="mb-1 block text-sm font-medium" htmlFor="consent-authority">{t('arco.modal_consent.authority_letter')}</label>
                  <input id="consent-authority" autoComplete="off" type="text" value={authorityRef} onChange={(e) => setAuthorityRef(e.target.value)} placeholder={t('arco.modal_consent.ph_authority_ref')} className={INPUT} />
                </div>
              </div>
            )}
          </fieldset>

          <div className="rounded-2xl border border-gray-200 bg-white p-5">
            <label className="mb-1 block text-base font-bold text-carbon" htmlFor="consent-notes">{t('arco.modal_consent.notes')}</label>
            <textarea id="consent-notes" autoComplete="off" rows={3} value={notes} onChange={(e) => setNotes(e.target.value)} placeholder={t('arco.modal_consent.notes_placeholder')} className={INPUT} />
          </div>

          {confirmingLeave && <DiscardConfirm onDiscard={onCancel} onKeep={() => setConfirmingLeave(false)} />}

          <div className="sticky bottom-[calc(3.5rem+env(safe-area-inset-bottom))] z-30 -mx-4 border-t border-gray-200 bg-white/95 px-4 py-3 backdrop-blur md:bottom-0 md:mx-0 md:rounded-2xl md:border">
            <div className="flex items-center justify-between gap-3">
              <button type="button" onClick={leave} className="min-h-11 rounded-lg border border-gray-300 bg-white px-4 text-sm font-semibold text-gray-700 hover:bg-gray-50">
                {t('common.cancel')}
              </button>
              <button type="submit" className="inline-flex min-h-11 items-center gap-1.5 rounded-lg bg-turquesa px-5 text-sm font-semibold text-carbon shadow-sm hover:opacity-90">
                <FileCheck className="h-4 w-4" aria-hidden="true" />
                <span>{t('arco.modal_consent.btn_save')}</span>
              </button>
            </div>
          </div>
        </form>

        {/* Contexto: lo que la persona ya decidió */}
        <aside aria-label={t('arco.consent_page.current_title')} className="space-y-3 lg:sticky lg:top-20 lg:self-start">
          <section className="rounded-2xl border border-gray-200 bg-white p-5">
            <h3 className="text-base font-bold text-carbon">{t('arco.consent_page.current_title')}</h3>
            <p className="mt-1 text-sm text-gray-600">{caseData.case_number} · {caseData.person.given_name} {caseData.person.paternal_family_name}</p>
            <ul className="mt-3 space-y-3 text-sm">
              {TYPES.map((k) => {
                const c = latest(k);
                return (
                  <li key={k}>
                    <p className="text-gray-700">{t(`arco.consent_types.${k}`)}</p>
                    <p className="font-semibold text-carbon">
                      {c ? `${t(`arco.consent_status.${c.status}`)} · ${formatDate(c.granted_at)}` : t('arco.consent_page.none')}
                    </p>
                  </li>
                );
              })}
            </ul>
          </section>
        </aside>
      </div>
    </div>
  );
};
