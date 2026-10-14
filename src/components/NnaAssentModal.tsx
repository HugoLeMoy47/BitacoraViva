import React from 'react';
import { X, HeartHandshake, Shield, Sparkles } from 'lucide-react';
import { t } from '../lib/i18n';
import { ModalShell } from './ModalShell';

interface NnaAssentModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export const NnaAssentModal: React.FC<NnaAssentModalProps> = ({ isOpen, onClose }) => {
  if (!isOpen) return null;

  return (
    <ModalShell onClose={onClose} className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 overflow-y-auto">
      <div className="bg-white rounded-2xl shadow-2xl max-w-2xl w-full max-h-[90vh] flex flex-col overflow-hidden border border-gray-100 animate-in fade-in zoom-in-95 duration-200">
        {/* Encabezado */}
        <div className="bg-carbon px-6 py-4 flex items-center justify-between text-white border-b border-carbon-muted/20 shrink-0">
          <div className="flex items-center gap-2.5">
            <HeartHandshake className="w-5 h-5 text-turquesa" />
            <div>
              <h3 className="text-sm font-bold tracking-wide">
                {t('nna_guide.title')}
              </h3>
              <p className="text-xs text-gray-300">
                {t('nna_guide.subtitle')}
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-white p-1 rounded transition"
            aria-label={t('common.close')}
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Contenido con scroll */}
        <div className="p-6 overflow-y-auto space-y-5 text-carbon text-xs">
          {/* Principio rector */}
          <div className="rounded-xl border border-turquesa/30 bg-claro/40 p-4 space-y-1.5">
            <div className="flex items-center gap-2 text-turquesa-dark font-bold text-sm">
              <Shield className="w-4 h-4" />
              <h4>{t('nna_guide.p1_title')}</h4>
            </div>
            <p className="text-gray-700 leading-relaxed">
              {t('nna_guide.p1_desc')}
            </p>
          </div>

          {/* Paso 1 */}
          <div className="rounded-xl border border-gray-200 bg-white p-4 space-y-1">
            <h4 className="font-bold text-carbon text-xs uppercase tracking-wide">
              {t('nna_guide.step1_title')}
            </h4>
            <p className="text-gray-600 leading-relaxed">
              {t('nna_guide.step1_desc')}
            </p>
          </div>

          {/* Paso 2: Guion verbal sugerido */}
          <div className="rounded-xl border border-gray-200 bg-white p-4 space-y-2">
            <div className="flex items-center gap-1.5 font-bold text-carbon text-xs uppercase tracking-wide">
              <Sparkles className="w-3.5 h-3.5 text-turquesa-dark" />
              <h4>{t('nna_guide.step2_title')}</h4>
            </div>
            <blockquote className="border-l-4 border-turquesa bg-gray-50 p-3 italic text-gray-800 leading-relaxed rounded-r-lg">
              {t('nna_guide.step2_script')}
            </blockquote>
          </div>

          {/* Paso 3: Derecho a pausar */}
          <div className="rounded-xl border border-gray-200 bg-white p-4 space-y-2">
            <h4 className="font-bold text-carbon text-xs uppercase tracking-wide">
              {t('nna_guide.step3_title')}
            </h4>
            <blockquote className="border-l-4 border-amber-400 bg-amber-50/50 p-3 italic text-gray-800 leading-relaxed rounded-r-lg">
              {t('nna_guide.step3_script')}
            </blockquote>
          </div>

          {/* Paso 4: Pregunta de validación */}
          <div className="rounded-xl border border-gray-200 bg-white p-4 space-y-2">
            <h4 className="font-bold text-carbon text-xs uppercase tracking-wide">
              {t('nna_guide.step4_title')}
            </h4>
            <blockquote className="border-l-4 border-emerald-500 bg-emerald-50/50 p-3 font-semibold text-carbon leading-relaxed rounded-r-lg">
              {t('nna_guide.step4_script')}
            </blockquote>
          </div>

          {/* Rechazo o incomodidad */}
          <div className="rounded-xl border border-amber-300 bg-amber-50/70 p-4 space-y-1 text-amber-900">
            <h4 className="font-bold text-xs uppercase tracking-wide">
              {t('nna_guide.refusal_title')}
            </h4>
            <p className="leading-relaxed">
              {t('nna_guide.refusal_desc')}
            </p>
          </div>
        </div>

        {/* Pie de modal */}
        <div className="bg-gray-50 px-6 py-3 border-t border-gray-200 flex justify-end shrink-0">
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg bg-turquesa px-5 py-2 text-xs font-semibold text-carbon shadow-sm hover:opacity-90"
          >
            {t('nna_guide.close_btn')}
          </button>
        </div>
      </div>
    </ModalShell>
  );
};
