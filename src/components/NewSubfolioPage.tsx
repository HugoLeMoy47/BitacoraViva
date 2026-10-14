import { useEffect, useId, useMemo, useState } from 'react';
import { ArrowLeft, HeartHandshake, BookOpen } from 'lucide-react';
import { t } from '../lib/i18n';
import { CaseWithDetails, VulnerabilityMarkerCode } from '../types/database';
import { VULNERABILITY_CATALOG } from '../lib/catalogs';
import { ConsentInput, SubfolioInput } from '../lib/data';
import { DisabledReason, describedBy } from './DisabledReason';
import { NnaAssentModal } from './NnaAssentModal';

// BV-3.2 · Subfolio, como PÁGINA (no modal): son 12 campos y conviene ver el caso principal al lado.
// Quien representa a la persona menor es la persona titular del caso principal (la base toma su nombre de ahí;
// aquí solo se pide el parentesco). Los consentimientos llegan con la decisión que ya tomó, se pueden ajustar,
// y la nota de justificación es obligatoria. «Atrás» funciona, y lo capturado se conserva en memoria si se
// va a mirar otra pantalla y se regresa (no se guarda en el navegador: son datos de una persona menor).

type Choice = 'yes' | 'no' | null;
type ConsentKey = Exclude<ConsentInput['consent_type'], 'internal_sharing'>;
type Relationship = 'mother' | 'father' | 'guardian' | 'other';
const CONSENT_KEYS: ConsentKey[] = ['general_care', 'sensitive_data', 'secondary_use_research'];
const COUNTRY_ID: Record<string, number> = { Honduras: 93, Guatemala: 86 };
const COUNTRIES: { value: string; key: string }[] = [
  { value: 'Honduras', key: 'intake.countries.honduras' },
  { value: 'Guatemala', key: 'intake.countries.guatemala' },
  { value: 'El Salvador', key: 'intake.countries.el_salvador' },
  { value: 'Venezuela', key: 'intake.countries.venezuela' },
  { value: 'Haití', key: 'intake.countries.haiti' },
  { value: 'Cuba', key: 'intake.countries.cuba' },
  { value: 'Colombia', key: 'intake.countries.colombia' },
  { value: 'México', key: 'intake.countries.mexico' },
  { value: 'Otro', key: 'intake.other_country' },
];
const MIN_NOTE = 10;
const INPUT = 'w-full min-h-11 text-sm p-2.5 border rounded-lg border-gray-300 bg-white focus:outline-none focus:border-turquesa';
const LABEL = 'block text-sm font-medium text-gray-700 mb-1';

interface Draft {
  choices: Record<ConsentKey, Choice>;
  childAssent?: boolean;
  givenName: string;
  paternalName: string;
  maternalName: string;
  birthDate: string;
  birthEstimated: boolean;
  sexId: number | '';
  nationality: string;
  language: string;
  relationship: Relationship | '';
  otherRelationship: string;
  markers: VulnerabilityMarkerCode[];
  note: string;
}
// Borradores en memoria, por caso principal: se pierden al recargar la página, a propósito
const drafts = new Map<string, Draft>();

// Fecha más antigua que todavía corresponde a una persona menor de 18 años
function earliestBirth(): string {
  const d = new Date();
  d.setFullYear(d.getFullYear() - 18);
  d.setDate(d.getDate() + 1);
  return d.toISOString().slice(0, 10);
}

function ageYears(isoDate: string): number {
  const b = new Date(isoDate);
  if (Number.isNaN(b.getTime())) return 99;
  const now = new Date();
  let age = now.getFullYear() - b.getFullYear();
  const m = now.getMonth() - b.getMonth();
  if (m < 0 || (m === 0 && now.getDate() < b.getDate())) age--;
  return age;
}

interface NewSubfolioPageProps {
  parent: CaseWithDetails;
  /** Enlace «Volver al caso»: el borrador se conserva */
  onBack: () => void;
  /** Botón «Cancelar»: el borrador se borra */
  onCancel: () => void;
  onSubmit: (input: SubfolioInput) => void;
}

