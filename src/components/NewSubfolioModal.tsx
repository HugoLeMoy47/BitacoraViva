import { useId, useState } from 'react';
import { X, HeartHandshake } from 'lucide-react';
import { t } from '../lib/i18n';
import { CaseWithDetails, VulnerabilityMarkerCode } from '../types/database';
import { VULNERABILITY_CATALOG } from '../lib/catalogs';
import { ConsentInput, SubfolioInput } from '../lib/data';
import { DisabledReason, describedBy } from './DisabledReason';
import { ModalShell } from './ModalShell';

// BV-3.2 · Subfolio: expediente propio de una persona menor que viaja con quien tiene el folio principal.
// Quien representa es la persona titular del caso principal (la base toma su nombre de ahí; aquí solo se
// pide el parentesco). Los consentimientos llegan con la decisión que ya tomó, se pueden ajustar, y la nota
// de justificación es obligatoria.

type Choice = 'yes' | 'no' | null;
type ConsentKey = Exclude<ConsentInput['consent_type'], 'internal_sharing'>;
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
const INPUT = 'w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa';
const LABEL = 'block text-xs font-medium text-gray-700 mb-1';

function ageYears(isoDate: string): number {
  const b = new Date(isoDate);
  if (Number.isNaN(b.getTime())) return 99;
  const now = new Date();
  let age = now.getFullYear() - b.getFullYear();
  const m = now.getMonth() - b.getMonth();
  if (m < 0 || (m === 0 && now.getDate() < b.getDate())) age--;
  return age;
}

interface NewSubfolioModalProps {
  parent: CaseWithDetails;
  onClose: () => void;
  onSubmit: (input: SubfolioInput) => void;
}

