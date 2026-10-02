import { useState } from 'react';
import { X, Share2, CheckCircle2 } from 'lucide-react';
import { t } from '../lib/i18n';
import { JournalEntry } from '../types/database';
import { DEMO_AREAS } from '../lib/mockData';

interface ShareEntryModalProps {
  isOpen: boolean;
  onClose: () => void;
  entry: JournalEntry;
  authorUserId: string;
  authorFullName: string;
  onSubmitShare: (entryId: string, toAreaId: string, toAreaName: string, reason: string) => void;
}

export const ShareEntryModal: React.FC<ShareEntryModalProps> = ({
  isOpen,
  onClose,
  entry,
  authorUserId: _authorUserId,
  authorFullName: _authorFullName,
  onSubmitShare,
}) => {
  // Filter out the entry's own area
  const candidateAreas = DEMO_AREAS.filter(a => a.id !== entry.area_id);
  const [targetAreaId, setTargetAreaId] = useState<string>(
    candidateAreas[0]?.id || ''
  );
  const [reason, setReason] = useState<string>('');

  if (!isOpen) return null;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!reason.trim() || !targetAreaId) return;

    const targetArea = DEMO_AREAS.find(a => a.id === targetAreaId);
    onSubmitShare(entry.id, targetAreaId, targetArea?.name || '', reason.trim());
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-carbon/60 p-4 backdrop-blur-sm">
      <div className="flex max-h-[90vh] w-full max-w-xl flex-col rounded-xl bg-white shadow-2xl">
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4">
          <div className="flex items-center gap-2">
            <Share2 className="h-5 w-5 text-turquesa" />
            <h3 className="font-title text-base font-bold text-carbon">
              {t('journal.share_modal.title')}
            </h3>
          </div>
          <button
            onClick={onClose}
            className="rounded-lg p-1.5 text-gray-400 hover:bg-gray-100 hover:text-gray-600"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4 overflow-y-auto px-6 py-5">
          <p className="text-xs text-gray-500">
            {t('journal.share_modal.subtitle')}
          </p>

          <div className="rounded-lg border border-gray-200 bg-gray-50 p-3 text-xs">
            <span className="font-bold text-gray-600">Área de origen:</span>{' '}
            <span className="text-gray-800">{entry.area_name}</span>
            <p className="mt-1 line-clamp-2 text-gray-500 italic">"{entry.body}"</p>
          </div>

          <div>
            <label className="block text-xs font-semibold text-gray-700">
              {t('journal.share_modal.field_target_area')}
            </label>
            <select
              value={targetAreaId}
              onChange={(e) => setTargetAreaId(e.target.value)}
              className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-turquesa focus:outline-none"
            >
              {candidateAreas.map(a => (
                <option key={a.id} value={a.id}>{a.name}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-xs font-semibold text-gray-700">
              {t('journal.share_modal.field_reason')}
            </label>
            <textarea
              rows={4}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder={t('journal.share_modal.field_reason_placeholder')}
              required
              className="mt-1 w-full rounded-lg border border-gray-300 p-3 text-sm focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa"
            />
            <p className="mt-1 text-xs text-amber-700">
              * El motivo asentado notificará a la Dirección y quedará firmado de forma inmutable.
            </p>
          </div>

          <div className="flex items-center justify-end gap-3 pt-3 border-t border-gray-100">
            <button
              type="button"
              onClick={onClose}
              className="rounded-lg border border-gray-300 px-4 py-2 text-xs font-medium text-gray-700 hover:bg-gray-50"
            >
              {t('common.cancel')}
            </button>
            <button
              type="submit"
              disabled={!reason.trim()}
              className="flex items-center gap-2 rounded-lg bg-turquesa px-4 py-2 text-xs font-semibold text-white hover:opacity-90 disabled:opacity-50"
            >
              <CheckCircle2 className="h-4 w-4" />
              <span>{t('journal.share_modal.btn_submit')}</span>
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
