import React, { useEffect, useState } from 'react';
import { X, Printer, Copy, Check, FileText, ShieldAlert } from 'lucide-react';
import { t } from '../lib/i18n';
import { CaseWithDetails } from '../types/database';
import { useCatalog } from '../lib/catalog';
import { api } from '../lib/data';
import { formatDate } from '../lib/format';
import { ModalShell } from './ModalShell';

interface ArcoAccessExtractModalProps {
  isOpen: boolean;
  onClose: () => void;
  caseData: CaseWithDetails;
}

export const ArcoAccessExtractModal: React.FC<ArcoAccessExtractModalProps> = ({
  isOpen,
  onClose,
  caseData,
}) => {
  const [copied, setCopied] = useState(false);
  const { organizationName, organizationInfo } = useCatalog();
  const [serverExtract, setServerExtract] = useState<Record<string, unknown> | null>(null);
  const [extractError, setExtractError] = useState<string | null>(null);

  // El extracto formal lo emite la base (sólo dirección, sin notas de trabajo protegidas)
  // y deja el evento de auditoría ARCO_ACCESS_EXTRACT_ISSUED (BV-5.2, Ethos E-02).
  useEffect(() => {
    if (!isOpen) return;
    let cancelled = false;
    setServerExtract(null);
    setExtractError(null);
    api
      .generateArcoAccessExtract(caseData.person.id)
      .then((r) => { if (!cancelled) setServerExtract(r); })
      .catch((e) => { if (!cancelled) setExtractError(e instanceof Error ? e.message : String(e)); });
    return () => { cancelled = true; };
  }, [isOpen, caseData.person.id]);

  if (!isOpen) return null;

  // Filtrado ético estricto por Ethos E-02 / MD-04: Excluir is_work_note = true
  const accessibleEntries = (caseData.journal_entries || []).filter(
    (entry) => !entry.is_work_note
  );

  const extractData = {
    institution: organizationName,
    emitted_at: new Date().toISOString(),
    titular_person: {
      given_name: caseData.person.given_name,
      paternal_family_name: caseData.person.paternal_family_name,
      maternal_family_name: caseData.person.maternal_family_name,
      preferred_name: caseData.person.preferred_name,
      birth_date: caseData.person.birth_date,
      birth_date_is_estimated: caseData.person.birth_date_is_estimated,
      phone_number: caseData.person.phone_number,
      email: caseData.person.email,
      is_anonymized: caseData.person.is_anonymized,
    },
    cases: [
      {
        case_number: caseData.case_number,
        opened_at: caseData.opened_at,
        travels_with_family: caseData.travels_with_family,
        statuses: caseData.statuses,
      },
    ],
    journal_interventions_count: accessibleEntries.length,
    journal_interventions: accessibleEntries.map((e) => ({
      occurred_at: e.occurred_at,
      area_name: e.area_name || e.area_code,
      entry_type: e.entry_type_key,
      body: e.body,
    })),
    consents: caseData.consents || [],
  };

  const handleCopyJson = () => {
    navigator.clipboard.writeText(JSON.stringify(serverExtract ?? extractData, null, 2));
    setCopied(true);
    setTimeout(() => setCopied(false), 2500);
  };

  const handlePrint = () => {
    window.print();
  };

  return (
    <ModalShell onClose={onClose} className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 overflow-y-auto">
      <div className="bg-white rounded-xl shadow-2xl max-w-3xl w-full max-h-[90vh] flex flex-col overflow-hidden border border-gray-100 animate-in fade-in zoom-in-95 duration-200">
        {/* Encabezado */}
        <div className="bg-carbon px-6 py-4 flex items-center justify-between text-white border-b border-carbon-muted/20 shrink-0">
          <div className="flex items-center gap-2">
            <FileText className="w-5 h-5 text-turquesa-dark" />
            <div>
              <h3 className="text-sm font-bold tracking-wide">
                {t('arco.modal_access.title')}
              </h3>
              <p className="text-xs text-gray-300">
                {caseData.case_number} — {caseData.person.given_name} {caseData.person.paternal_family_name}
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="text-gray-500 hover:text-white p-1 rounded transition"
           aria-label={t('common.close')}>
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Contenido imprimible */}
        <div className="p-6 overflow-y-auto space-y-6 text-carbon print:p-0">
          {extractError && (
            <div role="alert" className="rounded-lg border border-alerta/20 bg-alerta-bg p-3 text-xs text-alerta-dark">
              {extractError}
            </div>
          )}
          {/* Cabecera institucional */}
          <div className="border-b border-gray-200 pb-4 flex justify-between items-start">
            <div>
              <span className="text-xs uppercase font-bold tracking-wider text-turquesa-dark">
                {t('arco.modal_access.org_custodian')}
              </span>
              <h2 className="text-base font-bold text-carbon">{organizationName}</h2>
              <p className="text-xs text-gray-500">{t('arco.modal_access.official_extract')}</p>
              {(organizationInfo.responsibleName || organizationInfo.responsibleAddress || organizationInfo.arcoContact) && (
                <p className="mt-1 text-xs text-gray-600">
                  {[organizationInfo.responsibleName, organizationInfo.responsibleAddress, organizationInfo.arcoContact].filter(Boolean).join(' · ')}
                </p>
              )}
            </div>
            <div className="text-right text-xs text-gray-500">
              <span>{new Date().toLocaleDateString('es-MX', { year: 'numeric', month: 'long', day: 'numeric' })}</span>
            </div>
          </div>

          {/* Salvaguarda ética Ethos E-02 / MD-04 */}
          <div className="p-3 bg-amber-50 border border-amber-200 rounded-lg flex items-start gap-2.5 text-xs text-amber-900">
            <ShieldAlert className="w-4 h-4 text-amber-600 shrink-0 mt-0.5" />
            <p className="leading-relaxed">
              {t('arco.modal_access.work_note_disclaimer')}
            </p>
          </div>

          {/* Ficha de Persona */}
          <div className="space-y-2">
            <h4 className="text-xs font-bold uppercase tracking-wider text-gray-500 border-b pb-1">
              {t('arco.modal_access.person_header')}
            </h4>
            <div className="grid grid-cols-2 md:grid-cols-3 gap-3 text-xs bg-gray-50 p-3 rounded-lg">
              <div>
                <span className="text-gray-500 block text-xs">{t('arco.extract.full_name')}</span>
                <span className="font-semibold">
                  {caseData.person.given_name} {caseData.person.paternal_family_name} {caseData.person.maternal_family_name || ''}
                </span>
              </div>
              {caseData.person.preferred_name && (
                <div>
                  <span className="text-gray-500 block text-xs">{t('arco.extract.preferred')}</span>
                  <span>{caseData.person.preferred_name}</span>
                </div>
              )}
              <div>
                <span className="text-gray-500 block text-xs">{t('arco.extract.birth')}</span>
                <span>
                  {formatDate(caseData.person.birth_date)} {caseData.person.birth_date_is_estimated && '(Aproximada)'}
                </span>
              </div>
              {caseData.person.phone_number && (
                <div>
                  <span className="text-gray-500 block text-xs">Teléfono:</span>
                  <span>{caseData.person.phone_number}</span>
                </div>
              )}
              {caseData.person.email && (
                <div>
                  <span className="text-gray-500 block text-xs">Correo:</span>
                  <span>{caseData.person.email}</span>
                </div>
              )}
            </div>
          </div>

          {/* Expedientes y Estatus */}
          <div className="space-y-2">
            <h4 className="text-xs font-bold uppercase tracking-wider text-gray-500 border-b pb-1">
              {t('arco.modal_access.cases_header')}
            </h4>
            <div className="border border-gray-200 rounded-lg p-3 space-y-2 text-xs">
              <div className="flex justify-between items-center">
                <span className="font-mono font-bold text-turquesa-dark">{caseData.case_number}</span>
                <span className="text-gray-500 text-xs">Apertura: {formatDate(caseData.opened_at)}</span>
              </div>
              <div className="grid grid-cols-2 md:grid-cols-3 gap-2 pt-2 border-t text-xs">
                <div>
                  <span className="text-gray-500 block">{t('arco.extract.engagement')}</span>
                  <span className="font-semibold">{caseData.statuses.engagement_status.label}</span>
                </div>
                <div>
                  <span className="text-gray-500 block">{t('arco.extract.legal')}</span>
                  <span className="font-semibold">{caseData.statuses.legal_status.label}</span>
                </div>
                <div>
                  <span className="text-gray-500 block">{t('arco.extract.shelter')}</span>
                  <span className="font-semibold">{caseData.statuses.shelter_status.label}</span>
                </div>
              </div>
            </div>
          </div>

          {/* Bitácora de Intervenciones Públicas/Compartidas (Excluye notas de trabajo) */}
          <div className="space-y-2">
            <div className="flex justify-between items-center border-b pb-1">
              <h4 className="text-xs font-bold uppercase tracking-wider text-gray-500">
                {t('arco.modal_access.journal_header')}
              </h4>
              <span className="text-xs text-gray-500">
                ({accessibleEntries.length} hechos registrados)
              </span>
            </div>

            {accessibleEntries.length === 0 ? (
              <p className="text-xs text-gray-500 italic py-2">
                {t('arco.modal_access.no_entries')}
              </p>
            ) : (
              <div className="space-y-3">
                {accessibleEntries.map((entry) => (
                  <div
                    key={entry.id}
                    className="p-3 rounded-lg border border-gray-200 bg-white text-xs space-y-1.5"
                  >
                    <div className="flex justify-between items-center text-xs text-gray-500">
                      <span className="font-semibold text-carbon">
                        {entry.area_name || entry.area_code || 'Área Operativa'}
                      </span>
                      <span>
                        {new Date(entry.occurred_at).toLocaleString('es-MX', {
                          dateStyle: 'medium',
                          timeStyle: 'short',
                        })}
                      </span>
                    </div>
                    <p className="text-gray-700 leading-relaxed">{entry.body}</p>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Consentimientos */}
          {caseData.consents && caseData.consents.length > 0 && (
            <div className="space-y-2">
              <h4 className="text-xs font-bold uppercase tracking-wider text-gray-500 border-b pb-1">
                {t('arco.modal_access.consents_header')}
              </h4>
              <div className="space-y-1.5 text-xs">
                {caseData.consents.map((c) => (
                  <div key={c.id} className="flex justify-between items-center p-2 rounded bg-gray-50">
                    <span className="font-medium text-carbon">
                      {t(`arco.consent_types.${c.consent_type}`)}
                    </span>
                    <span className="text-xs px-2 py-0.5 rounded bg-emerald-100 text-emerald-800 font-semibold">
                      {t(`arco.consent_status.${c.status}`)}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Barra de Acciones */}
        <div className="bg-gray-50 px-6 py-3 border-t border-gray-200 flex justify-between items-center shrink-0">
          <div className="flex items-center gap-2">
            <button
              onClick={handlePrint}
              className="px-3 py-1.5 text-xs font-semibold rounded border border-gray-300 bg-white text-carbon hover:bg-gray-100 transition flex items-center gap-1.5 shadow-sm"
            >
              <Printer className="w-3.5 h-3.5" />
              <span>{t('arco.modal_access.btn_print')}</span>
            </button>
            <button
              onClick={handleCopyJson}
              className="px-3 py-1.5 text-xs font-semibold rounded border border-gray-300 bg-white text-carbon hover:bg-gray-100 transition flex items-center gap-1.5 shadow-sm"
            >
              {copied ? <Check className="w-3.5 h-3.5 text-emerald-600" /> : <Copy className="w-3.5 h-3.5" />}
              <span>{copied ? t('arco.modal_access.copied_notice') : t('arco.modal_access.btn_copy_json')}</span>
            </button>
          </div>

          <button
            onClick={onClose}
            className="px-4 py-1.5 text-xs font-semibold rounded bg-carbon text-white hover:bg-carbon-muted transition"
          >
            {t('arco.modal_access.btn_close')}
          </button>
        </div>
      </div>
    </ModalShell>
  );
};
