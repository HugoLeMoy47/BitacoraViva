import React, { useState } from 'react';
import { X, ShieldAlert, CheckCircle, Save } from 'lucide-react';
import { t } from '../lib/i18n';
import { CaseWithDetails } from '../types/database';

interface OpposeSecondaryTreatmentModalProps {
  isOpen: boolean;
  onClose: () => void;
  caseData: CaseWithDetails;
  onOppose: (personId: string, reason: string) => void;
}

export const OpposeSecondaryTreatmentModal: React.FC<OpposeSecondaryTreatmentModalProps> = ({
  isOpen,
  onClose,
  caseData,
  onOppose,
}) => {
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);

  if (!isOpen) return null;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!reason.trim()) {
      setError(t('arco.modal_oppose.reason_placeholder'));
      return;
    }

    onOppose(caseData.person.id, reason.trim());
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 overflow-y-auto">
      <div className="bg-white rounded-xl shadow-2xl max-w-xl w-full overflow-hidden border border-gray-100 animate-in fade-in zoom-in-95 duration-200">
        {/* Encabezado */}
        <div className="bg-carbon px-6 py-4 flex items-center justify-between text-white border-b border-carbon-muted/20">
          <div className="flex items-center gap-2">
            <ShieldAlert className="w-5 h-5 text-amber-400" />
            <div>
              <h3 className="text-sm font-bold tracking-wide">
                {t('arco.modal_oppose.title')}
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
            {t('arco.modal_oppose.subtitle')}
          </p>

          {/* Garantía humanitaria inquebrantable */}
          <div className="p-4 bg-emerald-50 border border-emerald-200 rounded-lg space-y-1">
            <div className="flex items-center gap-2 text-emerald-800 font-bold text-xs">
              <CheckCircle className="w-4 h-4 text-emerald-600 shrink-0" />
              <span>{t('arco.modal_oppose.guarantee_title')}</span>
            </div>
            <p className="text-[11px] text-emerald-700 leading-relaxed">
              {t('arco.modal_oppose.guarantee_text')}
            </p>
          </div>

          <div className="p-3 bg-gray-50 border border-gray-200 rounded-lg text-xs text-carbon space-y-1">
            <span className="font-semibold">{t('arco.modal_oppose.scope_label')}</span>
            <p className="text-[11px] text-gray-600">
              {t('arco.modal_oppose.scope_research')}
            </p>
          </div>

          {error && (
            <div className="p-2.5 bg-red-50 border border-red-200 rounded text-xs text-red-700">
              {error}
            </div>
          )}

          <div>
            <label className="block text-xs font-bold text-carbon mb-1">
              {t('arco.modal_oppose.reason')} <span className="text-red-500">*</span>
            </label>
            <textarea
              rows={3}
              required
              value={reason}
              onChange={(e) => {
                setReason(e.target.value);
                if (error) setError(null);
              }}
              placeholder={t('arco.modal_oppose.reason_placeholder')}
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
              <Save className="w-4 h-4" />
              <span>{t('arco.modal_oppose.btn_save')}</span>
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
