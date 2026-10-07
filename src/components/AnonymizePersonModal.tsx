import React, { useState } from 'react';
import { X, AlertTriangle, Trash2, ShieldAlert } from 'lucide-react';
import { t } from '../lib/i18n';
import { CaseWithDetails } from '../types/database';

interface AnonymizePersonModalProps {
  isOpen: boolean;
  onClose: () => void;
  caseData: CaseWithDetails;
  onAnonymize: (personId: string, reason: string) => void;
}

export const AnonymizePersonModal: React.FC<AnonymizePersonModalProps> = ({
  isOpen,
  onClose,
  caseData,
  onAnonymize,
}) => {
  const [challengeText, setChallengeText] = useState('');
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);

  if (!isOpen) return null;

  const isChallengeMatched = challengeText.trim().toUpperCase() === 'ANONIMIZAR';

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!reason.trim()) {
      setError(t('arco.modal_anonymize.reason_placeholder'));
      return;
    }
    if (!isChallengeMatched) {
      setError(t('arco.modal_anonymize.confirm_challenge'));
      return;
    }

    onAnonymize(caseData.person.id, reason.trim());
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-sm p-4 overflow-y-auto">
      <div className="bg-white rounded-xl shadow-2xl max-w-xl w-full overflow-hidden border-2 border-red-500 animate-in fade-in zoom-in-95 duration-200">
        {/* Encabezado de alerta máxima */}
        <div className="bg-red-700 px-6 py-4 flex items-center justify-between text-white">
          <div className="flex items-center gap-2">
            <ShieldAlert className="w-6 h-6 text-amber-300" />
            <div>
              <h3 className="text-sm font-bold tracking-wide">
                {t('arco.modal_anonymize.title')}
              </h3>
              <p className="text-xs text-red-200">
                {caseData.case_number} — {caseData.person.given_name} {caseData.person.paternal_family_name}
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="text-red-200 hover:text-white p-1 rounded transition"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Formulario */}
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          {/* Banner de alto impacto */}
          <div className="p-4 bg-red-50 border border-red-200 rounded-lg space-y-2">
            <div className="flex items-center gap-2 text-red-800 font-bold text-xs">
              <AlertTriangle className="w-4 h-4 text-red-600 shrink-0" />
              <span>{t('arco.modal_anonymize.alert_destructive_title')}</span>
            </div>
            <p className="text-xs text-red-700 leading-relaxed">
              {t('arco.modal_anonymize.alert_destructive_text')}
            </p>
          </div>

          {/* Lo que sobrevive */}
          <div className="p-3 bg-gray-50 border border-gray-200 rounded-lg space-y-1">
            <span className="text-xs font-bold text-carbon">
              {t('arco.modal_anonymize.retained_skeleton_title')}
            </span>
            <p className="text-xs text-gray-600">
              {t('arco.modal_anonymize.retained_skeleton_items')}
            </p>
          </div>

          {error && (
            <div className="p-2.5 bg-red-100 border border-red-300 rounded text-xs text-red-800 font-medium">
              {error}
            </div>
          )}

          <div>
            <label className="block text-xs font-bold text-carbon mb-1" htmlFor="anonym-1">
              {t('arco.modal_anonymize.reason')} <span className="text-red-500">*</span>
            </label>
            <textarea id="anonym-1" name="anonym-1" autoComplete="off"
              rows={2}
              required
              value={reason}
              onChange={(e) => {
                setReason(e.target.value);
                if (error) setError(null);
              }}
              placeholder={t('arco.modal_anonymize.reason_placeholder')}
              className="w-full text-xs rounded-lg border-gray-300 border p-2 focus:ring-1 focus:ring-red-500 focus:outline-none"
            />
          </div>

          {/* Reto de doble confirmación */}
          <div className="p-3 bg-amber-50 border border-amber-200 rounded-lg space-y-2">
            <label className="block text-xs font-bold text-amber-900" htmlFor="anonym-2">
              {t('arco.modal_anonymize.confirm_challenge')}
            </label>
            <input id="anonym-2" name="anonym-2" autoComplete="off"
              type="text"
              value={challengeText}
              onChange={(e) => {
                setChallengeText(e.target.value);
                if (error) setError(null);
              }}
              placeholder={t('arco.modal_anonymize.challenge_placeholder')}
              className="w-full text-xs font-mono uppercase tracking-widest rounded border border-amber-300 p-2 bg-white focus:outline-none focus:ring-2 focus:ring-red-500"
            />
          </div>

          <div className="pt-3 border-t border-gray-200 flex justify-end gap-2">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-xs font-semibold rounded-lg border border-gray-300 text-carbon hover:bg-gray-50 transition"
            >
              {t('arco.modal_anonymize.btn_cancel')}
            </button>
            <button
              type="submit"
              disabled={!isChallengeMatched || !reason.trim()}
              className={`px-4 py-2 text-xs font-bold rounded-lg flex items-center gap-1.5 shadow-sm transition ${
                isChallengeMatched && reason.trim()
                  ? 'bg-red-600 text-white hover:bg-red-700 cursor-pointer'
                  : 'bg-gray-200 text-gray-500 cursor-not-allowed'
              }`}
            >
              <Trash2 className="w-4 h-4" />
              <span>{t('arco.modal_anonymize.btn_execute')}</span>
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
