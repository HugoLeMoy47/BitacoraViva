import { useEffect, useState } from 'react';
import { X, CheckCircle2, HeartHandshake, ShieldCheck, AlertTriangle } from 'lucide-react';
import { t } from '../lib/i18n';
import { ConsentText, PrivacyNotice, VulnerabilityMarkerCode } from '../types/database';
import { VULNERABILITY_CATALOG } from '../lib/catalogs';
import { useEnvironment } from '../lib/environment';
import { useCatalog } from '../lib/catalog';
import { ConsentInput, NewCaseInput, getActivePrivacyNotice, listConsentTexts } from '../lib/data';
import { ModalShell } from './ModalShell';

type Step = 0 | 1 | 2 | 3 | 4;
type Choice = 'yes' | 'no' | null;
// El intercambio entre áreas del propio albergue no se consiente por separado: lo cubre el aviso
// de privacidad general (decisión de Producto, 07 oct 2026).
type ConsentKey = Exclude<ConsentInput['consent_type'], 'internal_sharing'>;

const CONSENT_KEYS: { key: ConsentKey; required: boolean }[] = [
  { key: 'general_care', required: true },
  { key: 'sensitive_data', required: false },
  { key: 'secondary_use_research', required: false },
];

// Identificadores de país del estándar usados hasta ahora por la semilla; el resto va como "otro" (1).
const COUNTRY_ID: Record<string, number> = { Honduras: 93, Guatemala: 86 };

function ageYears(isoDate: string): number {
  const b = new Date(isoDate);
  if (Number.isNaN(b.getTime())) return 99;
  const now = new Date();
  let age = now.getFullYear() - b.getFullYear();
  const m = now.getMonth() - b.getMonth();
  if (m < 0 || (m === 0 && now.getDate() < b.getDate())) age--;
  return age;
}

interface NewCaseModalProps {
  isOpen: boolean;
  onClose: () => void;
  onCaseCreated: (input: NewCaseInput) => void;
  authorUserId?: string;
  authorFullName: string;
}

