import { useEffect, useState } from 'react';
import { ArrowLeft, CheckCircle2, HeartHandshake, ShieldCheck, AlertTriangle, BookOpen } from 'lucide-react';
import { t } from '../lib/i18n';
import { ConsentText, GeoMunicipality, PrivacyNotice, VulnerabilityMarkerCode } from '../types/database';
import { friendlyError } from '../lib/errors';
import { DatePrecision, startsInFuture, toStoredDate } from '../lib/flexDate';
import { FlexibleDateInput } from './FlexibleDateInput';
import { VULNERABILITY_CATALOG } from '../lib/catalogs';
import { useEnvironment } from '../lib/environment';
import { useCatalog } from '../lib/catalog';
import { ConsentInput, NewCaseInput, dataApi, getActivePrivacyNotice, listConsentTexts } from '../lib/data';
import { DisabledReason, describedBy } from './DisabledReason';
import { NnaAssentModal } from './NnaAssentModal';

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

// Alta de expediente, como PÁGINA (no modal): 18 campos en cinco pasos, con el aviso de privacidad y el
// consentimiento. Empieza SIEMPRE vacía: ninguna opción de consentimiento viene marcada, y no se guarda
// borrador (sería arrastrar las decisiones y los datos de una persona a la captura de otra). Salir con algo
// capturado pide confirmación; el navegador avisa antes de recargar o cerrar.
interface NewCasePageProps {
  /** Sale de la captura (se llama tras confirmar si había algo escrito) */
  onCancel: () => void;
  onCaseCreated: (input: NewCaseInput) => void;
  authorUserId?: string;
  authorFullName: string;
}