export const NewSubfolioModal: React.FC<NewSubfolioModalProps> = ({ parent, onClose, onSubmit }) => {
  const uid = useId();

  // Decisión vigente de quien representa en el caso principal (la más reciente de cada tipo)
  const inherited = (key: ConsentKey): Choice => {
    const latest = (parent.consents ?? [])
      .filter((c) => c.consent_type === key)
      .sort((a, b) => b.granted_at.localeCompare(a.granted_at))[0];
    return latest ? (latest.status === 'granted' ? 'yes' : 'no') : null;
  };
  const [choices, setChoices] = useState<Record<ConsentKey, Choice>>(() => ({
    general_care: inherited('general_care'),
    sensitive_data: inherited('sensitive_data'),
    secondary_use_research: inherited('secondary_use_research'),
  }));

  const [givenName, setGivenName] = useState('');
  const [paternalName, setPaternalName] = useState('');
  const [maternalName, setMaternalName] = useState('');
  const [birthDate, setBirthDate] = useState('');
  const [birthEstimated, setBirthEstimated] = useState(false);
  const [sexId, setSexId] = useState(1);
  const [nationality, setNationality] = useState(parent.person.other_nationality || 'Honduras');
  const [language, setLanguage] = useState(parent.person.other_language || 'Español');
  const [relationship, setRelationship] = useState<'mother' | 'father' | 'guardian' | 'other'>('mother');
  const [otherRelationship, setOtherRelationship] = useState('');
  const [markers, setMarkers] = useState<VulnerabilityMarkerCode[]>([]);
  const [note, setNote] = useState('');

  const sensitiveGranted = choices.sensitive_data === 'yes';
  const guardianRole = relationship === 'other' ? otherRelationship.trim() : t(`subfolio.rel_${relationship}`);
  const representative = [parent.person.given_name, parent.person.paternal_family_name, parent.person.maternal_family_name]
    .filter(Boolean)
    .join(' ');

  const reason: string | null = !givenName.trim()
    ? t('intake.reason.given_name')
    : !paternalName.trim()
      ? t('intake.reason.paternal_name')
      : !birthDate
        ? t('subfolio.reason_birth')
        : ageYears(birthDate) >= 18
          ? t('subfolio.reason_minor')
          : !guardianRole
            ? t('subfolio.reason_relationship')
            : choices.general_care !== 'yes'
              ? t('subfolio.reason_general')
              : note.trim().length < MIN_NOTE
                ? t('subfolio.reason_note')
                : null;

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    if (reason) return;
    onSubmit({
      parent_case_id: parent.id,
      given_name: givenName.trim(),
      paternal_family_name: paternalName.trim(),
      maternal_family_name: maternalName.trim() || null,
      preferred_name: null,
      birth_date: birthDate,
      birth_date_is_estimated: birthEstimated,
      sex_id: sexId,
      nationality_country_id: COUNTRY_ID[nationality] ?? 1,
      other_nationality: nationality,
      primary_language_id: 1,
      other_language: language.trim() || null,
      guardian_role: guardianRole,
      justification: note.trim(),
      vulnerability_codes: sensitiveGranted ? markers : [],
      consents: CONSENT_KEYS.filter((k) => choices[k] === 'yes').map((k) => ({
        consent_type: k,
        status: 'granted' as const,
        is_minor_assent: true,
      })),
    });
    onClose();
  };

  const markerCodes = (Object.keys(VULNERABILITY_CATALOG) as VulnerabilityMarkerCode[]).filter((c) => c !== 'unaccompanied_child');

  return (
    <ModalShell onClose={onClose} className="fixed inset-0 z-50 bg-black/50 backdrop-blur-sm flex items-center justify-center p-4 overflow-y-auto">
      <form onSubmit={submit} className="bg-white rounded-2xl shadow-xl border border-gray-200 w-full max-w-2xl overflow-hidden my-8">
        <div className="px-6 py-4 bg-carbon text-white flex justify-between items-center border-b border-gray-700">
          <div>
            <h3 className="text-base font-bold">{t('subfolio.title')}</h3>
            <p className="text-xs text-gray-300">{t('subfolio.subtitle').replace('{folio}', parent.case_number)}</p>
          </div>
          <button type="button" onClick={onClose} aria-label={t('session.dismiss')} className="p-1 rounded-lg hover:bg-gray-800 text-gray-300 hover:text-white">
            <X className="w-5 h-5" />
          </button>
        </div>

        <div className="p-6 space-y-5 text-xs">
          <p className="rounded-lg border border-gray-200 bg-gray-50 p-3 text-gray-700">
            {t('subfolio.representative').replace('{name}', representative).replace('{folio}', parent.case_number)}
          </p>

          <fieldset className="space-y-3">
            <legend className="text-sm font-bold text-carbon">{t('subfolio.section_person')}</legend>
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
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
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <label className={LABEL} htmlFor={`${uid}-birth`}>{t('intake.field_birth_date')}</label>
                <input id={`${uid}-birth`} type="date" className={INPUT} value={birthDate} max={new Date().toISOString().slice(0, 10)} onChange={(e) => setBirthDate(e.target.value)} />
                <label className="flex items-center gap-2 mt-1.5 cursor-pointer text-gray-600">
                  <input type="checkbox" checked={birthEstimated} onChange={(e) => setBirthEstimated(e.target.checked)} className="rounded text-turquesa border-gray-300" />
                  <span>{t('intake.field_birth_estimated')}</span>
                </label>
              </div>
              <div>
                <label className={LABEL} htmlFor={`${uid}-sex`}>{t('intake.field_sex')}</label>
                <select id={`${uid}-sex`} className={INPUT} value={sexId} onChange={(e) => setSexId(Number(e.target.value))}>
                  <option value={1}>{t('intake.sex_1')}</option>
                  <option value={2}>{t('intake.sex_2')}</option>
                  <option value={3}>{t('intake.sex_3')}</option>
                </select>
              </div>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <label className={LABEL} htmlFor={`${uid}-nat`}>{t('intake.field_nationality')}</label>
                <select id={`${uid}-nat`} className={INPUT} value={nationality} onChange={(e) => setNationality(e.target.value)}>
                  {!COUNTRIES.some((c) => c.value === nationality) && <option value={nationality}>{nationality}</option>}
                  {COUNTRIES.map((c) => (
                    <option key={c.value} value={c.value}>{t(c.key)}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className={LABEL} htmlFor={`${uid}-lang`}>{t('intake.field_primary_language')}</label>
                <input id={`${uid}-lang`} className={INPUT} value={language} onChange={(e) => setLanguage(e.target.value)} autoComplete="off" />
              </div>
            </div>
          </fieldset>

          <fieldset className="space-y-3">
            <legend className="text-sm font-bold text-carbon">{t('subfolio.section_relationship')}</legend>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <label className={LABEL} htmlFor={`${uid}-rel`}>{t('subfolio.relationship')}</label>
                <select id={`${uid}-rel`} className={INPUT} value={relationship} onChange={(e) => setRelationship(e.target.value as typeof relationship)}>
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

          <fieldset className="space-y-3">
            <legend className="text-sm font-bold text-carbon">{t('subfolio.section_consents')}</legend>
            <p className="text-gray-600">{t('subfolio.consents_hint')}</p>
            {CONSENT_KEYS.map((key) => (
              <div key={key} className="rounded-xl border border-gray-200 p-3" role="radiogroup" aria-labelledby={`${uid}-c-${key}`}>
                <p id={`${uid}-c-${key}`} className="font-semibold text-carbon">{t(`arco.consent_types.${key}`)}</p>
                <p className="text-gray-500 mt-0.5">{t(`intake.consent.desc.${key}`)}</p>
                <div className="mt-2 flex flex-wrap gap-2">
                  {(['yes', 'no'] as const).map((v) => (
                    <label key={v} className={`inline-flex min-h-11 cursor-pointer items-center gap-2 rounded-lg border px-3 ${choices[key] === v ? 'border-turquesa bg-claro font-semibold text-carbon' : 'border-gray-300 text-gray-700'}`}>
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
            <fieldset className="space-y-2">
              <legend className="text-sm font-bold text-carbon">{t('subfolio.section_markers')}</legend>
              <p className="text-gray-600">{t('subfolio.markers_hint')}</p>
              {markerCodes.map((code) => (
                <label key={code} className="flex items-start gap-3 rounded-xl border border-gray-200 p-3 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={markers.includes(code)}
                    onChange={() => setMarkers((m) => (m.includes(code) ? m.filter((x) => x !== code) : [...m, code]))}
                    className="mt-0.5 w-4 h-4 rounded border-gray-300"
                  />
                  <span>
                    <span className="font-bold block text-carbon">{VULNERABILITY_CATALOG[code].label}</span>
                    <span className="text-gray-500">{VULNERABILITY_CATALOG[code].description}</span>
                  </span>
                </label>
              ))}
            </fieldset>
          )}

          <div>
            <label className="block text-sm font-bold text-carbon mb-1" htmlFor={`${uid}-note`}>{t('subfolio.note_label')}</label>
            <p className="text-gray-600 mb-1.5">{t('subfolio.note_hint')}</p>
            <textarea id={`${uid}-note`} className={INPUT} rows={3} value={note} onChange={(e) => setNote(e.target.value)} />
          </div>
        </div>

        <DisabledReason id={uid} reason={reason} className="border-t border-gray-200 bg-gray-50 px-6 pt-3" />
        <div className="px-6 py-4 bg-gray-50 border-t border-gray-200 flex justify-between items-center text-xs">
          <button type="button" onClick={onClose} className="px-4 py-2 font-semibold text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-100">
            {t('common.cancel')}
          </button>
          <button
            type="submit"
            disabled={!!reason}
            {...describedBy(uid, reason)}
            className="px-5 py-2 font-bold text-white bg-carbon hover:bg-black rounded-lg shadow-md flex items-center gap-1.5 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <HeartHandshake className="w-4 h-4 text-turquesa" aria-hidden="true" />
            {t('subfolio.create')}
          </button>
        </div>
      </form>
    </ModalShell>
  );
};