export const NewSubfolioPage: React.FC<NewSubfolioPageProps> = ({ parent, onBack, onCancel, onSubmit }) => {
  const uid = useId();

  // Decisión vigente de quien representa en el caso principal (la más reciente de cada tipo)
  const inherited = useMemo(() => {
    const latest = (key: ConsentKey): Choice => {
      const c = (parent.consents ?? [])
        .filter((x) => x.consent_type === key)
        .sort((a, b) => b.granted_at.localeCompare(a.granted_at))[0];
      return c ? (c.status === 'granted' ? 'yes' : 'no') : null;
    };
    return { general_care: latest('general_care'), sensitive_data: latest('sensitive_data'), secondary_use_research: latest('secondary_use_research') } as Record<ConsentKey, Choice>;
  }, [parent.consents]);

  const saved = drafts.get(parent.id);
  const [choices, setChoices] = useState<Record<ConsentKey, Choice>>(saved?.choices ?? inherited);
  // Sin valores supuestos: el asentimiento, el vínculo, el sexo, la nacionalidad y la lengua los decide quien captura
  const [childAssent, setChildAssent] = useState(saved?.childAssent ?? false);
  const [showNnaModal, setShowNnaModal] = useState(false);
  const [givenName, setGivenName] = useState(saved?.givenName ?? '');
  const [paternalName, setPaternalName] = useState(saved?.paternalName ?? '');
  const [maternalName, setMaternalName] = useState(saved?.maternalName ?? '');
  const [birthDate, setBirthDate] = useState(saved?.birthDate ?? '');
  const [birthEstimated, setBirthEstimated] = useState(saved?.birthEstimated ?? false);
  const [sexId, setSexId] = useState<number | ''>(saved?.sexId ?? '');
  const [nationality, setNationality] = useState(saved?.nationality ?? '');
  const [language, setLanguage] = useState(saved?.language ?? '');
  const [relationship, setRelationship] = useState<Relationship | ''>(saved?.relationship ?? '');
  const [otherRelationship, setOtherRelationship] = useState(saved?.otherRelationship ?? '');
  const [markers, setMarkers] = useState<VulnerabilityMarkerCode[]>(saved?.markers ?? []);
  const [note, setNote] = useState(saved?.note ?? '');

  // Lo capturado se conserva en memoria; si hay algo escrito, el navegador pregunta antes de recargar o cerrar
  const dirty = !!(givenName || paternalName || maternalName || birthDate || otherRelationship || note || markers.length);
  useEffect(() => {
    drafts.set(parent.id, { choices, childAssent, givenName, paternalName, maternalName, birthDate, birthEstimated, sexId, nationality, language, relationship, otherRelationship, markers, note });
  }, [parent.id, choices, childAssent, givenName, paternalName, maternalName, birthDate, birthEstimated, sexId, nationality, language, relationship, otherRelationship, markers, note]);
  useEffect(() => {
    if (!dirty) return;
    const guard = (e: BeforeUnloadEvent) => e.preventDefault();
    window.addEventListener('beforeunload', guard);
    return () => window.removeEventListener('beforeunload', guard);
  }, [dirty]);

  const sensitiveGranted = choices.sensitive_data === 'yes';
  const guardianRole = relationship === '' ? '' : relationship === 'other' ? otherRelationship.trim() : t(`subfolio.rel_${relationship}`);
  const representative = [parent.person.given_name, parent.person.paternal_family_name, parent.person.maternal_family_name].filter(Boolean).join(' ');

  // El error de un campo se dice junto al campo, además de en la barra de acciones
  const birthProblem = birthDate && ageYears(birthDate) >= 18 ? t('subfolio.reason_minor') : null;
  const reason: string | null = !givenName.trim()
    ? t('intake.reason.given_name')
    : !paternalName.trim()
      ? t('intake.reason.paternal_name')
      : !birthDate
        ? t('subfolio.reason_birth')
        : birthProblem
          ? birthProblem
          : !guardianRole
            ? t('subfolio.reason_relationship')
            : choices.general_care !== 'yes'
              ? t('subfolio.reason_general')
              : !childAssent
                ? t('subfolio.reason_assent')
              : note.trim().length < MIN_NOTE
                ? t('subfolio.reason_note')
                : null;

  const finish = () => {
    drafts.delete(parent.id);
  };

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    if (reason) return;
    finish();
    onSubmit({
      parent_case_id: parent.id,
      given_name: givenName.trim(),
      paternal_family_name: paternalName.trim(),
      maternal_family_name: maternalName.trim() || null,
      preferred_name: null,
      birth_date: birthDate,
      birth_date_is_estimated: birthEstimated,
      sex_id: sensitiveGranted && sexId !== '' ? sexId : null,
      nationality_country_id: sensitiveGranted && nationality ? (COUNTRY_ID[nationality] ?? 1) : null,
      other_nationality: sensitiveGranted && nationality ? nationality : null,
      // Aún no hay catálogo de lenguas: se guarda lo que se escribió y el identificador queda vacío
      primary_language_id: null,
      other_language: sensitiveGranted && language.trim() ? language.trim() : null,
      guardian_role: guardianRole,
      justification: note.trim(),
      vulnerability_codes: sensitiveGranted ? markers : [],
      consents: CONSENT_KEYS.filter((k) => choices[k] === 'yes').map((k) => ({
        consent_type: k,
        status: 'granted' as const,
        is_minor_assent: childAssent,
      })),
    });
  };

  const cancel = () => {
    finish();
    onCancel();
  };

  const markerCodes = (Object.keys(VULNERABILITY_CATALOG) as VulnerabilityMarkerCode[]).filter((c) => c !== 'unaccompanied_child');

  return (
    <div className="mx-auto max-w-6xl space-y-5">
      <div>
        <button type="button" onClick={onBack} className="inline-flex min-h-11 items-center gap-1.5 text-sm font-semibold text-turquesa-dark hover:underline">
          <ArrowLeft className="h-4 w-4" aria-hidden="true" />
          {t('subfolio.back_to_case').replace('{folio}', parent.case_number)}
        </button>
        <h2 className="font-title text-2xl font-bold text-carbon">{t('subfolio.title')}</h2>
        <p className="mt-1 text-sm text-gray-600">{t('subfolio.subtitle').replace('{folio}', parent.case_number)}</p>
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,1fr)_20rem]">
        <form onSubmit={submit} className="min-w-0 space-y-6">
          <fieldset className="space-y-3 rounded-2xl border border-gray-200 bg-white p-5">
            <legend className="px-1 text-base font-bold text-carbon">{t('subfolio.section_person')}</legend>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
              <div>
                <label className={LABEL} htmlFor={`${uid}-given`}>{t('intake.field_given_name')}</label>
                <input id={`${uid}-given`} className={INPUT} value={givenName} onChange={(e) => setGivenName(e.target.value)} autoComplete="off" />
              </div>
              <div>
                <label className={LABEL} htmlFor={`${uid}-paternal`}>{t('intake.field_paternal_name')}</label>
                <input id={`${uid}-paternal`} className={INPUT} value={paternalName} onChange={(e) => setPaternalName(e.target.value)} autoComplete="off" />
              </div>
              <div>
                <label className={LABEL} htmlFor={`${uid}-maternal`}>{t('intake.field_maternal_name')}</label>
                <input id={`${uid}-maternal`} className={INPUT} value={maternalName} onChange={(e) => setMaternalName(e.target.value)} autoComplete="off" />
              </div>
            </div>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div>
                <label className={LABEL} htmlFor={`${uid}-birth`}>{t('intake.field_birth_date')}</label>
                <input
                  id={`${uid}-birth`}
                  type="date"
                  className={birthProblem ? `${INPUT} border-alerta-dark bg-alerta-bg/40` : INPUT}
                  value={birthDate}
                  min={earliestBirth()}
                  max={new Date().toISOString().slice(0, 10)}
                  onChange={(e) => setBirthDate(e.target.value)}
                  aria-invalid={birthProblem ? true : undefined}
                  aria-describedby={birthProblem ? `${uid}-birth-error` : undefined}
                />
                {birthProblem && (
                  <p id={`${uid}-birth-error`} role="alert" className="mt-1 text-sm font-semibold text-alerta-dark">
                    {birthProblem}
                  </p>
                )}
                <label className="mt-1.5 flex min-h-11 cursor-pointer items-center gap-2 text-sm text-gray-600">
                  <input type="checkbox" checked={birthEstimated} onChange={(e) => setBirthEstimated(e.target.checked)} className="h-4 w-4 rounded border-gray-300 text-turquesa" />
                  <span>{t('intake.field_birth_estimated')}</span>
                </label>
              </div>
              <div>
                <label className={LABEL} htmlFor={`${uid}-sex`}>{t('intake.field_sex')}</label>
                <select
                  id={`${uid}-sex`}
                  disabled={!sensitiveGranted}
                  className={`${INPUT} disabled:bg-gray-100 disabled:text-gray-400 disabled:cursor-not-allowed`}
                  value={sexId}
                  onChange={(e) => setSexId(e.target.value === '' ? '' : Number(e.target.value))}
                >
                  <option value="">{t('common.not_recorded')}</option>
                  <option value={1}>{t('intake.sex_1')}</option>
                  <option value={2}>{t('intake.sex_2')}</option>
                  <option value={3}>{t('intake.sex_3')}</option>
                </select>
                {!sensitiveGranted && (
                  <span className="mt-1 block text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded px-1.5 py-0.5">
                    {t('intake.consent.sensitive_disabled_notice')}
                  </span>
                )}
              </div>
            </div>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div>
                <label className={LABEL} htmlFor={`${uid}-nat`}>{t('intake.field_nationality')}</label>
                <select
                  id={`${uid}-nat`}
                  disabled={!sensitiveGranted}
                  className={`${INPUT} disabled:bg-gray-100 disabled:text-gray-400 disabled:cursor-not-allowed`}
                  value={nationality}
                  onChange={(e) => setNationality(e.target.value)}
                >
                  <option value="">{t('common.not_recorded')}</option>
                  {nationality !== '' && !COUNTRIES.some((c) => c.value === nationality) && <option value={nationality}>{nationality}</option>}
                  {COUNTRIES.map((c) => (
                    <option key={c.value} value={c.value}>{t(c.key)}</option>
                  ))}
                </select>
                {!sensitiveGranted && (
                  <span className="mt-1 block text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded px-1.5 py-0.5">
                    {t('intake.consent.sensitive_disabled_notice')}
                  </span>
                )}
              </div>
              <div>
                <label className={LABEL} htmlFor={`${uid}-lang`}>{t('intake.field_primary_language')}</label>
                <input
                  id={`${uid}-lang`}
                  disabled={!sensitiveGranted}
                  className={`${INPUT} disabled:bg-gray-100 disabled:text-gray-400 disabled:cursor-not-allowed`}
                  value={language}
                  onChange={(e) => setLanguage(e.target.value)}
                  autoComplete="off"
                />
                {!sensitiveGranted && (
                  <span className="mt-1 block text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded px-1.5 py-0.5">
                    {t('intake.consent.sensitive_disabled_notice')}
                  </span>
                )}
              </div>
            </div>
          </fieldset>

          <fieldset className="space-y-3 rounded-2xl border border-gray-200 bg-white p-5">
            <legend className="px-1 text-base font-bold text-carbon">{t('subfolio.section_relationship')}</legend>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div>
                <label className={LABEL} htmlFor={`${uid}-rel`}>{t('subfolio.relationship')}</label>
                <select id={`${uid}-rel`} className={INPUT} value={relationship} onChange={(e) => setRelationship(e.target.value as Relationship | '')}>
                  <option value="">{t('subfolio.rel_choose')}</option>
                  <option value="mother">{t('subfolio.rel_mother')}</option>
                  <option value="father">{t('subfolio.rel_father')}</option>
                  <option value="guardian">{t('subfolio.rel_guardian')}</option>
                  <option value="other">{t('subfolio.rel_other')}</option>
                </select>
              </div>
              {relationship === 'other' && (
                <div>
                  <label className={LABEL} htmlFor={`${uid}-rel-other`}>{t('subfolio.rel_other_label')}</label>
                  <input id={`${uid}-rel-other`} className={INPUT} value={otherRelationship} onChange={(e) => setOtherRelationship(e.target.value)} autoComplete="off" />
                </div>
              )}
            </div>
          </fieldset>

          <fieldset className="space-y-3 rounded-2xl border border-gray-200 bg-white p-5">
            <legend className="px-1 text-base font-bold text-carbon">{t('subfolio.section_consents')}</legend>
            <p className="text-sm text-gray-600">{t('subfolio.consents_hint')}</p>

            <div className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-turquesa/30 bg-claro/30 p-3">
              <label className="flex items-center gap-2 text-xs font-semibold text-carbon cursor-pointer">
                <input
                  type="checkbox"
                  checked={childAssent}
                  onChange={(e) => setChildAssent(e.target.checked)}
                  className="h-4 w-4 rounded border-gray-300 text-turquesa focus:ring-turquesa"
                />
                <span>{t('subfolio.child_assent_check')}</span>
              </label>
              <button
                type="button"
                onClick={() => setShowNnaModal(true)}
                className="inline-flex items-center gap-1.5 rounded-lg border border-turquesa/40 bg-white px-2.5 py-1 text-xs font-semibold text-turquesa-dark hover:bg-claro shadow-2xs"
              >
                <BookOpen className="w-3.5 h-3.5" />
                <span>{t('nna_guide.open_btn')}</span>
              </button>
            </div>
            {CONSENT_KEYS.map((key) => (
              <div key={key} className="rounded-xl border border-gray-200 p-3" role="radiogroup" aria-labelledby={`${uid}-c-${key}`}>
                <p id={`${uid}-c-${key}`} className="text-sm font-semibold text-carbon">{t(`arco.consent_types.${key}`)}</p>
                <p className="mt-0.5 text-sm text-gray-600">{t(`intake.consent.desc.${key}`)}</p>
                <div className="mt-2 flex flex-wrap gap-2">
                  {(['yes', 'no'] as const).map((v) => (
                    <label key={v} className={`inline-flex min-h-11 cursor-pointer items-center gap-2 rounded-lg border px-3 text-sm ${choices[key] === v ? 'border-turquesa bg-claro font-semibold text-carbon' : 'border-gray-300 text-gray-700'}`}>
                      <input
                        type="radio"
                        name={`${uid}-${key}`}
                        value={v}
                        checked={choices[key] === v}
                        onChange={() => setChoices((c) => ({ ...c, [key]: v }))}
                        className="text-turquesa"
                      />
                      {t(v === 'yes' ? 'intake.consent.choice_yes' : 'intake.consent.choice_no')}
                    </label>
                  ))}
                </div>
              </div>
            ))}
          </fieldset>

          {sensitiveGranted && (
            <fieldset className="space-y-2 rounded-2xl border border-gray-200 bg-white p-5">
              <legend className="px-1 text-base font-bold text-carbon">{t('subfolio.section_markers')}</legend>
              <p className="text-sm text-gray-600">{t('subfolio.markers_hint')}</p>
              {markerCodes.map((code) => (
                <label key={code} className="flex min-h-11 cursor-pointer items-start gap-3 rounded-xl border border-gray-200 p-3">
                  <input
                    type="checkbox"
                    checked={markers.includes(code)}
                    onChange={() => setMarkers((m) => (m.includes(code) ? m.filter((x) => x !== code) : [...m, code]))}
                    className="mt-0.5 h-4 w-4 rounded border-gray-300"
                  />
                  <span className="text-sm">
                    <span className="block font-bold text-carbon">{VULNERABILITY_CATALOG[code].label}</span>
                    <span className="text-gray-600">{VULNERABILITY_CATALOG[code].description}</span>
                  </span>
                </label>
              ))}
            </fieldset>
          )}

          <div className="rounded-2xl border border-gray-200 bg-white p-5">
            <label className="mb-1 block text-base font-bold text-carbon" htmlFor={`${uid}-note`}>{t('subfolio.note_label')}</label>
            <p className="mb-2 text-sm text-gray-600">{t('subfolio.note_hint')}</p>
            <textarea id={`${uid}-note`} className={INPUT} rows={3} value={note} onChange={(e) => setNote(e.target.value)} />
          </div>

          {/* Barra de acciones: siempre a la vista; en celular queda sobre la barra de navegación */}
          <div className="sticky bottom-[calc(3.5rem+env(safe-area-inset-bottom))] z-30 -mx-4 border-t border-gray-200 bg-white/95 px-4 py-3 backdrop-blur md:bottom-0 md:mx-0 md:rounded-2xl md:border">
            <DisabledReason id={uid} reason={reason} className="mb-2" />
            <div className="flex items-center justify-between gap-3">
              <button type="button" onClick={cancel} className="min-h-11 rounded-lg border border-gray-300 bg-white px-4 text-sm font-semibold text-gray-700 hover:bg-gray-50">
                {t('common.cancel')}
              </button>
              <button
                type="submit"
                disabled={!!reason}
                {...describedBy(uid, reason)}
                className="inline-flex min-h-11 items-center gap-1.5 rounded-lg bg-carbon px-5 text-sm font-bold text-white shadow-md hover:bg-black disabled:cursor-not-allowed disabled:opacity-50"
              >
                <HeartHandshake className="h-4 w-4 text-turquesa" aria-hidden="true" />
                {t('subfolio.create')}
              </button>
            </div>
          </div>
        </form>

        {/* Contexto: el caso principal a la vista mientras se llena */}
        <aside aria-label={t('subfolio.context_title')} className="space-y-3 lg:sticky lg:top-20 lg:self-start">
          <section className="rounded-2xl border border-gray-200 bg-white p-5">
            <h3 className="text-base font-bold text-carbon">{t('subfolio.context_title')}</h3>
            <dl className="mt-3 space-y-3 text-sm">
              <div>
                <dt className="text-gray-600">{t('subfolio.context_folio')}</dt>
                <dd className="font-mono font-bold text-carbon">{parent.case_number}</dd>
              </div>
              <div>
                <dt className="text-gray-600">{t('subfolio.context_representative')}</dt>
                <dd className="font-semibold text-carbon">{representative}</dd>
              </div>
              <div>
                <dt className="text-gray-600">{t('subfolio.context_status')}</dt>
                <dd className="font-semibold text-carbon">{parent.statuses.engagement_status?.label}</dd>
              </div>
              <div>
                <dt className="text-gray-600">{t('subfolio.context_consents')}</dt>
                <dd>
                  <ul className="mt-1 space-y-1">
                    {CONSENT_KEYS.map((key) => (
                      <li key={key} className="flex justify-between gap-3">
                        <span className="text-gray-700">{t(`arco.consent_types.${key}`)}</span>
                        <span className="shrink-0 font-semibold text-carbon">
                          {inherited[key] === null ? t('subfolio.context_none') : t(inherited[key] === 'yes' ? 'intake.consent.choice_yes' : 'intake.consent.choice_no')}
                        </span>
                      </li>
                    ))}
                  </ul>
                </dd>
              </div>
              <div>
                <dt className="text-gray-600">{t('subfolio.context_subfolios')}</dt>
                <dd className="font-semibold text-carbon">
                  {(parent.subfolios?.length ?? 0) === 0
                    ? t('subfolio.context_no_subfolios')
                    : (parent.subfolios ?? []).map((s) => s.case_number).join(', ')}
                </dd>
              </div>
            </dl>
          </section>
          <p className="px-1 text-sm text-gray-600">{t('subfolio.representative').replace('{name}', representative).replace('{folio}', parent.case_number)}</p>
        </aside>
      </div>

      <NnaAssentModal isOpen={showNnaModal} onClose={() => setShowNnaModal(false)} />
    </div>
  );
};
