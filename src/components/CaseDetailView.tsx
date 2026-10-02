import React, { useState } from 'react';
import { 
  ArrowLeft, 
  ShieldAlert, 
  Clock, 
  AlertCircle, 
  Layers, 
  FileText, 
  Users, 
  ChevronRight,
  Send,
  Lock
} from 'lucide-react';
import { t } from '../lib/i18n';
import { 
  CaseWithDetails, 
  RoleName, 
  StatusAxisCode 
} from '../types/database';
import { 
  DEMO_STATUS_AXES, 
  DEMO_STATUS_VALUES, 
  VULNERABILITY_CATALOG 
} from '../lib/mockData';

interface CaseDetailViewProps {
  caseData: CaseWithDetails;
  onBack: () => void;
  activeRole: RoleName;
  assignedAreaCode?: string;
  onTransitionStatus: (
    caseId: string, 
    axisCode: StatusAxisCode, 
    newValueCode: string, 
    reason: string
  ) => void;
  onSelectSubfolio?: (subfolioCase: CaseWithDetails) => void;
}

export const CaseDetailView: React.FC<CaseDetailViewProps> = ({
  caseData,
  onBack,
  activeRole,
  assignedAreaCode,
  onTransitionStatus,
  onSelectSubfolio,
}) => {
  const [activeTab, setActiveTab] = useState<'axes' | 'summary' | 'vulnerabilities' | 'subfolios'>('axes');
  const [transitioningAxis, setTransitioningAxis] = useState<StatusAxisCode | null>(null);
  const [targetValueCode, setTargetValueCode] = useState<string>('');
  const [transitionReason, setTransitionReason] = useState<string>('');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const hasUnaccompaniedChild = caseData.vulnerabilities.some(
    (v) => v.marker_code === 'unaccompanied_child'
  );

  const isDirector = activeRole === 'director';
  const isLegalCaseworker = activeRole === 'caseworker' && assignedAreaCode === 'legal';

  const handleOpenTransition = (axisCode: StatusAxisCode) => {
    setTransitioningAxis(axisCode);
    setErrorMessage(null);
    setTransitionReason('');
    const possibleValues = DEMO_STATUS_VALUES[axisCode] || [];
    const firstNonCurrent = possibleValues.find(v => v.code !== caseData.statuses[axisCode]?.valueCode);
    setTargetValueCode(firstNonCurrent ? firstNonCurrent.code : (possibleValues[0]?.code || ''));
  };

  const handleConfirmTransition = () => {
    if (!transitioningAxis || !targetValueCode) return;

    if (!transitionReason.trim()) {
      setErrorMessage(t('cases.err_reason_required'));
      return;
    }

    // Regla de gobernanza: legal_status solo director o caseworker de legal
    if (transitioningAxis === 'legal_status' && !isDirector && !isLegalCaseworker) {
      setErrorMessage(t('cases.err_legal_restricted'));
      return;
    }

    // Regla de gobernanza: record_status a closed solo director
    if (transitioningAxis === 'record_status' && targetValueCode === 'closed' && !isDirector) {
      setErrorMessage(t('cases.err_closed_restricted'));
      return;
    }

    onTransitionStatus(caseData.id, transitioningAxis, targetValueCode, transitionReason.trim());
    setTransitioningAxis(null);
    setTransitionReason('');
    setErrorMessage(null);
  };

  return (
    <div className="space-y-6">
      {/* Botón Volver y Cabecera de Expediente */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-white p-6 rounded-2xl border border-gray-200 shadow-sm">
        <div>
          <button
            onClick={onBack}
            className="flex items-center text-xs font-semibold text-gray-500 hover:text-carbon transition-colors mb-3"
          >
            <ArrowLeft className="w-4 h-4 mr-1" />
            {t('cases.back_to_list')}
          </button>

          <div className="flex flex-wrap items-center gap-3">
            <h2 className="text-2xl font-mono font-extrabold text-carbon">
              {caseData.case_number}
            </h2>
            <span className="bg-claro text-turquesa-dark border border-turquesa/30 px-3 py-1 rounded-full text-xs font-bold">
              {caseData.statuses.engagement_status?.label || 'En atención'}
            </span>
            {caseData.parent_case_id && (
              <span className="bg-purple-100 text-purple-800 px-2.5 py-0.5 rounded-full text-xs font-medium">
                {t('cases.badge_subfolio')}
              </span>
            )}
            {caseData.previous_case_id && (
              <span className="bg-blue-100 text-blue-800 px-2.5 py-0.5 rounded-full text-xs font-medium">
                {t('cases.badge_reentry')}
              </span>
            )}
          </div>

          <div className="mt-2 text-sm text-gray-600 flex flex-wrap items-center gap-2">
            <span className="font-bold text-carbon">
              {caseData.person.given_name} {caseData.person.paternal_family_name}
            </span>
            {caseData.person.preferred_name && (
              <span className="text-turquesa-dark italic">
                ("{caseData.person.preferred_name}")
              </span>
            )}
            <span>·</span>
            <span>{caseData.person.other_nationality || 'Honduras'}</span>
            <span>·</span>
            <span>Apertura: {caseData.opened_at.substring(0, 10)}</span>
          </div>
        </div>

        <div className="flex items-center gap-2">
          {caseData.parentCaseNumber && (
            <div className="text-xs bg-gray-50 p-2.5 rounded-xl border border-gray-200">
              <span className="text-gray-400 block">{t('cases.subfolio_of')}</span>
              <span className="font-mono font-bold text-carbon">{caseData.parentCaseNumber}</span>
            </div>
          )}
        </div>
      </div>

      {/* Alerta de Niñez No Acompañada */}
      {hasUnaccompaniedChild && (
        <div className="bg-alerta-bg border border-alerta/30 rounded-2xl p-4 flex items-start gap-3 text-alerta">
          <ShieldAlert className="w-5 h-5 flex-shrink-0 mt-0.5" />
          <div className="text-xs">
            <h4 className="font-bold">{t('cases.badge_unaccompanied')}</h4>
            <p className="mt-0.5 text-carbon-muted">{t('cases.unaccompanied_notice')}</p>
          </div>
        </div>
      )}

      {/* Pestañas del Expediente */}
      <div className="flex space-x-2 border-b border-gray-200">
        <button
          onClick={() => setActiveTab('axes')}
          className={`pb-3 px-4 text-xs font-bold border-b-2 flex items-center gap-2 ${
            activeTab === 'axes'
              ? 'border-turquesa text-carbon'
              : 'border-transparent text-gray-500 hover:text-carbon'
          }`}
        >
          <Layers className="w-4 h-4" />
          {t('cases.tab_axes')}
        </button>
        <button
          onClick={() => setActiveTab('summary')}
          className={`pb-3 px-4 text-xs font-bold border-b-2 flex items-center gap-2 ${
            activeTab === 'summary'
              ? 'border-turquesa text-carbon'
              : 'border-transparent text-gray-500 hover:text-carbon'
          }`}
        >
          <FileText className="w-4 h-4" />
          {t('cases.tab_summary')}
        </button>
        <button
          onClick={() => setActiveTab('vulnerabilities')}
          className={`pb-3 px-4 text-xs font-bold border-b-2 flex items-center gap-2 ${
            activeTab === 'vulnerabilities'
              ? 'border-turquesa text-carbon'
              : 'border-transparent text-gray-500 hover:text-carbon'
          }`}
        >
          <AlertCircle className="w-4 h-4" />
          {t('cases.tab_vulnerabilities')} ({caseData.vulnerabilities.length})
        </button>
        {caseData.subfolios && caseData.subfolios.length > 0 && (
          <button
            onClick={() => setActiveTab('subfolios')}
            className={`pb-3 px-4 text-xs font-bold border-b-2 flex items-center gap-2 ${
              activeTab === 'subfolios'
                ? 'border-turquesa text-carbon'
                : 'border-transparent text-gray-500 hover:text-carbon'
            }`}
          >
            <Users className="w-4 h-4" />
            {t('cases.tab_subfolios')} ({caseData.subfolios.length})
          </button>
        )}
      </div>

      {/* Tab 1: Los 5 Ejes de Estatus (Regla Dura 7 / ME-02) */}
      {activeTab === 'axes' && (
        <div className="space-y-4">
          <div className="bg-claro/30 p-4 rounded-xl border border-turquesa/30 text-xs text-carbon">
            <h3 className="font-bold text-turquesa-dark mb-1">{t('cases.axes_section_title')}</h3>
            <p className="text-gray-600">
              {t('cases.change_modal_notice')}
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {DEMO_STATUS_AXES.map((axis) => {
              const current = caseData.statuses[axis.code];
              const isPrimary = axis.is_primary;
              const isLegal = axis.code === 'legal_status';

              return (
                <div
                  key={axis.id}
                  className={`bg-white rounded-2xl p-5 border shadow-xs flex flex-col justify-between ${
                    isPrimary ? 'border-turquesa ring-1 ring-turquesa/20' : 'border-gray-200'
                  }`}
                >
                  <div>
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center space-x-2">
                        <span className="text-xs font-semibold text-gray-500 uppercase tracking-wider">
                          {axis.label_es}
                        </span>
                        {isPrimary && (
                          <span className="bg-turquesa/20 text-turquesa-dark text-[10px] font-bold px-2 py-0.5 rounded-full">
                            Estatus Prioritario
                          </span>
                        )}
                      </div>
                      {isLegal && (
                        <span className="text-[10px] text-gray-400 font-mono flex items-center gap-1">
                          <Lock className="w-3 h-3" /> Área Jurídica
                        </span>
                      )}
                    </div>

                    <div className="my-3">
                      <span className="text-base font-bold text-carbon block">
                        {current?.label || 'Sin asignar'}
                      </span>
                      <p className="text-xs text-gray-500 font-mono mt-1">
                        Código: <code>{current?.valueCode}</code>
                      </p>
                    </div>

                    <div className="bg-gray-50 p-3 rounded-xl border border-gray-100 text-xs space-y-1 mb-4">
                      <div className="flex items-center text-gray-500 text-[11px] gap-1">
                        <Clock className="w-3.5 h-3.5 text-gray-400" />
                        <span>Vigente desde: {current?.valid_from.substring(0, 10)}</span>
                      </div>
                      <p className="text-gray-700 italic text-[11px] mt-1">
                        "{current?.reason || 'Apertura de caso'}"
                      </p>
                    </div>
                  </div>

                  <button
                    onClick={() => handleOpenTransition(axis.code)}
                    className="w-full text-xs font-semibold py-2 px-3 border border-gray-300 rounded-lg hover:bg-gray-50 text-carbon transition-colors flex items-center justify-center gap-1.5"
                  >
                    <span>{t('cases.btn_change_status')}</span>
                    <ChevronRight className="w-3.5 h-3.5" />
                  </button>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Tab 2: Ficha Sociodemográfica MAP-OIM v3 */}
      {activeTab === 'summary' && (
        <div className="bg-white rounded-2xl border border-gray-200 p-6 shadow-sm space-y-6">
          <h3 className="text-base font-bold text-carbon border-b pb-3">
            Ficha de Identificación MAP-OIM v3 (Fase 1 y 2)
          </h3>

          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4 text-xs">
            <div>
              <span className="text-gray-400 block font-medium">Nombre Completo:</span>
              <span className="font-bold text-carbon text-sm">
                {caseData.person.given_name} {caseData.person.paternal_family_name} {caseData.person.maternal_family_name || ''}
              </span>
            </div>
            <div>
              <span className="text-gray-400 block font-medium">Nombre Preferido (Compromiso C1):</span>
              <span className="font-semibold text-turquesa-dark text-sm">
                {caseData.person.preferred_name || 'No especificado'}
              </span>
            </div>
            <div>
              <span className="text-gray-400 block font-medium">Fecha de Nacimiento:</span>
              <span className="font-semibold text-carbon">
                {caseData.person.birth_date} {caseData.person.birth_date_is_estimated && '(Estimada)'}
              </span>
            </div>
            <div>
              <span className="text-gray-400 block font-medium">Nacionalidad:</span>
              <span className="font-semibold text-carbon">{caseData.person.other_nationality || 'Honduras'}</span>
            </div>
            <div>
              <span className="text-gray-400 block font-medium">Idioma Principal:</span>
              <span className="font-semibold text-carbon">{caseData.person.other_language || 'Español'}</span>
            </div>
            <div>
              <span className="text-gray-400 block font-medium">Teléfono de Contacto:</span>
              <span className="font-mono text-carbon">{caseData.person.phone_number || 'Sin teléfono'}</span>
            </div>
            <div>
              <span className="text-gray-400 block font-medium">Vía de Ingreso a México:</span>
              <span className="font-semibold text-carbon">Terrestre (Frontera Sur)</span>
            </div>
            <div>
              <span className="text-gray-400 block font-medium">Tipo de Ventanilla:</span>
              <span className="font-semibold text-carbon capitalize">{caseData.intake_window_type}</span>
            </div>
            <div>
              <span className="text-gray-400 block font-medium">Núcleo Familiar:</span>
              <span className="font-semibold text-carbon">
                {caseData.travels_with_family ? 'Viaja con familia' : 'Viaja solo'}
              </span>
            </div>
          </div>
        </div>
      )}

      {/* Tab 3: Marcadores de Vulnerabilidad */}
      {activeTab === 'vulnerabilities' && (
        <div className="bg-white rounded-2xl border border-gray-200 p-6 shadow-sm space-y-4">
          <div className="flex justify-between items-center border-b pb-3">
            <div>
              <h3 className="text-base font-bold text-carbon">Marcadores de Vulnerabilidad Objetivos</h3>
              <p className="text-xs text-gray-500">Afirmados profesionalmente en ventanilla (13 marcadores de MAP-OIM v3)</p>
            </div>
            <span className="bg-alerta-bg text-alerta px-2.5 py-1 rounded-full font-bold text-xs">
              {caseData.vulnerabilities.length} activos
            </span>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {caseData.vulnerabilities.map((v) => {
              const info = VULNERABILITY_CATALOG[v.marker_code];
              return (
                <div key={v.id} className="p-4 rounded-xl border border-gray-200 bg-gray-50/50 space-y-2 text-xs">
                  <div className="flex items-center space-x-2">
                    <span className="w-2.5 h-2.5 rounded-full bg-alerta flex-shrink-0" />
                    <span className="font-bold text-carbon text-sm">{info?.label || v.marker_code}</span>
                  </div>
                  <p className="text-gray-600 text-xs leading-relaxed">{v.notes || info?.description}</p>
                  <div className="pt-2 border-t border-gray-100 flex justify-between text-[11px] text-gray-400">
                    <span>Afirmado por: {v.affirmed_by}</span>
                    <span>{v.affirmed_at.substring(0, 10)}</span>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Tab 4: Subfolios Vinculados */}
      {activeTab === 'subfolios' && caseData.subfolios && (
        <div className="bg-white rounded-2xl border border-gray-200 p-6 shadow-sm space-y-4">
          <h3 className="text-base font-bold text-carbon border-b pb-3">
            Subfolios de Infancias Acompañadas (BV-3.2)
          </h3>
          <div className="divide-y divide-gray-100">
            {caseData.subfolios.map((sub) => (
              <div key={sub.id} className="py-4 flex items-center justify-between">
                <div>
                  <div className="flex items-center space-x-2">
                    <span className="font-mono font-bold text-carbon">{sub.case_number}</span>
                    <span className="bg-purple-100 text-purple-800 text-[10px] font-semibold px-2 py-0.5 rounded-full">
                      Subfolio NNA
                    </span>
                  </div>
                  <p className="text-xs text-gray-600 font-semibold mt-1">
                    {sub.person.given_name} {sub.person.paternal_family_name}
                  </p>
                </div>
                {onSelectSubfolio && (
                  <button
                    onClick={() => onSelectSubfolio(sub)}
                    className="text-xs font-semibold text-turquesa-dark hover:underline flex items-center gap-1"
                  >
                    <span>Ver Subfolio</span>
                    <ChevronRight className="w-3.5 h-3.5" />
                  </button>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Modal de Transición de Estatus (Regla Dura 7) */}
      {transitioningAxis && (
        <div className="fixed inset-0 z-50 bg-black/50 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl shadow-xl border border-gray-200 w-full max-w-lg overflow-hidden">
            <div className="px-6 py-4 bg-carbon text-white flex justify-between items-center">
              <div>
                <h3 className="text-sm font-bold">{t('cases.change_modal_title')}</h3>
                <p className="text-xs text-turquesa-light font-mono capitalize">
                  {DEMO_STATUS_AXES.find((a) => a.code === transitioningAxis)?.label_es}
                </p>
              </div>
              <button
                onClick={() => setTransitioningAxis(null)}
                className="text-gray-400 hover:text-white p-1"
              >
                ✕
              </button>
            </div>

            <div className="p-6 space-y-4 text-xs">
              {errorMessage && (
                <div className="p-3 bg-alerta-bg border border-alerta/30 text-alerta rounded-xl text-xs flex items-start gap-2">
                  <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" />
                  <span>{errorMessage}</span>
                </div>
              )}

              <div>
                <label className="block font-semibold text-carbon mb-1">
                  {t('cases.field_target_status')}
                </label>
                <select
                  value={targetValueCode}
                  onChange={(e) => setTargetValueCode(e.target.value)}
                  className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                >
                  {(DEMO_STATUS_VALUES[transitioningAxis] || []).map((val) => (
                    <option key={val.code} value={val.code}>
                      {val.label_es} ({val.code})
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block font-semibold text-carbon mb-1">
                  {t('cases.field_reason')}
                </label>
                <textarea
                  rows={3}
                  required
                  value={transitionReason}
                  onChange={(e) => setTransitionReason(e.target.value)}
                  placeholder={t('cases.field_reason_placeholder')}
                  className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                />
              </div>

              <div className="p-3 bg-gray-50 rounded-xl border border-gray-200 text-[11px] text-gray-500 space-y-1">
                <p className="font-semibold text-carbon">Regla Dura 7 de Supabase:</p>
                <p>
                  Esta acción cerrará el registro anterior con marca de tiempo actual y abrirá el nuevo estado de manera transaccional. No es posible sobrescribir ni revertir sin dejar un nuevo rastro auditable.
                </p>
              </div>
            </div>

            <div className="px-6 py-4 bg-gray-50 border-t border-gray-200 flex justify-end gap-2 text-xs">
              <button
                type="button"
                onClick={() => setTransitioningAxis(null)}
                className="px-4 py-2 font-medium text-gray-600 hover:bg-gray-100 rounded-lg"
              >
                {t('cases.btn_cancel')}
              </button>
              <button
                type="button"
                onClick={handleConfirmTransition}
                className="px-4 py-2 font-bold text-carbon bg-turquesa hover:bg-turquesa-hover rounded-lg shadow-sm flex items-center gap-1.5"
              >
                <Send className="w-3.5 h-3.5" />
                {t('cases.btn_confirm_transition')}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
