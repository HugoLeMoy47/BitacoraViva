import React from 'react';
import { X, Printer, ShieldCheck, Calendar, FileText } from 'lucide-react';
import { t } from '../lib/i18n';
import { ArcoRequest, CaseWithDetails } from '../types/database';
import { formatDate, formatDateTime } from '../lib/format';
import { ModalShell } from './ModalShell';

interface ArcoReceiptModalProps {
  isOpen: boolean;
  onClose: () => void;
  arcoRequest: ArcoRequest;
  caseData: CaseWithDetails;
  organizationName: string;
  organizationPrefix?: string;
  organizationInfo: {
    responsibleName?: string;
    responsibleAddress?: string;
    arcoContact?: string;
  };
}

import { computeBusinessDaysDeadline, computeArcoDocket } from '../lib/arco';
export { computeBusinessDaysDeadline, computeArcoDocket };


export const ArcoReceiptModal: React.FC<ArcoReceiptModalProps> = ({
  isOpen,
  onClose,
  arcoRequest,
  caseData,
  organizationName,
  organizationPrefix = 'BV',
  organizationInfo,
}) => {
  if (!isOpen) return null;

  const docket = computeArcoDocket(arcoRequest, organizationPrefix);
  const deadlineDate = computeBusinessDaysDeadline(arcoRequest.received_at, 20);
  const fullName = [
    caseData.person.given_name,
    caseData.person.paternal_family_name,
    caseData.person.maternal_family_name,
  ]
    .filter(Boolean)
    .join(' ');

  return (
    <ModalShell onClose={onClose} className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 overflow-y-auto">
      <div className="bg-white rounded-2xl shadow-2xl max-w-2xl w-full max-h-[90vh] flex flex-col overflow-hidden border border-gray-100 animate-in fade-in zoom-in-95 duration-200">
        {/* Encabezado modal */}
        <div className="bg-carbon px-6 py-4 flex items-center justify-between text-white border-b border-carbon-muted/20 shrink-0">
          <div className="flex items-center gap-2">
            <FileText className="w-5 h-5 text-turquesa" />
            <div>
              <h3 className="text-sm font-bold tracking-wide">
                {t('arco.receipt_title')}
              </h3>
              <p className="text-xs text-gray-300">
                {docket}
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

        {/* Contenido imprimible */}
        <div className="p-6 overflow-y-auto space-y-6 text-carbon text-xs print:p-0">
          {/* Membrete institucional */}
          <div className="border-b border-gray-200 pb-4 flex justify-between items-start">
            <div>
              <span className="text-[11px] uppercase font-bold tracking-wider text-turquesa-dark">
                {t('arco.receipt_contact_label')}
              </span>
              <h2 className="text-base font-bold text-carbon">{organizationName}</h2>
              {(organizationInfo.responsibleName || organizationInfo.responsibleAddress || organizationInfo.arcoContact) && (
                <p className="mt-1 text-xs text-gray-600">
                  {[organizationInfo.responsibleName, organizationInfo.responsibleAddress, organizationInfo.arcoContact]
                    .filter(Boolean)
                    .join(' · ')}
                </p>
              )}
            </div>
            <div className="text-right">
              <span className="inline-block rounded-lg bg-carbon px-2.5 py-1 text-xs font-mono font-bold text-white shadow-xs">
                {docket}
              </span>
            </div>
          </div>

          {/* Caja oficial de plazo y folio */}
          <div className="rounded-xl border border-turquesa/30 bg-claro/30 p-4 space-y-2">
            <div className="flex items-center gap-2 text-carbon font-bold text-sm">
              <ShieldCheck className="w-4 h-4 text-turquesa-dark" />
              <h4>{t('arco.receipt_title')}</h4>
            </div>
            <p className="text-xs text-gray-700">
              {t('arco.receipt_subtitle')}
            </p>
            <div className="pt-2 border-t border-turquesa/20 grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs">
              <div>
                <span className="text-gray-500 block font-medium">{t('arco.receipt_received_at')}</span>
                <span className="font-semibold text-carbon">{formatDateTime(arcoRequest.received_at)}</span>
              </div>
              <div>
                <span className="text-gray-500 block font-medium">{t('arco.receipt_legal_deadline')}</span>
                <span className="font-semibold text-emerald-800 flex items-center gap-1">
                  <Calendar className="w-3.5 h-3.5" />
                  {t('arco.receipt_deadline_desc').replace('{date}', formatDate(deadlineDate))}
                </span>
              </div>
            </div>
          </div>

          {/* Datos del trámite */}
          <div className="rounded-xl border border-gray-200 p-4 space-y-3 bg-white">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <span className="text-gray-500 block">{t('arco.receipt_titular')}</span>
                <span className="font-bold text-carbon">{fullName}</span>
              </div>
              <div>
                <span className="text-gray-500 block">{t('arco.receipt_case')}</span>
                <span className="font-mono font-bold text-carbon">{caseData.case_number}</span>
              </div>
              <div>
                <span className="text-gray-500 block">{t('arco.receipt_petitioner')}</span>
                <span className="font-semibold text-carbon">{arcoRequest.requested_by_name}</span>
              </div>
              <div>
                <span className="text-gray-500 block">{t('arco.receipt_right')}</span>
                <span className="inline-block px-2 py-0.5 rounded bg-gray-100 font-bold text-carbon border border-gray-200">
                  {t(`arco.types.${arcoRequest.request_type}`)}
                </span>
              </div>
            </div>

            <div className="pt-2 border-t border-gray-100">
              <span className="text-gray-500 block mb-1">{t('arco.receipt_reason')}</span>
              <p className="bg-gray-50 p-3 rounded-lg text-gray-800 italic border border-gray-100">
                "{arcoRequest.reason}"
              </p>
            </div>
          </div>

          {/* Nota legal y firma institucional */}
          <div className="rounded-xl border border-gray-200 p-4 bg-gray-50/50 space-y-3">
            <p className="text-[11px] text-gray-600 leading-relaxed">
              {t('arco.receipt_legal_note')}
            </p>
            <div className="pt-6 flex justify-between items-end text-gray-500 text-[11px]">
              <div>
                <div className="border-t border-gray-400 w-48 mb-1" />
                <span>{organizationName} · {t('arco.table_status')}: {t(`arco.statuses.${arcoRequest.status}`)}</span>
              </div>
              <div className="text-right font-mono text-[10px]">
                <span>{arcoRequest.id}</span>
              </div>
            </div>
          </div>
        </div>

        {/* Botones de acción */}
        <div className="bg-gray-50 px-6 py-3 border-t border-gray-200 flex justify-end gap-3 shrink-0 print:hidden">
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg border border-gray-300 bg-white px-4 py-2 text-xs font-semibold text-gray-700 shadow-sm hover:bg-gray-50"
          >
            {t('arco.receipt_close_btn')}
          </button>
          <button
            type="button"
            onClick={() => window.print()}
            className="rounded-lg bg-turquesa px-4 py-2 text-xs font-semibold text-carbon shadow-sm hover:opacity-90 flex items-center gap-1.5"
          >
            <Printer className="w-3.5 h-3.5" />
            <span>{t('arco.receipt_print_btn')}</span>
          </button>
        </div>
      </div>
    </ModalShell>
  );
};