export const NewCasePage: React.FC<NewCasePageProps> = ({ onCancel, onCaseCreated, authorFullName }) => {
  const [step, setStep] = useState<Step>(0);
  const { isDemo } = useEnvironment();
  const { areas, geoStates, intakeChannels, entryRoutes, catalogItems } = useCatalog();

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
  const [showNnaModal, setShowNnaModal] = useState(false);
  const [isUnaccompanied, setIsUnaccompanied] = useState(false);
  const [guardianName, setGuardianName] = useState('');
  const [guardianRole, setGuardianRole] = useState('');
  const [authorityRef, setAuthorityRef] = useState('');

  // Paso 1: Contexto
  // Sin valores supuestos: lo obligatorio (ventanilla) lo elige quien captura; lo opcional queda «No registrado»
  const [windowType, setWindowType] = useState<'' | 'fija' | 'movil' | 'transaccional'>('');
  const [travelsWithFamily, setTravelsWithFamily] = useState<'' | 'yes' | 'no'>('');
  const [stateKey, setStateKey] = useState('');
  const [municipalityKey, setMunicipalityKey] = useState('');
  const [channelCode, setChannelCode] = useState('');
  const [routeCode, setRouteCode] = useState('');
  // Fechas de ingreso (opcionales, con la precisión que se conozca)
  const [nationPrecision, setNationPrecision] = useState<DatePrecision>('day');
  const [nationRaw, setNationRaw] = useState('');
  const [shelterPrecision, setShelterPrecision] = useState<DatePrecision>('day');
  const [shelterRaw, setShelterRaw] = useState('');
  const [municipalities, setMunicipalities] = useState<GeoMunicipality[]>([]);
  const [municipalitiesError, setMunicipalitiesError] = useState<string | null>(null);

  // Paso 2: Persona (MAP-OIM v3)
  const [givenName, setGivenName] = useState('');
  const [paternalName, setPaternalName] = useState('');
  const [maternalName, setMaternalName] = useState('');
  const [preferredName, setPreferredName] = useState('');
  const [birthDate, setBirthDate] = useState('');
  const [birthDateEstimated, setBirthDateEstimated] = useState(false);
  const [sexId, setSexId] = useState<number | ''>('');
  const [nationalityCountry, setNationalityCountry] = useState('');
  // Idioma: valor del diccionario + detalle; sin consentimiento sensible solo «la persona no quiso responder»
  const [languageItemId, setLanguageItemId] = useState('');
  const [primaryLanguage, setPrimaryLanguage] = useState('');
  const [phone, setPhone] = useState('');

  // Paso 3: Vulnerabilidades (13 marcadores) — sólo con consentimiento expreso para datos sensibles
  const [selectedVulnerabilities, setSelectedVulnerabilities] = useState<VulnerabilityMarkerCode[]>([]);

  useEffect(() => {
    let cancelled = false;
    getActivePrivacyNotice()
      .then((n) => { if (!cancelled) { setNotice(n); setNoticeLoaded(true); } })
      .catch(() => { if (!cancelled) setNoticeLoaded(true); });
    listConsentTexts(true)
      .then((list) => { if (!cancelled) setTexts(Object.fromEntries(list.map((x) => [x.consent_type, x]))); })
      .catch(() => { /* sin textos publicados: se usan los de la plataforma */ });
    return () => { cancelled = true; };
  }, []);

  // Municipios del estado elegido (catálogo oficial); al cambiar de estado se limpia el municipio
  useEffect(() => {
    setMunicipalityKey('');
    setMunicipalities([]);
    setMunicipalitiesError(null);
    if (!stateKey) return;
    let cancelled = false;
    dataApi.listMunicipalities(stateKey)
      .then((list) => { if (!cancelled) setMunicipalities(list); })
      .catch((e) => { if (!cancelled) setMunicipalitiesError(friendlyError(e)); });
    return () => { cancelled = true; };
  }, [stateKey]);

  const consentTitle = (key: ConsentKey) => texts[key]?.title ?? t(`arco.consent_types.${key}`);
  const consentDesc = (key: ConsentKey) => texts[key]?.description ?? t(`intake.consent.desc.${key}`);
  const consentRequired = (key: ConsentKey) => key === 'general_care' || (texts[key]?.required ?? CONSENT_KEYS.find((c) => c.key === key)!.required);

  const sensitiveGranted = choices.sensitive_data === 'yes';
  const generalRefused = choices.general_care === 'no';
  const allDecided = CONSENT_KEYS.every(({ key }) => choices[key] !== null);

  const birthAge = ageYears(birthDate);
  const ageProblem = step >= 2 && ((birthAge < 18 && !isMinor) ? 'intake.consent.age_mismatch_minor'
    : (birthAge >= 18 && isMinor) ? 'intake.consent.age_mismatch_adult' : null);
  const authorityProblem =
    selectedVulnerabilities.includes('unaccompanied_child') && !(isUnaccompanied && authorityRef.trim() !== '')
      ? 'intake.consent.unaccompanied_marker_needs_authority'
      : null;

  // Fechas de ingreso: lo escrito debe servir y no ser futuro; vacío = «No registrado»
  const dateProblem = (precision: DatePrecision, raw: string): string | null => {
    const stored = toStoredDate(precision, raw);
    if (raw.trim() !== '' && !stored) return t('dates.reason_invalid');
    return stored && startsInFuture(stored) ? t('dates.reason_future') : null;
  };
  const nationProblem = dateProblem(nationPrecision, nationRaw);
  const shelterProblem = dateProblem(shelterPrecision, shelterRaw);

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
    // Ningún dato se inventa: lo sensible solo viaja con consentimiento sensible; lo no resuelto va vacío
    const nationality = sensitiveGranted && nationalityCountry ? nationalityCountry : null;
    const langItem = catalogItems.find((i) => i.id === languageItemId && i.catalog === 'language');
    const effectiveLang = langItem && (sensitiveGranted || langItem.key === 'no_response') ? langItem : null;
    const nationStored = toStoredDate(nationPrecision, nationRaw);
    const shelterStored = toStoredDate(shelterPrecision, shelterRaw);
    const dates: NewCaseInput['dates'] = [
      ...(nationStored ? [{ kind: 'nation_entry' as const, value: nationStored, precision: nationPrecision }] : []),
      ...(shelterStored ? [{ kind: 'shelter_entry' as const, value: shelterStored, precision: shelterPrecision }] : []),
    ];
    const input: NewCaseInput = {
      given_name: givenName.trim(),
      paternal_family_name: paternalName.trim(),
      maternal_family_name: maternalName.trim() || null,
      preferred_name: preferredName.trim() || null,
      birth_date: birthDate,
      birth_date_is_estimated: birthDateEstimated,
      sex_id: sensitiveGranted && sexId !== '' ? sexId : null,
      nationality_country_id: nationality ? (COUNTRY_ID[nationality] ?? 1) : null,
      other_nationality: nationality,
      primary_language_item_id: effectiveLang?.id ?? null,
      other_language: effectiveLang && effectiveLang.key !== 'no_response' && primaryLanguage.trim() ? primaryLanguage.trim() : null,
      phone_number: sensitiveGranted && phone.trim() ? phone.trim() : null,
      intake_window_type: windowType as 'fija' | 'movil' | 'transaccional',
      travels_with_family: travelsWithFamily === '' ? null : travelsWithFamily === 'yes',
      intake_state_id: stateKey ? Number(stateKey) : null,
      intake_municipality_key: municipalityKey || null,
      intake_channel_id: channelCode ? Number(channelCode) : null,
      entry_route_id: routeCode ? Number(routeCode) : null,
      entry_date_str: null,
      dates,
      assigned_area_id: areas.find((a) => a.code === 'trabajo_social')?.id ?? null,
      vulnerability_codes: sensitiveGranted ? selectedVulnerabilities : [],
      consents: buildConsents(),
    };
    onCaseCreated(input);
  };

  const stepLabels: { id: Step; label: string }[] = [
    { id: 0, label: t('intake.step_consent') },
    { id: 1, label: t('intake.step_context') },
    { id: 2, label: t('intake.step_person') },
    { id: 3, label: t('intake.step_vulnerabilities') },
    { id: 4, label: t('intake.step_confirm') },
  ];

  // Qué falta para avanzar, dicho con palabras (norma: ningún botón deshabilitado sin decir por qué)
  const stepReason: string | null = (() => {
    if (step === 0) {
      if (!notice) return t('intake.reason.notice_loading');
      if (!noticeDelivered) return t('intake.reason.notice_delivered');
      if (!allDecided) return t('intake.reason.decide_all');
      if (choices.general_care !== 'yes') return t('intake.reason.general_care');
      if (!CONSENT_KEYS.every(({ key }) => !consentRequired(key) || choices[key] === 'yes')) return t('intake.reason.required_consent');
      if (isUnaccompanied && !isMinor) return t('intake.reason.unaccompanied_minor');
      if (isMinor && (guardianName.trim() === '' || guardianRole.trim() === '')) return t('intake.reason.guardian');
      if (isUnaccompanied && authorityRef.trim() === '') return t('intake.reason.authority');
    }
    if (step === 1) {
      if (!windowType) return t('intake.reason.window_type');
      if (nationProblem) return nationProblem;
      if (shelterProblem) return shelterProblem;
    }
    if (step === 2) {
      if (!givenName.trim()) return t('intake.reason.given_name');
      if (!paternalName.trim()) return t('intake.reason.paternal_name');
      if (!birthDate) return t('intake.reason.birth_date');
      if (ageProblem) return t(ageProblem);
    }
    if (step === 4 && authorityProblem) return t(authorityProblem);
    return null;
  })();
  const nextDisabled = step < 4 && !!stepReason;

  // ¿Hay algo capturado que se perdería al salir?
  const dirty =
    !!(givenName || paternalName || maternalName || preferredName || phone || birthDate || windowType || travelsWithFamily || stateKey || channelCode || routeCode || guardianName || guardianRole || authorityRef) ||
    noticeDelivered ||
    CONSENT_KEYS.some(({ key }) => choices[key] !== null);
  const [confirmingLeave, setConfirmingLeave] = useState(false);
  const leave = () => (dirty ? setConfirmingLeave(true) : onCancel());
  useEffect(() => {
    if (!dirty) return;
    const guard = (e: BeforeUnloadEvent) => e.preventDefault();
    window.addEventListener('beforeunload', guard);
    return () => window.removeEventListener('beforeunload', guard);
  }, [dirty]);

  return (
    <div className="mx-auto max-w-3xl space-y-5">
      <div>
        <button type="button" onClick={leave} className="inline-flex min-h-11 items-center gap-1.5 text-sm font-semibold text-turquesa-dark hover:underline">
          <ArrowLeft className="h-4 w-4" aria-hidden="true" />
          {t('intake.page.back_to_list')}
        </button>
        <h2 className="font-title text-2xl font-bold text-carbon">{t('intake.page.title')}</h2>
        <p className="mt-1 text-sm text-gray-600">{t('intake.page.subtitle')}</p>
      </div>

      {isDemo && (
        <p role="note" className="rounded-lg border border-amber-300 bg-amber-50 px-4 py-2 text-sm text-amber-900">
          {t('demo.modal_notice')}
        </p>
      )}

      {/* Pasos: en celular, «Paso 2 de 5 · …»; desde tableta, los cinco a la vista */}
      <p className="text-sm font-semibold text-carbon md:hidden" aria-live="polite">
        {t('intake.page.step_of').replace('{n}', String(step + 1)).replace('{total}', String(stepLabels.length))} · {stepLabels[step].label}
      </p>
      <ol className="hidden grid-cols-5 overflow-hidden rounded-xl border border-gray-200 bg-white text-center text-xs font-medium md:grid" aria-label={t('intake.page.steps')}>
        {stepLabels.map((s) => {
          const skipped = s.id === 3 && !sensitiveGranted && step > 0;
          return (
            <li
              key={s.id}
              aria-current={step === s.id ? 'step' : undefined}
              className={`border-b-2 px-1 py-2.5 ${
                step === s.id
                  ? 'border-turquesa bg-white font-bold text-carbon'
                  : skipped
                    ? 'border-transparent text-gray-600 line-through'
                    : 'border-transparent text-gray-600'
              }`}
            >
              {s.id + 1}. {s.label}
            </li>
          );
        })}
      </ol>

      {/* Cuerpo del paso */}
      <div className="space-y-4 rounded-2xl border border-gray-200 bg-white p-5 text-sm">
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
                      className="inline-flex min-h-11 items-center text-turquesa-dark font-semibold underline"
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
                    <div className="flex flex-wrap items-center justify-between gap-2 bg-claro/30 p-2.5 rounded-lg border border-turquesa/20">
                      <p className="text-xs text-gray-600">{t('intake.consent.minor_assent_note')}</p>
                      <button
                        type="button"
                        onClick={() => setShowNnaModal(true)}
                        className="inline-flex items-center gap-1.5 rounded-lg border border-turquesa/40 bg-white px-2.5 py-1 text-xs font-semibold text-turquesa-dark hover:bg-claro shadow-2xs"
                      >
                        <BookOpen className="w-3.5 h-3.5" />
                        <span>{t('nna_guide.open_btn')}</span>
                      </button>
                    </div>
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
                <p id="window-label" className="block text-xs font-semibold text-carbon mb-1">{t('intake.field_intake_window')} <span className="font-normal text-gray-600">({t('intake.required')})</span></p>
                <div role="group" aria-labelledby="window-label" className="grid grid-cols-3 gap-2">
                  {(['fija', 'movil', 'transaccional'] as const).map((wt) => (
                    <button
                      key={wt}
                      type="button"
                      aria-pressed={windowType === wt}
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

              <div className="p-4 bg-gray-50 rounded-xl border border-gray-200" role="radiogroup" aria-labelledby="travels-label">
                <p id="travels-label" className="text-xs font-semibold text-carbon">{t('intake.field_travels_family')}</p>
                <p className="text-xs text-gray-600">{t('intake.travels_family_help')}</p>
                <div className="mt-2 flex flex-wrap gap-2">
                  {([['yes', 'intake.travels_yes'], ['no', 'intake.travels_no'], ['', 'intake.travels_unknown']] as const).map(([v, key]) => (
                    <label key={v || 'unknown'} className={`inline-flex min-h-11 cursor-pointer items-center gap-2 rounded-lg border px-3 text-xs ${travelsWithFamily === v ? 'border-turquesa bg-claro font-semibold text-carbon' : 'border-gray-300 text-gray-700'}`}>
                      <input type="radio" name="travels-family" checked={travelsWithFamily === v} onChange={() => setTravelsWithFamily(v)} className="text-turquesa" />
                      {t(key)}
                    </label>
                  ))}
                </div>
              </div>

              <p className="text-xs text-gray-700">{t('intake.ctx.hint')}</p>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1" htmlFor="newcas-state">{t('intake.ctx.state')}</label>
                  <select id="newcas-state" autoComplete="off" value={stateKey} onChange={(e) => setStateKey(e.target.value)} className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa disabled:bg-gray-100 disabled:text-gray-400 disabled:cursor-not-allowed">
                    <option value="">{t('common.not_recorded')}</option>
                    {geoStates.map((s) => <option key={s.cve_ent} value={s.cve_ent}>{s.name}</option>)}
                  </select>
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1" htmlFor="newcas-muni">{t('intake.ctx.municipality')}</label>
                  <select id="newcas-muni" autoComplete="off" value={municipalityKey} onChange={(e) => setMunicipalityKey(e.target.value)} disabled={!stateKey} className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa disabled:bg-gray-100 disabled:text-gray-400 disabled:cursor-not-allowed">
                    <option value="">{t('common.not_recorded')}</option>
                    {municipalities.map((m) => <option key={m.cvegeo} value={m.cvegeo}>{m.name}</option>)}
                  </select>
                  {!stateKey && <p className="mt-1 text-xs text-gray-700">{t('intake.ctx.municipality_needs_state')}</p>}
                  {municipalitiesError && <p role="alert" className="mt-1 text-xs font-semibold text-alerta-dark">{municipalitiesError}</p>}
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1" htmlFor="newcas-channel">{t('intake.ctx.channel')}</label>
                  <select id="newcas-channel" autoComplete="off" value={channelCode} onChange={(e) => setChannelCode(e.target.value)} className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa disabled:bg-gray-100 disabled:text-gray-400 disabled:cursor-not-allowed">
                    <option value="">{t('common.not_recorded')}</option>
                    {intakeChannels.filter((c) => c.is_active).map((c) => <option key={c.id} value={c.code}>{c.label_es}</option>)}
                  </select>
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1" htmlFor="newcas-route">{t('intake.ctx.route')}</label>
                  <select id="newcas-route" autoComplete="off" value={routeCode} onChange={(e) => setRouteCode(e.target.value)} className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa disabled:bg-gray-100 disabled:text-gray-400 disabled:cursor-not-allowed">
                    <option value="">{t('common.not_recorded')}</option>
                    {entryRoutes.filter((r) => r.is_active).map((r) => <option key={r.id} value={r.code}>{r.label_es}</option>)}
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <FlexibleDateInput
                  id="newcas-nation"
                  label={t('dates.kind.nation_entry')}
                  precision={nationPrecision}
                  value={nationRaw}
                  onChange={(p, v) => { setNationPrecision(p); setNationRaw(v); }}
                  problem={nationProblem}
                />
                <FlexibleDateInput
                  id="newcas-shelter"
                  label={t('dates.kind.shelter_entry')}
                  precision={shelterPrecision}
                  value={shelterRaw}
                  onChange={(p, v) => { setShelterPrecision(p); setShelterRaw(v); }}
                  problem={shelterProblem}
                />
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
                    {t('intake.field_preferred_name')}
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
                    required
                    max={new Date().toISOString().slice(0, 10)}
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
                    disabled={!sensitiveGranted}
                    value={sexId}
                    onChange={(e) => setSexId(e.target.value === '' ? '' : Number(e.target.value))}
                    className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa disabled:bg-gray-100 disabled:text-gray-400 disabled:cursor-not-allowed"
                  >
                    <option value="">{t('common.not_recorded')}</option>
                    <option value={1}>{t('intake.sex_1')}</option>
                    <option value={2}>{t('intake.sex_2')}</option>
                    <option value={3}>{t('intake.sex_3')}</option>
                  </select>
                  {!sensitiveGranted && (
                    <span className="mt-1 block text-[11px] text-amber-800 bg-amber-50 border border-amber-200 rounded px-1.5 py-0.5">
                      {t('intake.consent.sensitive_disabled_notice')}
                    </span>
                  )}
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
                    disabled={!sensitiveGranted}
                    value={nationalityCountry}
                    onChange={(e) => setNationalityCountry(e.target.value)}
                    className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa disabled:bg-gray-100 disabled:text-gray-400 disabled:cursor-not-allowed"
                  >
                    <option value="">{t('common.not_recorded')}</option>
                    <option value="Honduras">{t('intake.countries.honduras')}</option>
                    <option value="Guatemala">{t('intake.countries.guatemala')}</option>
                    <option value="El Salvador">{t('intake.countries.el_salvador')}</option>
                    <option value="Venezuela">{t('intake.countries.venezuela')}</option>
                    <option value="Haití">{t('intake.countries.haiti')}</option>
                    <option value="Cuba">{t('intake.countries.cuba')}</option>
                    <option value="Colombia">{t('intake.countries.colombia')}</option>
                    <option value="México">{t('intake.countries.mexico')}</option>
                    <option value="Otro">{t('intake.other_country')}</option>
                  </select>
                  {!sensitiveGranted && (
                    <span className="mt-1 block text-[11px] text-amber-800 bg-amber-50 border border-amber-200 rounded px-1.5 py-0.5">
                      {t('intake.consent.sensitive_disabled_notice')}
                    </span>
                  )}
                </div>

                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1" htmlFor="newcas-11">{t('intake.field_primary_language')}</label>
                  <select id="newcas-11" name="newcas-11" autoComplete="off"
                    value={languageItemId}
                    onChange={(e) => { setLanguageItemId(e.target.value); setPrimaryLanguage(''); }}
                    className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                  >
                    <option value="">{t('common.not_recorded')}</option>
                    {catalogItems
                      .filter((i) => i.catalog === 'language' && i.is_active && (sensitiveGranted || i.key === 'no_response'))
                      .map((i) => <option key={i.id} value={i.id}>{i.label_es}</option>)}
                  </select>
                  {catalogItems.find((i) => i.id === languageItemId)?.key && catalogItems.find((i) => i.id === languageItemId)?.key !== 'no_response' && (
                    <input id="newcas-11d" name="newcas-11d" autoComplete="off" aria-label={t('intake.language_detail')}
                      type="text"
                      value={primaryLanguage}
                      maxLength={120}
                      onChange={(e) => setPrimaryLanguage(e.target.value)}
                      placeholder={t('intake.language_detail')}
                      className="mt-2 w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                    />
                  )}
                  {!sensitiveGranted && (
                    <span className="mt-1 block text-[11px] text-amber-800 bg-amber-50 border border-amber-200 rounded px-1.5 py-0.5">
                      {t('diccionarios.only_no_response')}
                    </span>
                  )}
                </div>
              </div>

              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1" htmlFor="newcas-12">{t('intake.field_phone')}</label>
                <input id="newcas-12" name="newcas-12" autoComplete="off"
                  disabled={!sensitiveGranted}
                  type="text"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  placeholder={t('intake.ph_phone')}
                  className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa disabled:bg-gray-100 disabled:text-gray-400 disabled:cursor-not-allowed"
                />
                {!sensitiveGranted && (
                  <span className="mt-1 block text-[11px] text-amber-800 bg-amber-50 border border-amber-200 rounded px-1.5 py-0.5">
                    {t('intake.consent.sensitive_disabled_notice')}
                  </span>
                )}
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

              {!sensitiveGranted && (
                <div role="alert" className="p-3 bg-amber-50 border border-amber-300 rounded-xl flex items-start gap-2.5 text-xs text-amber-900">
                  <AlertTriangle className="w-4 h-4 text-amber-600 shrink-0 mt-0.5" />
                  <p>{t('intake.consent.vulnerabilities_disabled_notice')}</p>
                </div>
              )}

              <div className="grid grid-cols-1 gap-2">
                {(Object.keys(VULNERABILITY_CATALOG) as VulnerabilityMarkerCode[]).map((code) => {
                  const item = VULNERABILITY_CATALOG[code];
                  const isChecked = selectedVulnerabilities.includes(code);
                  return (
                    <label
                      key={code}
                      className={`flex items-start space-x-3 p-3 rounded-xl border transition ${
                        !sensitiveGranted
                          ? 'opacity-60 cursor-not-allowed bg-gray-50 border-gray-200 text-gray-400'
                          : isChecked
                          ? 'bg-alerta-bg/40 border-alerta/40 text-carbon shadow-xs cursor-pointer'
                          : 'bg-white border-gray-200 hover:bg-gray-50 text-gray-700 cursor-pointer'
                      }`}
                    >
                      <input
                        type="checkbox"
                        disabled={!sensitiveGranted}
                        checked={isChecked}
                        onChange={() => toggleVulnerability(code)}
                        className="mt-0.5 w-4 h-4 text-alerta-dark rounded border-gray-300 disabled:cursor-not-allowed"
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
                  <h3 className="font-bold text-green-900">{t('intake.confirm_title')}</h3>
                  <p className="text-green-700 mt-0.5">{t('intake.confirm_body')}</p>
                </div>
              </div>

              <div className="p-4 bg-gray-50 rounded-xl border border-gray-200 text-xs space-y-2">
                <div className="flex justify-between border-b pb-2">
                  <span className="text-gray-500">{t('intake.summary.person')}</span>
                  <span className="font-bold text-carbon">{givenName} {paternalName} {maternalName}</span>
                </div>
                <div className="flex justify-between border-b pb-2">
                  <span className="text-gray-500">{t('intake.summary.preferred')}</span>
                  <span className="font-semibold text-turquesa-dark">{preferredName || t('common.not_recorded')}</span>
                </div>
                <div className="flex justify-between border-b pb-2">
                  <span className="text-gray-500">{t('intake.summary.nationality')}</span>
                  <span className="font-semibold text-carbon">{sensitiveGranted && nationalityCountry ? nationalityCountry : t('common.not_recorded')}</span>
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

      {confirmingLeave && (
        <div role="alert" className="rounded-xl border border-alerta/30 bg-alerta-bg p-4 text-sm">
          <p className="font-bold text-alerta-dark">{t('intake.page.discard_title')}</p>
          <p className="mt-1 text-carbon">{t('intake.page.discard_body')}</p>
          <div className="mt-3 flex flex-wrap gap-2">
            <button type="button" onClick={onCancel} className="min-h-11 rounded-lg bg-carbon px-4 text-sm font-semibold text-white hover:bg-black">
              {t('intake.page.discard_confirm')}
            </button>
            <button type="button" onClick={() => setConfirmingLeave(false)} className="min-h-11 rounded-lg border border-gray-300 bg-white px-4 text-sm font-semibold text-gray-700 hover:bg-gray-50">
              {t('intake.page.discard_keep')}
            </button>
          </div>
        </div>
      )}

      {/* Barra de acciones: siempre a la vista; en celular queda sobre la barra de navegación */}
      <div className="sticky bottom-[calc(3.5rem+env(safe-area-inset-bottom))] z-30 -mx-4 border-t border-gray-200 bg-white/95 px-4 py-3 backdrop-blur md:bottom-0 md:mx-0 md:rounded-2xl md:border">
        <DisabledReason id="alta" reason={stepReason} className="mb-2" />
        <div className="flex items-center justify-between gap-3">
          {step > 0 ? (
            <button type="button" onClick={goPrev} className="min-h-11 rounded-lg border border-gray-300 bg-white px-4 text-sm font-semibold text-gray-700 hover:bg-gray-50">
              {t('intake.btn_prev')}
            </button>
          ) : (
            <div />
          )}

          {step < 4 ? (
            <button
              type="button"
              disabled={nextDisabled}
              {...describedBy('alta', stepReason)}
              onClick={goNext}
              className="min-h-11 rounded-lg bg-turquesa px-5 text-sm font-semibold text-carbon shadow-sm hover:bg-turquesa-hover disabled:cursor-not-allowed disabled:opacity-50"
            >
              {t('intake.btn_next')}
            </button>
          ) : (
            <button
              type="button"
              disabled={!!authorityProblem}
              {...describedBy('alta', stepReason)}
              onClick={handleFinish}
              className="inline-flex min-h-11 items-center gap-1.5 rounded-lg bg-carbon px-5 text-sm font-bold text-white shadow-md hover:bg-black disabled:cursor-not-allowed disabled:opacity-50"
            >
              <HeartHandshake className="h-4 w-4 text-turquesa" aria-hidden="true" />
              {t('intake.btn_create_case')}
            </button>
          )}
        </div>
      </div>

      <NnaAssentModal isOpen={showNnaModal} onClose={() => setShowNnaModal(false)} />
    </div>
  );
};
