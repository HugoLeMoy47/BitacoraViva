import { X, Bell, Check, ArrowRight, Clock } from 'lucide-react';
import { t } from '../lib/i18n';
import { SharingEvent } from '../types/database';
import { formatDate, formatDateTime } from '../lib/format';
import { ModalShell } from './ModalShell';

interface DirectorSharingInboxProps {
  isOpen: boolean;
  onClose: () => void;
  sharingEvents: SharingEvent[];
  onAcknowledge: (sharingEventId: string) => void;
  /** Hay una acción en curso: se deshabilita el acuse para evitar envíos dobles */
  busy?: boolean;
}

export const DirectorSharingInbox: React.FC<DirectorSharingInboxProps> = ({
  isOpen,
  onClose,
  sharingEvents,
  onAcknowledge,
  busy = false,
}) => {
  if (!isOpen) return null;

  const pendingEvents = sharingEvents.filter(e => !e.acknowledged_at);
  const acknowledgedEvents = sharingEvents.filter(e => !!e.acknowledged_at);

  return (
    <ModalShell onClose={onClose} className="fixed inset-0 z-50 flex items-center justify-center bg-carbon/60 p-4 backdrop-blur-sm">
      <div className="flex max-h-[85vh] w-full max-w-2xl flex-col rounded-xl bg-white shadow-2xl">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4">
          <div className="flex items-center gap-2">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-turquesa/10 text-turquesa-dark">
              <Bell className="h-5 w-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="font-title text-base font-bold text-carbon">
                  {t('journal.director_digest.title')}
                </h3>
                {pendingEvents.length > 0 && (
                  <span className="rounded-full bg-alerta-dark px-2 py-0.5 text-xs font-bold text-white">
                    {pendingEvents.length} {t('journal.director_digest.badge_pending')}
                  </span>
                )}
              </div>
              <p className="text-xs text-gray-500">
                {t('journal.director_digest.subtitle')}
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="rounded-lg p-1.5 text-gray-500 hover:bg-gray-100 hover:text-gray-600"
           aria-label={t('common.close')}>
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Content */}
        <div className="overflow-y-auto px-6 py-4 space-y-4">
          {pendingEvents.length === 0 && acknowledgedEvents.length === 0 ? (
            <div className="py-12 text-center text-sm text-gray-500">
              {t('journal.director_digest.empty')}
            </div>
          ) : (
            <>
              {pendingEvents.length > 0 && (
                <div className="space-y-3">
                  <h4 className="text-xs font-bold uppercase tracking-wider text-gray-500">
                    Pendientes de Acuse ({pendingEvents.length})
                  </h4>
                  {pendingEvents.map((evt) => (
                    <div
                      key={evt.id}
                      className="rounded-xl border border-turquesa/30 bg-turquesa/5 p-4 shadow-sm transition hover:shadow-md"
                    >
                      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-turquesa/10 pb-2.5">
                        <div className="flex items-center gap-2">
                          <span className="rounded bg-carbon px-2 py-0.5 text-xs font-bold text-white">
                            {evt.case_number || 'Expediente'}
                          </span>
                          <span className="text-xs font-semibold text-carbon">
                            {evt.from_area_name}
                          </span>
                          <ArrowRight className="h-3.5 w-3.5 text-gray-300" />
                          <span className="text-xs font-semibold text-turquesa-dark">
                            {evt.to_area_name}
                          </span>
                        </div>
                        <div className="flex items-center gap-1 text-xs text-gray-500">
                          <Clock className="h-3 w-3" />
                          <span>{formatDateTime(evt.shared_at)}</span>
                        </div>
                      </div>

                      <div className="mt-2.5">
                        <span className="text-xs font-bold text-gray-700">
                          {t('journal.director_digest.reason_label')}
                        </span>
                        <p className="mt-1 rounded-lg bg-white/80 p-2.5 text-xs italic text-gray-800 border border-gray-100">
                          "{evt.reason}"
                        </p>
                      </div>

                      <div className="mt-3 flex items-center justify-between pt-2">
                        <span className="text-xs text-gray-500">
                          {t('journal.director_digest.shared_by')} <strong className="text-carbon">{evt.shared_by_name || 'Personal'}</strong>
                        </span>
                        <button
                          onClick={() => onAcknowledge(evt.id)}
                          disabled={busy}
                          className="flex items-center gap-1.5 rounded-lg bg-turquesa px-3 py-1.5 text-xs font-bold text-carbon shadow-sm hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50"
                        >
                          <Check className="h-3.5 w-3.5" />
                          <span>{t('journal.director_digest.btn_acknowledge')}</span>
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              )}

              {acknowledgedEvents.length > 0 && (
                <div className="space-y-3 pt-3 border-t border-gray-100">
                  <h4 className="text-xs font-bold uppercase tracking-wider text-gray-500">
                    Acusadas Previamente ({acknowledgedEvents.length})
                  </h4>
                  {acknowledgedEvents.map((evt) => (
                    <div
                      key={evt.id}
                      className="rounded-lg border border-gray-200 bg-gray-50/60 p-3 text-xs opacity-85"
                    >
                      <div className="flex items-center justify-between text-gray-500">
                        <div className="flex items-center gap-2">
                          <span className="font-semibold text-carbon">{evt.case_number}</span>
                          <span>{evt.from_area_name} → {evt.to_area_name}</span>
                        </div>
                        <span className="text-gray-500">{formatDate(evt.shared_at)}</span>
                      </div>
                      <p className="mt-1 italic text-gray-600">"{evt.reason}"</p>
                      <div className="mt-2 text-xs text-gray-500">
                        {t('journal.director_digest.acknowledged_on')} {formatDateTime(evt.acknowledged_at)}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </ModalShell>
  );
};
