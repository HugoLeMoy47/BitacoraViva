import { useState } from 'react';
import { ArrowLeft, Save } from 'lucide-react';
import { t } from '../lib/i18n';
import { CaseWithDetails, Person } from '../types/database';
import { DisabledReason, describedBy } from './DisabledReason';
import { DiscardConfirm, useBeforeUnloadGuard } from './LeaveGuard';

// Derecho de rectificación (ARCO), como PÁGINA (no modal): son ocho campos y un motivo. Los campos vienen con lo
// que hoy está registrado, así que se ve qué se corrige. Guardar exige al menos un cambio y el motivo.

const INPUT = 'w-full min-h-11 rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa';
const LABEL = 'block text-sm font-semibold text-carbon mb-1';

interface RectifyPersonPageProps {
  caseData: CaseWithDetails;
  /** Vuelve al expediente (se llama tras confirmar si había cambios sin guardar) */
  onCancel: () => void;
  onRectify: (updates: Partial<Person>, reason: string) => void;
}

export const RectifyPersonPage: React.FC<RectifyPersonPageProps> = ({ caseData, onCancel, onRectify }) => {
  const person = caseData.person;
  const sensitiveGranted = caseData.consents?.some((c) => c.consent_type === 'sensitive_data' && c.status === 'granted') ?? false;
  const [givenName, setGivenName] = useState(person.given_name);
  const [paternalName, setPaternalName] = useState(person.paternal_family_name);
  const [maternalName, setMaternalName] = useState(person.maternal_family_name || '');
  const [preferredName, setPreferredName] = useState(person.preferred_name || '');
  const [birthDate, setBirthDate] = useState(person.birth_date);
  const [birthEstimated, setBirthEstimated] = useState(person.birth_date_is_estimated);
  const [phone, setPhone] = useState(person.phone_number || '');
  const [email, setEmail] = useState(person.email || '');
  const [reason, setReason] = useState('');
  const [confirmingLeave, setConfirmingLeave] = useState(false);

  const changed =
    givenName.trim() !== person.given_name ||
    paternalName.trim() !== person.paternal_family_name ||
    maternalName.trim() !== (person.maternal_family_name || '') ||
    preferredName.trim() !== (person.preferred_name || '') ||
    birthDate !== person.birth_date ||
    birthEstimated !== person.birth_date_is_estimated ||
    phone.trim() !== (person.phone_number || '') ||
    email.trim() !== (person.email || '');
  const dirty = changed || reason.trim() !== '';
  useBeforeUnloadGuard(dirty);
  const leave = () => (dirty ? setConfirmingLeave(true) : onCancel());

  const saveReason: string | null = !givenName.trim()
    ? t('intake.reason.given_name')
    : !paternalName.trim()
      ? t('intake.reason.paternal_name')
      : !birthDate
        ? t('subfolio.reason_birth')
        : !changed
          ? t('arco.rectify_page.no_changes')
          : !reason.trim()
            ? t('arco.rectify_page.reason_required')
            : null;

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    if (saveReason) return;
    onRectify(
      {
        given_name: givenName.trim(),
        paternal_family_name: paternalName.trim(),
        maternal_family_name: maternalName.trim() || null,
        preferred_name: preferredName.trim() || null,
        birth_date: birthDate,
        birth_date_is_estimated: birthEstimated,
        phone_number: phone.trim() || null,
        email: email.trim() || null,
      },
      reason.trim()
    );
    onCancel();
  };

  return (
    <div className="mx-auto max-w-5xl space-y-5">
      <div>
        <button type="button" onClick={leave} className="inline-flex min-h-11 items-center gap-1.5 text-sm font-semibold text-turquesa-dark hover:underline">
          <ArrowLeft className="h-4 w-4" aria-hidden="true" />
          {t('arco.rectify_page.back_to_case').replace('{folio}', caseData.case_number)}
        </button>
        <h2 className="font-title text-2xl font-bold text-carbon">{t('arco.modal_rectify.title')}</h2>
        <p className="mt-1 text-sm text-gray-600">{t('arco.modal_rectify.subtitle')}</p>
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,1fr)_18rem]">
        <form onSubmit={submit} className="min-w-0 space-y-5">
          <fieldset className="space-y-3 rounded-2xl border border-gray-200 bg-white p-5">
            <legend className="px-1 text-base font-bold text-carbon">{t('arco.rectify_page.section_data')}</legend>
            <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
              <div>
                <label className={LABEL} htmlFor="rectif-given">{t('arco.modal_rectify.given_name')}</label>
                <input id="rectif-given" autoComplete="off" type="text" value={givenName} onChange={(e) => setGivenName(e.target.value)} className={INPUT} />
              </div>
              <div>
                <label className={LABEL} htmlFor="rectif-paternal">{t('arco.modal_rectify.paternal_name')}</label>
                <input id="rectif-paternal" autoComplete="off" type="text" value={paternalName} onChange={(e) => setPaternalName(e.target.value)} className={INPUT} />
              </div>
              <div>
                <label className={LABEL} htmlFor="rectif-maternal">{t('arco.modal_rectify.maternal_name')}</label>
                <input id="rectif-maternal" autoComplete="off" type="text" value={maternalName} onChange={(e) => setMaternalName(e.target.value)} className={INPUT} />
              </div>
              <div>
                <label className={LABEL} htmlFor="rectif-preferred">{t('arco.modal_rectify.preferred_name')}</label>
                <input id="rectif-preferred" autoComplete="off" type="text" value={preferredName} onChange={(e) => setPreferredName(e.target.value)} className={INPUT} />
              </div>
              <div>
                <label className={LABEL} htmlFor="rectif-birth">{t('arco.modal_rectify.birth_date')}</label>
                <input id="rectif-birth" autoComplete="off" type="date" value={birthDate} onChange={(e) => setBirthDate(e.target.value)} className={INPUT} />
                <label className="mt-1.5 flex min-h-11 cursor-pointer items-center gap-2 text-sm text-gray-600">
                  <input type="checkbox" checked={birthEstimated} onChange={(e) => setBirthEstimated(e.target.checked)} className="h-4 w-4 rounded border-gray-300 text-turquesa" />
                  <span>{t('arco.modal_rectify.birth_estimated')}</span>
                </label>
              </div>
              <div>
                <label className={LABEL} htmlFor="rectif-phone">{t('arco.modal_rectify.phone')}</label>
                <input
                  id="rectif-phone"
                  autoComplete="off"
                  disabled={!sensitiveGranted}
                  type="text"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  placeholder={t('arco.modal_rectify.ph_phone')}
                  className={`${INPUT} disabled:bg-gray-100 disabled:text-gray-400 disabled:cursor-not-allowed`}
                />
                {!sensitiveGranted && (
                  <span className="mt-1 block text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded px-1.5 py-0.5">
                    {t('intake.consent.sensitive_disabled_notice')}
                  </span>
                )}
              </div>
              <div className="md:col-span-2">
                <label className={LABEL} htmlFor="rectif-email">{t('arco.modal_rectify.email')}</label>
                <input
                  id="rectif-email"
                  autoComplete="off"
                  disabled={!sensitiveGranted}
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className={`${INPUT} disabled:bg-gray-100 disabled:text-gray-400 disabled:cursor-not-allowed`}
                />
                {!sensitiveGranted && (
                  <span className="mt-1 block text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded px-1.5 py-0.5">
                    {t('intake.consent.sensitive_disabled_notice')}
                  </span>
                )}
              </div>
            </div>
          </fieldset>

          <div className="rounded-2xl border border-gray-200 bg-white p-5">
            <label className="mb-1 block text-base font-bold text-carbon" htmlFor="rectif-reason">
              {t('arco.modal_rectify.reason')}
            </label>
            <textarea
              id="rectif-reason"
              autoComplete="off"
              rows={3}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder={t('arco.modal_rectify.reason_placeholder')}
              className={INPUT}
            />
          </div>

          {confirmingLeave && <DiscardConfirm onDiscard={onCancel} onKeep={() => setConfirmingLeave(false)} />}

          <div className="sticky bottom-[calc(3.5rem+env(safe-area-inset-bottom))] z-30 -mx-4 border-t border-gray-200 bg-white/95 px-4 py-3 backdrop-blur md:bottom-0 md:mx-0 md:rounded-2xl md:border">
            <DisabledReason id="rectificar" reason={saveReason} className="mb-2" />
            <div className="flex items-center justify-between gap-3">
              <button type="button" onClick={leave} className="min-h-11 rounded-lg border border-gray-300 bg-white px-4 text-sm font-semibold text-gray-700 hover:bg-gray-50">
                {t('common.cancel')}
              </button>
              <button
                type="submit"
                disabled={!!saveReason}
                {...describedBy('rectificar', saveReason)}
                className="inline-flex min-h-11 items-center gap-1.5 rounded-lg bg-turquesa px-5 text-sm font-semibold text-carbon shadow-sm hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50"
              >
                <Save className="h-4 w-4" aria-hidden="true" />
                <span>{t('arco.modal_rectify.btn_save')}</span>
              </button>
            </div>
          </div>
        </form>

        <aside aria-label={t('arco.rectify_page.context_title')} className="space-y-3 lg:sticky lg:top-20 lg:self-start">
          <section className="rounded-2xl border border-gray-200 bg-white p-5">
            <h3 className="text-base font-bold text-carbon">{t('arco.rectify_page.context_title')}</h3>
            <dl className="mt-3 space-y-3 text-sm">
              <div>
                <dt className="text-gray-600">{t('subfolio.context_folio')}</dt>
                <dd className="font-mono font-bold text-carbon">{caseData.case_number}</dd>
              </div>
              <div>
                <dt className="text-gray-600">{t('journal.new_page.context_person')}</dt>
                <dd className="font-semibold text-carbon">{person.given_name} {person.paternal_family_name}</dd>
              </div>
            </dl>
            <p className="mt-3 rounded-lg bg-gray-50 p-3 text-sm text-gray-700">{t('arco.rectify_page.audit_note')}</p>
          </section>
        </aside>
      </div>
    </div>
  );
};
