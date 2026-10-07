import { useState } from 'react';
import { X, FileText, CheckCircle2 } from 'lucide-react';
import { t } from '../lib/i18n';
import { JournalEntry } from '../types/database';
import { ModalShell } from './ModalShell';

interface ClarificationNoteModalProps {
  isOpen: boolean;
  onClose: () => void;
  originalEntry: JournalEntry;
  authorUserId: string;
  authorFullName: string;
  onSubmitClarification: (originalEntryId: string, clarificationEntry: JournalEntry) => void;
}

export const ClarificationNoteModal: React.FC<ClarificationNoteModalProps> = ({
  isOpen,
  onClose,
  originalEntry,
  authorUserId,
  authorFullName,
  onSubmitClarification,
}) => {
  const [body, setBody] = useState<string>('');
  const [isWorkNote, setIsWorkNote] = useState<boolean>(originalEntry.is_work_note);

  if (!isOpen) return null;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!body.trim()) return;

    const clarificationEntry: JournalEntry = {
      id: crypto.randomUUID(),
      organization_id: originalEntry.organization_id,
      case_id: originalEntry.case_id,
      case_number: originalEntry.case_number,
      area_id: originalEntry.area_id,
      area_code: originalEntry.area_code,
      area_name: originalEntry.area_name,
      author_user_id: authorUserId,
      author_name: authorFullName,
      entry_type_key: originalEntry.entry_type_key,
      body: body.trim(),
      is_work_note: isWorkNote,
      occurred_at: originalEntry.occurred_at,
      created_at: new Date().toISOString(),
      visibility: originalEntry.visibility,
      superseded_by_id: null,
    };

    onSubmitClarification(originalEntry.id, clarificationEntry);
    onClose();
  };

  return (
    <ModalShell onClose={onClose} className="fixed inset-0 z-50 flex items-center justify-center bg-carbon/60 p-4 backdrop-blur-sm">
      <div className="flex max-h-[90vh] w-full max-w-xl flex-col rounded-xl bg-white shadow-2xl">
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4">
          <div className="flex items-center gap-2">
            <FileText className="h-5 w-5 text-turquesa-dark" />
            <h3 className="font-title text-base font-bold text-carbon">
              {t('journal.clarification_modal.title')}
            </h3>
          </div>
          <button
            onClick={onClose}
            className="rounded-lg p-1.5 text-gray-500 hover:bg-gray-100 hover:text-gray-600"
           aria-label={t('common.close')}>
            <X className="h-5 w-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4 overflow-y-auto px-6 py-5">
          <p className="text-xs text-gray-500">
            {t('journal.clarification_modal.subtitle')}
          </p>

          {/* Original text snippet */}
          <div className="rounded-lg border border-gray-200 bg-gray-50 p-3.5">
            <span className="block text-xs font-bold text-gray-600">
              {t('journal.clarification_modal.original_label')}
            </span>
            <p className="mt-1 line-clamp-3 text-xs italic text-gray-700">
              "{originalEntry.body}"
            </p>
          </div>

          <div>
            <label className="block text-xs font-semibold text-gray-700" htmlFor="clarif-1">
              {t('journal.clarification_modal.field_body')}
            </label>
            <textarea id="clarif-1" name="clarif-1" autoComplete="off"
              rows={4}
              value={body}
              onChange={(e) => setBody(e.target.value)}
              placeholder={t('journal.clarification_modal.field_body_placeholder')}
              required
              className="mt-1 w-full rounded-lg border border-gray-300 p-3 text-sm focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa"
            />
          </div>

          <label className="flex items-center gap-2 text-xs font-medium text-gray-700">
            <input
              type="checkbox"
              checked={isWorkNote}
              onChange={(e) => setIsWorkNote(e.target.checked)}
              className="h-4 w-4 rounded border-gray-300 text-turquesa focus:ring-turquesa"
            />
            <span>{t('journal.clarification_modal.field_work_note')}</span>
          </label>

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
              disabled={!body.trim()}
              className="flex items-center gap-2 rounded-lg bg-turquesa px-4 py-2 text-xs font-semibold text-carbon hover:opacity-90 disabled:opacity-50"
            >
              <CheckCircle2 className="h-4 w-4" />
              <span>{t('journal.clarification_modal.btn_submit')}</span>
            </button>
          </div>
        </form>
      </div>
    </ModalShell>
  );
};
