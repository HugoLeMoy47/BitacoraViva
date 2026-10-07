import React, { useState } from 'react';
import { X, ShieldCheck, FileCheck } from 'lucide-react';
import { t } from '../lib/i18n';
import { CaseWithDetails, ConsentType, ConsentStatus } from '../types/database';

interface ConsentModalProps {
  isOpen: boolean;
  onClose: () => void;
  caseData: CaseWithDetails;
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

export const ConsentModal: React.FC<ConsentModalProps> = ({
  isOpen,
  onClose,
  caseData,
  onSaveConsent,
}) => {
  const [consentType, setConsentType] = useState<ConsentType>('sensitive_data');
  const [status, setStatus] = useState<ConsentStatus>('granted');
  const [isMinorAssent, setIsMinorAssent] = useState(false);
  const [guardianName, setGuardianName] = useState('');
  const [guardianRole, setGuardianRole] = useState('');
  const [authorityRef, setAuthorityRef] = useState('');
  const [notes, setNotes] = useState('');

  if (!isOpen) return null;

  const handleSubmit = (e: React.FormEvent) => {
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
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 overflow-y-auto">
      <div className="bg-white rounded-xl shadow-2xl max-w-xl w-full overflow-hidden border border-gray-100 animate-in fade-in zoom-in-95 duration-200">
        {/* Encabezado */}
        <div className="bg-carbon px-6 py-4 flex items-center justify-between text-white border-b border-carbon-muted/20">
          <div className="flex items-center gap-2">
            <ShieldCheck className="w-5 h-5 text-turquesa" />
            <div>
              <h3 className="text-sm font-bold tracking-wide">
                {t('arco.modal_consent.title')}
              </h3>
              <p className="text-[11px] text-gray-300">
                {caseData.case_number} — {caseData.person.given_name} {caseData.person.paternal_family_name}
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-white p-1 rounded transition"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Formulario */}
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <p className="text-xs text-gray-600">
            {t('arco.modal_consent.subtitle')}
          </p>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-semibold text-carbon mb-1">
                {t('arco.modal_consent.type_label')}
              </label>
              <select
                value={consentType}
                onChange={(e) => setConsentType(e.target.value as ConsentType)}
                className="w-full text-xs rounded-lg border-gray-300 border p-2 focus:ring-1 focus:ring-turquesa focus:outline-none"
              >
                <option value="general_care">{t('arco.consent_types.general_care')}</option>
                <option value="sensitive_data">{t('arco.consent_types.sensitive_data')}</option>
                <option value="secondary_use_research">{t('arco.consent_types.secondary_use_research')}</option>
              </select>
            </div>

            <div>
              <label className="block text-xs font-semibold text-carbon mb-1">
                {t('arco.modal_consent.status_label')}
              </label>
              <select
                value={status}
                onChange={(e) => setStatus(e.target.value as ConsentStatus)}
                className="w-full text-xs rounded-lg border-gray-300 border p-2 focus:ring-1 focus:ring-turquesa focus:outline-none"
              >
                <option value="granted">{t('arco.consent_status.granted')}</option>
                <option value="revoked">{t('arco.consent_status.revoked')}</option>
                <option value="opposed">{t('arco.consent_status.opposed')}</option>
              </select>
            </div>
          </div>

          {/* Salvaguarda para NNA */}
          <div className="p-3 bg-amber-50 rounded-lg border border-amber-200 text-xs text-amber-900 space-y-3">
            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                id="minor_assent"
                checked={isMinorAssent}
                onChange={(e) => setIsMinorAssent(e.target.checked)}
                className="rounded border-amber-300 text-turquesa focus:ring-turquesa"
              />
              <label htmlFor="minor_assent" className="font-semibold cursor-pointer">
                {t('arco.modal_consent.is_minor_assent')}
              </label>
            </div>

            {isMinorAssent && (
              <div className="space-y-2 pt-2 border-t border-amber-200">
                <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
                  <div>
                    <label className="block text-[11px] font-medium text-amber-800 mb-0.5">
                      {t('arco.modal_consent.guardian_name')}
                    </label>
                    <input
                      type="text"
                      value={guardianName}
                      onChange={(e) => setGuardianName(e.target.value)}
                      placeholder="Ej. Lic. Sofía Calderón"
                      className="w-full text-xs rounded border border-amber-300 p-1.5 bg-white focus:outline-none focus:ring-1 focus:ring-turquesa"
                    />
                  </div>
                  <div>
                    <label className="block text-[11px] font-medium text-amber-800 mb-0.5">
                      {t('arco.modal_consent.guardian_role')}
                    </label>
                    <input
                      type="text"
                      value={guardianRole}
                      onChange={(e) => setGuardianRole(e.target.value)}
                      placeholder="Ej. Procuraduría de Protección NNA"
                      className="w-full text-xs rounded border border-amber-300 p-1.5 bg-white focus:outline-none focus:ring-1 focus:ring-turquesa"
                    />
                  </div>
                </div>

                <div>
                  <label className="block text-[11px] font-medium text-amber-800 mb-0.5">
                    {t('arco.modal_consent.authority_letter')}
                  </label>
                  <input
                    type="text"
                    value={authorityRef}
                    onChange={(e) => setAuthorityRef(e.target.value)}
                    placeholder="Ej. DIF/PPNNA/2026/0491"
                    className="w-full text-xs rounded border border-amber-300 p-1.5 bg-white focus:outline-none focus:ring-1 focus:ring-turquesa"
                  />
                </div>
              </div>
            )}
          </div>

          <div>
            <label className="block text-xs font-semibold text-carbon mb-1">
              {t('arco.modal_consent.notes')}
            </label>
            <textarea
              rows={3}
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              placeholder={t('arco.modal_consent.notes_placeholder')}
              className="w-full text-xs rounded-lg border-gray-300 border p-2 focus:ring-1 focus:ring-turquesa focus:outline-none"
            />
          </div>

          <div className="pt-3 border-t border-gray-200 flex justify-end gap-2">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-xs font-semibold rounded-lg border border-gray-300 text-carbon hover:bg-gray-50 transition"
            >
              Cancelar
            </button>
            <button
              type="submit"
              className="px-4 py-2 text-xs font-semibold rounded-lg bg-turquesa text-carbon hover:bg-turquesa-light transition flex items-center gap-1.5 shadow-sm"
            >
              <FileCheck className="w-4 h-4" />
              <span>{t('arco.modal_consent.btn_save')}</span>
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