export const NewCaseModal: React.FC<NewCaseModalProps> = ({
  isOpen,
  onClose,
  onCaseCreated,
  authorFullName,
}) => {
  const [step, setStep] = useState<Step>(0);
  const { isDemo } = useEnvironment();
  const { areas } = useCatalog();

  // Paso 0: aviso de privacidad y consentimiento. Ninguna opción viene marcada.
  const [notice, setNotice] = useState<PrivacyNotice | null>(null);
  const [noticeLoaded, setNoticeLoaded] = useState(false);
  // Textos de consentimiento que la asociación publicó (si no hay, se usa el texto base de la plataforma)
  const [texts, setTexts] = useState<Partial<Record<ConsentKey, ConsentText>>>({});
  const [showFullNotice, setShowFullNotice] = useState(false);
  const [noticeDelivered, setNoticeDelivered] = useState(false);
  const [choices, setChoices] = useState<Record<ConsentKey, Choice>>({
    general_care: null,
    sensitive_data: null,
    secondary_use_research: null,
  });
  const [isMinor, setIsMinor] = useState(false);
  const [isUnaccompanied, setIsUnaccompanied] = useState(false);
  const [guardianName, setGuardianName] = useState('');
  const [guardianRole, setGuardianRole] = useState('');
  const [authorityRef, setAuthorityRef] = useState('');

  // Paso 1: Contexto
  const [windowType, setWindowType] = useState<'fija' | 'movil' | 'transaccional'>('fija');
  const [travelsWithFamily, setTravelsWithFamily] = useState(false);

  // Paso 2: Persona (MAP-OIM v3)
  const [givenName, setGivenName] = useState('');
  const [paternalName, setPaternalName] = useState('');
  const [maternalName, setMaternalName] = useState('');
  const [preferredName, setPreferredName] = useState('');
  const [birthDate, setBirthDate] = useState('2000-01-01');
  const [birthDateEstimated, setBirthDateEstimated] = useState(false);
  const [sexId, setSexId] = useState<number>(1);
  const [nationalityCountry, setNationalityCountry] = useState('Honduras');
  const [primaryLanguage, setPrimaryLanguage] = useState('Español');
  const [phone, setPhone] = useState('');

  // Paso 3: Vulnerabilidades (13 marcadores) — sólo con consentimiento expreso para datos sensibles
  const [selectedVulnerabilities, setSelectedVulnerabilities] = useState<VulnerabilityMarkerCode[]>([]);

  useEffect(() => {
    if (!isOpen) return;
    let cancelled = false;
    getActivePrivacyNotice()
      .then((n) => { if (!cancelled) { setNotice(n); setNoticeLoaded(true); } })
      .catch(() => { if (!cancelled) setNoticeLoaded(true); });
    listConsentTexts(true)
      .then((list) => { if (!cancelled) setTexts(Object.fromEntries(list.map((x) => [x.consent_type, x]))); })
      .catch(() => { /* sin textos publicados: se usan los de la plataforma */ });
    return () => { cancelled = true; };
  }, [isOpen]);

  if (!isOpen) return null;

  const consentTitle = (key: ConsentKey) => texts[key]?.title ?? t(`arco.consent_types.${key}`);
  const consentDesc = (key: ConsentKey) => texts[key]?.description ?? t(`intake.consent.desc.${key}`);
  const consentRequired = (key: ConsentKey) => key === 'general_care' || (texts[key]?.required ?? CONSENT_KEYS.find((c) => c.key === key)!.required);

  const sensitiveGranted = choices.sensitive_data === 'yes';
  const generalRefused = choices.general_care === 'no';
  const allDecided = CONSENT_KEYS.every(({ key }) => choices[key] !== null);

  const step0Valid =
    !!notice &&
    noticeDelivered &&
    allDecided &&
    choices.general_care === 'yes' &&
    CONSENT_KEYS.every(({ key }) => !consentRequired(key) || choices[key] === 'yes') &&
    (!isUnaccompanied || isMinor) &&
    (!isMinor || (guardianName.trim() !== '' && guardianRole.trim() !== '')) &&
    (!isUnaccompanied || authorityRef.trim() !== '');

  const birthAge = ageYears(birthDate);
  const ageProblem = step >= 2 && ((birthAge < 18 && !isMinor) ? 'intake.consent.age_mismatch_minor'
    : (birthAge >= 18 && isMinor) ? 'intake.consent.age_mismatch_adult' : null);
  const authorityProblem =
    selectedVulnerabilities.includes('unaccompanied_child') && !(isUnaccompanied && authorityRef.trim() !== '')
      ? 'intake.consent.unaccompanied_marker_needs_authority'
      : null;

  const toggleVulnerability = (code: VulnerabilityMarkerCode) => {
    setSelectedVulnerabilities((prev) =>
      prev.includes(code) ? prev.filter((c) => c !== code) : [...prev, code]
    );
  };

  const goNext = () => {
    setStep((s) => {
      if (s === 2) return sensitiveGranted ? 3 : 4;
      return (s + 1) as Step;
    });
  };
  const goPrev = () => {
    setStep((s) => {
      if (s === 4) return sensitiveGranted ? 3 : 2;
      return (s - 1) as Step;
    });
  };

  const buildConsents = (): ConsentInput[] =>
    CONSENT_KEYS.filter(({ key }) => choices[key] === 'yes').map(({ key }) => ({
      consent_type: key,
      status: 'granted',
      is_minor_assent: isMinor,
      legal_guardian_name: isMinor ? guardianName.trim() : null,
      legal_guardian_role: isMinor ? guardianRole.trim() : null,
      authority_letter_ref: isUnaccompanied ? authorityRef.trim() : null,
      notes: t('intake.consent.recorded_note'),
    }));

  const handleFinish = () => {
    const input: NewCaseInput = {
      given_name: givenName.trim() || 'Persona',
      paternal_family_name: paternalName.trim() || 'Registrada',
      maternal_family_name: maternalName.trim() || null,
      preferred_name: preferredName.trim() || null,
      birth_date: birthDate,
      birth_date_is_estimated: birthDateEstimated,
      sex_id: sexId,
      nationality_country_id: COUNTRY_ID[nationalityCountry] ?? 1,
      other_nationality: nationalityCountry,
      primary_language_id: 1,
      other_language: primaryLanguage || null,
      phone_number: phone.trim() || null,
      intake_window_type: windowType,
      travels_with_family: travelsWithFamily,
      intake_state_id: 9,
      intake_municipality_id: 15,
      intake_channel_id: 1,
      entry_route_id: 3,
      entry_date_str: null,
      assigned_area_id: areas.find((a) => a.code === 'trabajo_social')?.id ?? null,
      vulnerability_codes: sensitiveGranted ? selectedVulnerabilities : [],
      consents: buildConsents(),
    };
    onCaseCreated(input);
    onClose();
  };

  const stepLabels: { id: Step; label: string }[] = [
    { id: 0, label: t('intake.step_consent') },
    { id: 1, label: t('intake.step_context') },
    { id: 2, label: t('intake.step_person') },
    { id: 3, label: t('intake.step_vulnerabilities') },
    { id: 4, label: t('intake.step_confirm') },
  ];

  const nextDisabled =
    (step === 0 && !step0Valid) ||
    (step === 2 && (!givenName.trim() || !paternalName.trim() || !!ageProblem));

  return (
    <ModalShell onClose={onClose} className="fixed inset-0 z-50 bg-black/50 backdrop-blur-sm flex items-center justify-center p-4 overflow-y-auto">
      <div className="bg-white rounded-2xl shadow-xl border border-gray-200 w-full max-w-2xl overflow-hidden my-8">
        {/* Cabecera del modal */}
        <div className="px-6 py-4 bg-carbon text-white flex justify-between items-center border-b border-gray-700">
          <div>
            <h3 className="text-base font-bold">{t('intake.modal_title')}</h3>
            <p className="text-xs text-gray-300">{t('intake.modal_subtitle')}</p>
          </div>
          <button type="button" onClick={onClose} aria-label={t('session.dismiss')} className="p-1 rounded-lg hover:bg-gray-800 text-gray-300 hover:text-white">
            <X className="w-5 h-5" />
          </button>
        </div>

        {isDemo && (
          <p role="note" className="bg-amber-50 border-b border-amber-300 px-6 py-2 text-xs text-amber-900">
            {t('demo.modal_notice')}
          </p>
        )}

        {/* Indicador de pasos */}
        <div className="grid grid-cols-5 bg-gray-100 text-xs font-medium text-center border-b border-gray-200">
          {stepLabels.map((s) => {
            const skipped = s.id === 3 && !sensitiveGranted && step > 0;
            return (
              <div
                key={s.id}
                className={`py-2.5 px-1 border-b-2 ${
                  step === s.id
                    ? 'border-turquesa text-carbon font-bold bg-white'
                    : skipped
                      ? 'border-transparent text-gray-600 line-through'
                      : 'border-transparent text-gray-600'
                }`}
              >
                {s.label}
              </div>
            );
          })}
        </div>

        {/* Cuerpo del paso */}
        <div className="p-6 max-h-[65vh] overflow-y-auto space-y-4 text-sm">
          {/* Paso 0: Aviso de privacidad y consentimiento informado */}
          {step === 0 && (
            <div className="space-y-4">
              <div className="bg-claro/40 border border-turquesa/30 p-3 rounded-lg text-xs text-carbon flex items-start gap-2">
                <ShieldCheck className="w-4 h-4 text-turquesa-dark shrink-0 mt-0.5" />
                <div>
                  <p className="font-semibold text-turquesa-dark mb-0.5">{t('intake.consent.title')}</p>
                  <p className="text-gray-600">{t('intake.consent.intro')}</p>
                </div>
              </div>

              <div className="rounded-xl border border-gray-200 p-4 text-xs space-y-2">
                {!noticeLoaded ? (
                  <p className="text-gray-500">{t('session.loading')}</p>
                ) : !notice ? (
                  <p role="alert" className="text-alerta-dark">{t('intake.consent.notice_missing')}</p>
                ) : (
                  <>
                    <p className="font-bold text-carbon">{notice.title}</p>
                    <p className="text-gray-600">{notice.summary}</p>
                    <button
                      type="button"
                      onClick={() => setShowFullNotice((v) => !v)}
                      className="text-turquesa-dark font-semibold underline"
                    >
                      {showFullNotice ? t('intake.consent.hide_full') : t('intake.consent.show_full')}
                    </button>
                    {showFullNotice && (
                      <div className="max-h-40 overflow-y-auto whitespace-pre-line rounded-lg bg-gray-50 border border-gray-200 p-3 text-xs text-gray-700">
                        {notice.full_text}
                      </div>
                    )}
                    <p className="text-xs text-gray-500">
                      {t('intake.consent.version_label')} {notice.version}
                    </p>
                    {isDemo && <p className="text-xs text-amber-800">{t('intake.consent.demo_notice')}</p>}
                  </>
                )}
                <label className="flex items-start gap-2 pt-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={noticeDelivered}
                    onChange={(e) => setNoticeDelivered(e.target.checked)}
                    className="mt-0.5 rounded border-gray-300 text-turquesa"
                  />
                  <span className="font-medium text-carbon">{t('intake.consent.delivered')}</span>
                </label>
              </div>

              <div className="space-y-2">
                {CONSENT_KEYS.map(({ key }) => (
                  <fieldset key={key} className="rounded-xl border border-gray-200 p-3">
                    <legend className="px-1 text-xs font-bold text-carbon">
                      {consentTitle(key)}{' '}
                      <span className="font-normal text-gray-500">
                        ({consentRequired(key) ? t('intake.consent.required') : t('intake.consent.optional')})
                      </span>
                    </legend>
                    <p className="text-xs text-gray-500 mb-2">{consentDesc(key)}</p>
                    <div className="flex gap-2">
                      {(['yes', 'no'] as const).map((c) => (
                        <label
                          key={c}
                          className={`flex-1 text-center text-xs font-semibold rounded-lg border px-3 py-2 cursor-pointer transition ${
                            choices[key] === c
                              ? c === 'yes'
                                ? 'bg-claro border-turquesa text-carbon'
                                : 'bg-gray-100 border-gray-400 text-carbon'
                              : 'border-gray-200 text-gray-600 hover:bg-gray-50'
                          }`}
                        >
                          <input
                            type="radio"
                            name={`consent-${key}`}
                            value={c}
                            checked={choices[key] === c}
                            onChange={() => setChoices((prev) => ({ ...prev, [key]: c }))}
                            className="sr-only"
                          />
                          {c === 'yes' ? t('intake.consent.choice_yes') : t('intake.consent.choice_no')}
                        </label>
                      ))}
                    </div>
                  </fieldset>
                ))}
              </div>

              {generalRefused && (
                <div role="alert" className="flex items-start gap-2 rounded-xl border border-amber-300 bg-amber-50 p-3 text-xs text-amber-900">
                  <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5" />
                  <div>
                    <p className="font-bold">{t('intake.consent.refuse_general_title')}</p>
                    <p>{t('intake.consent.refuse_general_body')}</p>
                  </div>
                </div>
              )}
              {choices.sensitive_data === 'no' && (
                <p className="text-xs text-gray-600">{t('intake.consent.skip_sensitive')}</p>
              )}

              <div className="rounded-xl border border-gray-200 p-3 space-y-3">
                <label className="flex items-center gap-2 text-xs font-semibold text-carbon cursor-pointer">
                  <input
                    type="checkbox"
                    checked={isMinor}
                    onChange={(e) => {
                      setIsMinor(e.target.checked);
                      if (!e.target.checked) setIsUnaccompanied(false);
                    }}
                    className="rounded border-gray-300 text-turquesa"
                  />
                  {t('intake.consent.minor_check')}
                </label>
                {isMinor && (
                  <div className="space-y-3 pl-6">
                    <p className="text-xs text-gray-500">{t('intake.consent.minor_assent_note')}</p>
                    <label className="flex items-center gap-2 text-xs text-carbon cursor-pointer">
                      <input
                        type="checkbox"
                        checked={isUnaccompanied}
                        onChange={(e) => setIsUnaccompanied(e.target.checked)}
                        className="rounded border-gray-300 text-turquesa"
                      />
                      {t('intake.consent.unaccompanied_check')}
                    </label>
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                      <div>
                        <label className="block text-xs font-medium text-gray-700 mb-1" htmlFor="newcas-1">{t('intake.consent.guardian_name')}</label>
                        <input id="newcas-1" name="newcas-1" autoComplete="off"
                          type="text"
                          value={guardianName}
                          onChange={(e) => setGuardianName(e.target.value)}
                          className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                        />
                      </div>
                      <div>
                        <label className="block text-xs font-medium text-gray-700 mb-1" htmlFor="newcas-2">{t('intake.consent.guardian_role')}</label>
                        <input id="newcas-2" name="newcas-2" autoComplete="off"
                          type="text"
                          value={guardianRole}
                          onChange={(e) => setGuardianRole(e.target.value)}
                          className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                        />
                      </div>
                    </div>
                    {isUnaccompanied && (
                      <div>
                        <label className="block text-xs font-medium text-gray-700 mb-1" htmlFor="newcas-3">{t('intake.consent.authority_ref')}</label>
                        <input id="newcas-3" name="newcas-3" autoComplete="off"
                          type="text"
                          value={authorityRef}
                          onChange={(e) => setAuthorityRef(e.target.value)}
                          className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                        />
                      </div>
                    )}
                  </div>
                )}
              </div>
            </div>
          )}

          {/* Paso 1: Contexto de Llegada */}
          {step === 1 && (
            <div className="space-y-4">
              <div>
                <p id="window-label" className="block text-xs font-semibold text-carbon mb-1">{t('intake.field_intake_window')}</p>
                <div role="group" aria-labelledby="window-label" className="grid grid-cols-3 gap-2">
                  {(['fija', 'movil', 'transaccional'] as const).map((wt) => (
                    <button
                      key={wt}
                      type="button"
                      onClick={() => setWindowType(wt)}
                      className={`p-2.5 text-xs font-medium rounded-lg border text-center transition ${
                        windowType === wt ? 'bg-claro border-turquesa text-carbon font-bold shadow-sm' : 'border-gray-200 hover:bg-gray-50'
                      }`}
                    >
                      {t(`indicators.window.${wt}`)}
                    </button>
                  ))}
                </div>
              </div>

              <div className="p-4 bg-gray-50 rounded-xl border border-gray-200">
                <label className="flex items-center space-x-3 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={travelsWithFamily}
                    onChange={(e) => setTravelsWithFamily(e.target.checked)}
                    className="w-4 h-4 text-turquesa rounded border-gray-300 focus:ring-turquesa"
                  />
                  <div>
                    <span className="text-xs font-semibold text-carbon">{t('intake.field_travels_family')}</span>
                    <p className="text-xs text-gray-500">{t('intake.travels_family_help')}</p>
                  </div>
                </label>
              </div>
            </div>
          )}

          {/* Paso 2: Ficha Sociodemográfica */}
          {step === 2 && (
            <div className="space-y-4">
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1" htmlFor="newcas-4">{t('intake.field_given_name')}</label>
                  <input id="newcas-4" name="newcas-4" autoComplete="off"
                    type="text"
                    required
                    value={givenName}
                    onChange={(e) => setGivenName(e.target.value)}
                    placeholder={t('intake.ph_given')}
                    className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1" htmlFor="newcas-5">{t('intake.field_paternal_name')}</label>
                  <input id="newcas-5" name="newcas-5" autoComplete="off"
                    type="text"
                    required
                    value={paternalName}
                    onChange={(e) => setPaternalName(e.target.value)}
                    placeholder={t('intake.ph_paternal')}
                    className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                  />
                </div>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1" htmlFor="newcas-6">{t('intake.field_maternal_name')}</label>
                  <input id="newcas-6" name="newcas-6" autoComplete="off"
                    type="text"
                    value={maternalName}
                    onChange={(e) => setMaternalName(e.target.value)}
                    placeholder={t('intake.ph_optional')}
                    className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1" htmlFor="newcas-7">
                    {t('intake.field_preferred_name')} <span className="text-turquesa-dark font-semibold">(C1)</span>
                  </label>
                  <input id="newcas-7" name="newcas-7" autoComplete="off"
                    type="text"
                    value={preferredName}
                    onChange={(e) => setPreferredName(e.target.value)}
                    placeholder={t('intake.ph_preferred')}
                    className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                  />
                </div>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1" htmlFor="newcas-8">{t('intake.field_birth_date')}</label>
                  <input id="newcas-8" name="newcas-8" autoComplete="off"
                    type="date"
                    value={birthDate}
                    onChange={(e) => setBirthDate(e.target.value)}
                    className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                  />
                  <label className="flex items-center space-x-2 mt-1.5 cursor-pointer text-xs text-gray-600">
                    <input
                      type="checkbox"
                      checked={birthDateEstimated}
                      onChange={(e) => setBirthDateEstimated(e.target.checked)}
                      className="rounded text-turquesa border-gray-300"
                    />
                    <span className="text-xs">{t('intake.field_birth_estimated')}</span>
                  </label>
                </div>

                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1" htmlFor="newcas-9">{t('intake.field_sex')}</label>
                  <select id="newcas-9" name="newcas-9" autoComplete="off"
                    value={sexId}
                    onChange={(e) => setSexId(Number(e.target.value))}
                    className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                  >
                    <option value={1}>{t('intake.sex_1')}</option>
                    <option value={2}>{t('intake.sex_2')}</option>
                    <option value={3}>{t('intake.sex_3')}</option>
                  </select>
                </div>
              </div>

              {ageProblem && (
                <p role="alert" className="rounded-lg border border-alerta/30 bg-alerta-bg p-2.5 text-xs text-alerta-dark">
                  {t(ageProblem)}
                </p>
              )}

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1" htmlFor="newcas-10">{t('intake.field_nationality')}</label>
                  <select id="newcas-10" name="newcas-10" autoComplete="off"
                    value={nationalityCountry}
                    onChange={(e) => setNationalityCountry(e.target.value)}
                    className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                  >
                    <option value="Honduras">Honduras</option>
                    <option value="Guatemala">Guatemala</option>
                    <option value="El Salvador">El Salvador</option>
                    <option value="Venezuela">Venezuela</option>
                    <option value="Haití">Haití</option>
                    <option value="Cuba">Cuba</option>
                    <option value="Colombia">Colombia</option>
                    <option value="México">México</option>
                    <option value="Otro">{t('intake.other_country')}</option>
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1" htmlFor="newcas-11">{t('intake.field_primary_language')}</label>
                  <input id="newcas-11" name="newcas-11" autoComplete="off"
                    type="text"
                    value={primaryLanguage}
                    onChange={(e) => setPrimaryLanguage(e.target.value)}
                    placeholder={t('intake.ph_language')}
                    className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1" htmlFor="newcas-12">{t('intake.field_phone')}</label>
                <input id="newcas-12" name="newcas-12" autoComplete="off"
                  type="text"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  placeholder={t('intake.ph_phone')}
                  className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                />
              </div>
            </div>
          )}

          {/* Paso 3: Marcadores de Vulnerabilidad (13 marcadores de MAP-OIM v3) */}
          {step === 3 && (
            <div className="space-y-3">
              <div className="bg-claro/40 border border-turquesa/30 p-3 rounded-lg text-xs text-carbon">
                <p className="font-semibold text-turquesa-dark mb-0.5">{t('intake.vulnerabilities_title')}</p>
                <p className="text-gray-600">{t('intake.vulnerabilities_intro')}</p>
              </div>

              <div className="grid grid-cols-1 gap-2">
                {(Object.keys(VULNERABILITY_CATALOG) as VulnerabilityMarkerCode[]).map((code) => {
                  const item = VULNERABILITY_CATALOG[code];
                  const isChecked = selectedVulnerabilities.includes(code);
                  return (
                    <label
                      key={code}
                      className={`flex items-start space-x-3 p-3 rounded-xl border cursor-pointer transition ${
                        isChecked
                          ? 'bg-alerta-bg/40 border-alerta/40 text-carbon shadow-xs'
                          : 'bg-white border-gray-200 hover:bg-gray-50 text-gray-700'
                      }`}
                    >
                      <input
                        type="checkbox"
                        checked={isChecked}
                        onChange={() => toggleVulnerability(code)}
                        className="mt-0.5 w-4 h-4 text-alerta-dark rounded border-gray-300"
                      />
                      <div className="flex-1 text-xs">
                        <span className="font-bold block text-carbon">{item.label}</span>
                        <span className="text-xs text-gray-500">{item.description}</span>
                      </div>
                    </label>
                  );
                })}
              </div>
            </div>
          )}

          {/* Paso 4: Confirmación y Folio */}
          {step === 4 && (
            <div className="space-y-4">
              <div className="bg-green-50 border border-green-200 p-4 rounded-xl flex items-start space-x-3">
                <CheckCircle2 className="w-5 h-5 text-green-600 flex-shrink-0 mt-0.5" />
                <div className="text-xs">
                  <h4 className="font-bold text-green-900">{t('intake.confirm_title')}</h4>
                  <p className="text-green-700 mt-0.5">{t('intake.confirm_body')}</p>
                </div>
              </div>

              {authorityProblem && (
                <p role="alert" className="rounded-lg border border-alerta/30 bg-alerta-bg p-2.5 text-xs text-alerta-dark">
                  {t(authorityProblem)}
                </p>
              )}

              <div className="p-4 bg-gray-50 rounded-xl border border-gray-200 text-xs space-y-2">
                <div className="flex justify-between border-b pb-2">
                  <span className="text-gray-500">{t('intake.summary.person')}</span>
                  <span className="font-bold text-carbon">{givenName} {paternalName} {maternalName}</span>
                </div>
                <div className="flex justify-between border-b pb-2">
                  <span className="text-gray-500">{t('intake.summary.preferred')}</span>
                  <span className="font-semibold text-turquesa-dark">{preferredName || givenName}</span>
                </div>
                <div className="flex justify-between border-b pb-2">
                  <span className="text-gray-500">{t('intake.summary.nationality')}</span>
                  <span className="font-semibold text-carbon">{nationalityCountry}</span>
                </div>
                <div className="flex justify-between border-b pb-2">
                  <span className="text-gray-500">{t('intake.summary.vulnerabilities')}</span>
                  <span className="font-bold text-alerta-dark">
                    {sensitiveGranted ? `${selectedVulnerabilities.length} ${t('intake.summary.selected')}` : t('intake.consent.summary_none_sensitive')}
                  </span>
                </div>
                <div className="flex justify-between border-b pb-2">
                  <span className="text-gray-500">{t('intake.consent.summary_consents')}</span>
                  <span className="font-semibold text-carbon text-right">
                    {CONSENT_KEYS.filter(({ key }) => choices[key] === 'yes')
                      .map(({ key }) => consentTitle(key))
                      .join(' · ')}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-500">{t('intake.summary.officer')}</span>
                  <span className="font-semibold text-carbon">{authorFullName}</span>
                </div>
              </div>
            </div>
          )}
        </div>

        {/* Botones de navegación del modal */}
        <div className="px-6 py-4 bg-gray-50 border-t border-gray-200 flex justify-between items-center text-xs">
          {step > 0 ? (
            <button
              type="button"
              onClick={goPrev}
              className="px-4 py-2 font-semibold text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-100"
            >
              {t('intake.btn_prev')}
            </button>
          ) : (
            <div />
          )}

          {step < 4 ? (
            <button
              type="button"
              disabled={nextDisabled}
              onClick={goNext}
              className="px-4 py-2 font-semibold text-carbon bg-turquesa hover:bg-turquesa-hover rounded-lg shadow-sm disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {t('intake.btn_next')}
            </button>
          ) : (
            <button
              type="button"
              disabled={!!authorityProblem}
              onClick={handleFinish}
              className="px-5 py-2 font-bold text-white bg-carbon hover:bg-black rounded-lg shadow-md flex items-center gap-1.5 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <HeartHandshake className="w-4 h-4 text-turquesa" />
              {t('intake.btn_create_case')}
            </button>
          )}
        </div>
      </div>
    </ModalShell>
  );
};
