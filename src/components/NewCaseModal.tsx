import { useState } from 'react';
import { X, CheckCircle2, HeartHandshake } from 'lucide-react';
import { t } from '../lib/i18n';
import { CaseWithDetails, VulnerabilityMarkerCode } from '../types/database';
import { VULNERABILITY_CATALOG } from '../lib/catalogs';

interface NewCaseModalProps {
  isOpen: boolean;
  onClose: () => void;
  onCaseCreated: (newCase: CaseWithDetails) => void;
  authorUserId: string;
  authorFullName: string;
}

export const NewCaseModal: React.FC<NewCaseModalProps> = ({
  isOpen,
  onClose,
  onCaseCreated,
  authorUserId,
  authorFullName,
}) => {
  const [step, setStep] = useState<1 | 2 | 3 | 4>(1);

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

  // Paso 3: Vulnerabilidades (13 marcadores)
  const [selectedVulnerabilities, setSelectedVulnerabilities] = useState<VulnerabilityMarkerCode[]>([]);

  if (!isOpen) return null;

  const toggleVulnerability = (code: VulnerabilityMarkerCode) => {
    setSelectedVulnerabilities((prev) =>
      prev.includes(code) ? prev.filter((c) => c !== code) : [...prev, code]
    );
  };

  const handleFinish = () => {
    const timestamp = new Date().toISOString();
    const randomSeq = Math.floor(1000 + Math.random() * 9000);
    const folio = `ASF-2026-${randomSeq}`;
    const newPersonId = `p-${Date.now()}`;
    const newCaseId = `c-${Date.now()}`;

    const newCase: CaseWithDetails = {
      id: newCaseId,
      organization_id: '00000000-0000-0000-0000-000000000001',
      case_number: folio,
      parent_case_id: null,
      previous_case_id: null,
      titular_person_id: newPersonId,
      intake_state_id: 9,
      intake_municipality_id: 15,
      intake_channel_id: 1,
      intake_window_type: windowType,
      intake_date: timestamp.substring(0, 10),
      entry_route_id: 3,
      entry_date_str: 'Octubre 2026',
      travels_with_family: travelsWithFamily,
      opened_at: timestamp,
      opened_by: authorUserId,
      assigned_area_id: '10000000-0000-0000-0000-000000000001',
      assigned_user_id: authorUserId,
      created_at: timestamp,
      updated_at: timestamp,
      person: {
        id: newPersonId,
        organization_id: '00000000-0000-0000-0000-000000000001',
        given_name: givenName || 'Persona',
        paternal_family_name: paternalName || 'Registrada',
        maternal_family_name: maternalName || null,
        preferred_name: preferredName || givenName || 'Persona',
        birth_date: birthDate,
        birth_date_is_estimated: birthDateEstimated,
        sex_id: sexId,
        nationality_country_id: 93,
        other_nationality: nationalityCountry,
        is_self_identified_migrant: true,
        primary_language_id: 1,
        other_language: primaryLanguage,
        occupations: [],
        phone_number: phone || null,
        email: null,
        is_anonymized: false,
        created_at: timestamp,
        updated_at: timestamp,
      },
      vulnerabilities: selectedVulnerabilities.map((vCode, i) => ({
        id: `vm-${Date.now()}-${i}`,
        organization_id: '00000000-0000-0000-0000-000000000001',
        case_id: newCaseId,
        marker_code: vCode,
        notes: `Afirmado en ventanilla por ${authorFullName}`,
        affirmed_by: authorFullName,
        affirmed_at: timestamp,
        created_at: timestamp,
      })),
      // Todo caso nace con los 5 ejes poblados (BV-2.2 / Regla Dura 7)
      statuses: {
        legal_status: {
          valueCode: 'undetermined',
          label: 'Sin determinar',
          valid_from: timestamp,
          reason: 'Apertura de expediente e ingreso en ventanilla',
        },
        engagement_status: {
          valueCode: 'first_contact',
          label: 'Primer contacto',
          valid_from: timestamp,
          reason: 'Apertura de expediente e ingreso en ventanilla',
          isActiveCare: false,
        },
        shelter_status: {
          valueCode: 'sheltered',
          label: 'Albergada en el centro',
          valid_from: timestamp,
          reason: 'Registro inicial de estancia',
        },
        record_status: {
          valueCode: 'open',
          label: 'Abierto',
          valid_from: timestamp,
          reason: 'Expediente formalmente abierto y en trámite',
        },
        case_stage: {
          valueCode: 'intake',
          label: 'Recepción e Ingreso',
          valid_from: timestamp,
          reason: 'Paso 1 del ciclo estándar de gestión de caso',
        },
      },
      journal_entries: [],
      consents: [
        {
          id: `cons-${Date.now()}-1`,
          organization_id: '00000000-0000-0000-0000-000000000001',
          person_id: newPersonId,
          case_id: newCaseId,
          consent_type: 'general_care',
          status: 'granted',
          is_minor_assent: selectedVulnerabilities.includes('unaccompanied_child'),
          granted_at: timestamp,
          granted_by_user_id: authorUserId,
          granted_by_name: authorFullName,
          notes: 'Consentimiento informado general otorgado en proceso de ingreso (BV-5.1).',
          created_at: timestamp,
        },
        {
          id: `cons-${Date.now()}-2`,
          organization_id: '00000000-0000-0000-0000-000000000001',
          person_id: newPersonId,
          case_id: newCaseId,
          consent_type: 'sensitive_data',
          status: 'granted',
          is_minor_assent: selectedVulnerabilities.includes('unaccompanied_child'),
          granted_at: timestamp,
          granted_by_user_id: authorUserId,
          granted_by_name: authorFullName,
          notes: 'Consentimiento expreso para datos sensibles firmado en admisión (Control P-06).',
          created_at: timestamp,
        },
      ],
      arco_requests: [],
    };

    onCaseCreated(newCase);
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/50 backdrop-blur-sm flex items-center justify-center p-4 overflow-y-auto">
      <div className="bg-white rounded-2xl shadow-xl border border-gray-200 w-full max-w-2xl overflow-hidden my-8">
        {/* Cabecera del modal */}
        <div className="px-6 py-4 bg-carbon text-white flex justify-between items-center border-b border-gray-700">
          <div>
            <h3 className="text-base font-bold">{t('intake.modal_title')}</h3>
            <p className="text-xs text-gray-400">Estándar humanitario MAP Fase 1 y 2 · Gobernanza BV-3.1</p>
          </div>
          <button onClick={onClose} className="p-1 rounded-lg hover:bg-gray-800 text-gray-400 hover:text-white">
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Indicador de pasos */}
        <div className="grid grid-cols-4 bg-gray-100 text-xs font-medium text-center border-b border-gray-200">
          <div className={`py-2.5 px-2 border-b-2 ${step === 1 ? 'border-turquesa text-carbon font-bold bg-white' : 'border-transparent text-gray-500'}`}>
            1. Contexto
          </div>
          <div className={`py-2.5 px-2 border-b-2 ${step === 2 ? 'border-turquesa text-carbon font-bold bg-white' : 'border-transparent text-gray-500'}`}>
            2. Ficha Persona
          </div>
          <div className={`py-2.5 px-2 border-b-2 ${step === 3 ? 'border-turquesa text-carbon font-bold bg-white' : 'border-transparent text-gray-500'}`}>
            3. Vulnerabilidades
          </div>
          <div className={`py-2.5 px-2 border-b-2 ${step === 4 ? 'border-turquesa text-carbon font-bold bg-white' : 'border-transparent text-gray-500'}`}>
            4. Confirmar
          </div>
        </div>

        {/* Cuerpo del paso */}
        <div className="p-6 max-h-[65vh] overflow-y-auto space-y-4 text-sm">
          {/* Paso 1: Contexto de Llegada */}
          {step === 1 && (
            <div className="space-y-4">
              <div>
                <label className="block text-xs font-semibold text-carbon mb-1">{t('intake.field_intake_window')}</label>
                <div className="grid grid-cols-3 gap-2">
                  {(['fija', 'movil', 'transaccional'] as const).map((wt) => (
                    <button
                      key={wt}
                      type="button"
                      onClick={() => setWindowType(wt)}
                      className={`p-2.5 text-xs font-medium rounded-lg border text-center capitalize transition-all ${
                        windowType === wt ? 'bg-claro border-turquesa text-carbon font-bold shadow-sm' : 'border-gray-200 hover:bg-gray-50'
                      }`}
                    >
                      Ventanilla {wt}
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
                    <p className="text-[11px] text-gray-500">
                      Si viaja con NNA u otros parientes, se podrán abrir subfolios vinculados (BV-3.2).
                    </p>
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
                  <label className="block text-xs font-medium text-gray-700 mb-1">{t('intake.field_given_name')}</label>
                  <input
                    type="text"
                    required
                    value={givenName}
                    onChange={(e) => setGivenName(e.target.value)}
                    placeholder="Ej. María Elena"
                    className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1">{t('intake.field_paternal_name')}</label>
                  <input
                    type="text"
                    required
                    value={paternalName}
                    onChange={(e) => setPaternalName(e.target.value)}
                    placeholder="Ej. González"
                    className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                  />
                </div>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1">{t('intake.field_maternal_name')}</label>
                  <input
                    type="text"
                    value={maternalName}
                    onChange={(e) => setMaternalName(e.target.value)}
                    placeholder="Opcional"
                    className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1">
                    {t('intake.field_preferred_name')} <span className="text-turquesa-dark font-semibold">(C1)</span>
                  </label>
                  <input
                    type="text"
                    value={preferredName}
                    onChange={(e) => setPreferredName(e.target.value)}
                    placeholder="Cómo pide que se le llame"
                    className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                  />
                </div>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1">{t('intake.field_birth_date')}</label>
                  <input
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
                    <span className="text-[11px]">{t('intake.field_birth_estimated')}</span>
                  </label>
                </div>

                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1">{t('intake.field_sex')}</label>
                  <select
                    value={sexId}
                    onChange={(e) => setSexId(Number(e.target.value))}
                    className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                  >
                    <option value={1}>1. Masculino</option>
                    <option value={2}>2. Femenino</option>
                    <option value={3}>3. Otro / No binario</option>
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1">{t('intake.field_nationality')}</label>
                  <select
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
                    <option value="Otro">Otro país</option>
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1">{t('intake.field_primary_language')}</label>
                  <input
                    type="text"
                    value={primaryLanguage}
                    onChange={(e) => setPrimaryLanguage(e.target.value)}
                    placeholder="Español, Creole, Maya..."
                    className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">{t('intake.field_phone')}</label>
                <input
                  type="text"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  placeholder="+504 9999 9999"
                  className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                />
              </div>
            </div>
          )}

          {/* Paso 3: Marcadores de Vulnerabilidad (13 marcadores de MAP-OIM v3) */}
          {step === 3 && (
            <div className="space-y-3">
              <div className="bg-claro/40 border border-turquesa/30 p-3 rounded-lg text-xs text-carbon">
                <p className="font-semibold text-turquesa-dark mb-0.5">Evaluación Objetiva Humanitaria (BV-2.5)</p>
                <p className="text-gray-600">
                  Seleccione las condiciones aplicables. Todo marcador queda firmado con tu identidad profesional y no puede ser asignado automáticamente por un algoritmo.
                </p>
              </div>

              <div className="grid grid-cols-1 gap-2">
                {(Object.keys(VULNERABILITY_CATALOG) as VulnerabilityMarkerCode[]).map((code) => {
                  const item = VULNERABILITY_CATALOG[code];
                  const isChecked = selectedVulnerabilities.includes(code);
                  return (
                    <label
                      key={code}
                      onClick={() => toggleVulnerability(code)}
                      className={`flex items-start space-x-3 p-3 rounded-xl border cursor-pointer transition-all ${
                        isChecked
                          ? 'bg-alerta-bg/40 border-alerta/40 text-carbon shadow-xs'
                          : 'bg-white border-gray-200 hover:bg-gray-50 text-gray-700'
                      }`}
                    >
                      <input
                        type="checkbox"
                        checked={isChecked}
                        onChange={() => {}}
                        className="mt-0.5 w-4 h-4 text-alerta rounded border-gray-300"
                      />
                      <div className="flex-1 text-xs">
                        <span className="font-bold block text-carbon">{item.label}</span>
                        <span className="text-[11px] text-gray-500">{item.description}</span>
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
                  <h4 className="font-bold text-green-900">Listo para apertura formal</h4>
                  <p className="text-green-700 mt-0.5">
                    Al confirmar, el sistema generará un folio correlativo único e inicializará automáticamente los 5 ejes de estatus (Regla Dura 7 y BV-2.2).
                  </p>
                </div>
              </div>

              <div className="p-4 bg-gray-50 rounded-xl border border-gray-200 text-xs space-y-2">
                <div className="flex justify-between border-b pb-2">
                  <span className="text-gray-500">Persona:</span>
                  <span className="font-bold text-carbon">{givenName} {paternalName} {maternalName}</span>
                </div>
                <div className="flex justify-between border-b pb-2">
                  <span className="text-gray-500">Nombre Preferido:</span>
                  <span className="font-semibold text-turquesa-dark">{preferredName || givenName}</span>
                </div>
                <div className="flex justify-between border-b pb-2">
                  <span className="text-gray-500">Nacionalidad:</span>
                  <span className="font-semibold text-carbon">{nationalityCountry}</span>
                </div>
                <div className="flex justify-between border-b pb-2">
                  <span className="text-gray-500">Vulnerabilidades marcadas:</span>
                  <span className="font-bold text-alerta">{selectedVulnerabilities.length} seleccionadas</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-500">Oficial de Ingreso:</span>
                  <span className="font-semibold text-carbon">{authorFullName}</span>
                </div>
              </div>
            </div>
          )}
        </div>

        {/* Botones de navegación del modal */}
        <div className="px-6 py-4 bg-gray-50 border-t border-gray-200 flex justify-between items-center text-xs">
          {step > 1 ? (
            <button
              type="button"
              onClick={() => setStep((s) => (s - 1) as any)}
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
              disabled={step === 2 && (!givenName.trim() || !paternalName.trim())}
              onClick={() => setStep((s) => (s + 1) as any)}
              className="px-4 py-2 font-semibold text-carbon bg-turquesa hover:bg-turquesa-hover rounded-lg shadow-sm disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {t('intake.btn_next')}
            </button>
          ) : (
            <button
              type="button"
              onClick={handleFinish}
              className="px-5 py-2 font-bold text-white bg-carbon hover:bg-black rounded-lg shadow-md flex items-center gap-1.5"
            >
              <HeartHandshake className="w-4 h-4 text-turquesa" />
              {t('intake.btn_create_case')}
            </button>
          )}
        </div>
      </div>
    </div>
  );
};
