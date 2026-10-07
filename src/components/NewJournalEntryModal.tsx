import { useState } from 'react';
import { X, Calendar, Shield, Clock, AlertTriangle, Eye, ArrowRight, ArrowLeft, CheckCircle2 } from 'lucide-react';
import { t } from '../lib/i18n';
import { JournalEntry, JournalEntryType } from '../types/database';
import { useCatalog } from '../lib/catalog';

interface NewJournalEntryModalProps {
  isOpen: boolean;
  onClose: () => void;
  caseId: string;
  caseNumber: string;
  authorUserId: string;
  authorFullName: string;
  assignedAreaId?: string;
  onEntryCreated: (entry: JournalEntry) => void;
}

export const NewJournalEntryModal: React.FC<NewJournalEntryModalProps> = ({
  isOpen,
  onClose,
  caseId,
  caseNumber,
  authorUserId,
  authorFullName,
  assignedAreaId,
  onEntryCreated,
}) => {
  const { areas } = useCatalog();
  const [step, setStep] = useState<'compose' | 'preview'>('compose');
  const [entryType, setEntryType] = useState<JournalEntryType>('follow_up');
  const [areaId, setAreaId] = useState<string>(
    assignedAreaId || areas.find(a => a.code === 'trabajo_social')?.id || areas[0]?.id || ''
  );
  const [occurredAt, setOccurredAt] = useState<string>(
    new Date().toISOString().slice(0, 16)
  );
  const [isWorkNote, setIsWorkNote] = useState<boolean>(false);
  const [body, setBody] = useState<string>('');

  if (!isOpen) return null;

  const currentArea = areas.find(a => a.id === areaId) || areas[0];

  const handleProceedToPreview = (e: React.FormEvent) => {
    e.preventDefault();
    if (!body.trim()) return;
    setStep('preview');
  };

  const handleSave = () => {
    const newEntry: JournalEntry = {
      id: crypto.randomUUID(),
      organization_id: currentArea.organization_id,
      case_id: caseId,
      case_number: caseNumber,
      area_id: currentArea.id,
      area_code: currentArea.code,
      area_name: currentArea.name,
      author_user_id: authorUserId,
      author_name: authorFullName,
      entry_type_key: entryType,
      body: body.trim(),
      is_work_note: isWorkNote,
      occurred_at: new Date(occurredAt).toISOString(),
      created_at: new Date().toISOString(),
      visibility: 'area_private',
      superseded_by_id: null,
    };

    onEntryCreated(newEntry);
    onClose();
  };

  const getEntryTypeLabel = (type: JournalEntryType) => {
    return t(`journal.types.${type}`);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-carbon/60 p-4 backdrop-blur-sm">
      <div className="flex max-h-[90vh] w-full max-w-2xl flex-col rounded-xl bg-white shadow-2xl">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4">
          <div>
            <div className="flex items-center gap-2">
              <span className="rounded bg-turquesa/10 px-2.5 py-0.5 text-xs font-bold text-turquesa">
                {caseNumber}
              </span>
              <h3 className="font-title text-lg font-bold text-carbon">
                {t('journal.new_modal.title')}
              </h3>
            </div>
            <p className="mt-0.5 text-xs text-gray-500">
              {t('journal.new_modal.subtitle')}
            </p>
          </div>
          <button
            onClick={onClose}
            className="rounded-lg p-1.5 text-gray-400 hover:bg-gray-100 hover:text-gray-600"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Step indicator */}
        <div className="flex border-b border-gray-100 bg-gray-50/70 px-6 py-2.5 text-xs font-medium">
          <div className={`flex items-center gap-1.5 ${step === 'compose' ? 'font-bold text-turquesa' : 'text-gray-400'}`}>
            <span>{t('journal.new_modal.step_compose')}</span>
          </div>
          <span className="mx-3 text-gray-300">/</span>
          <div className={`flex items-center gap-1.5 ${step === 'preview' ? 'font-bold text-turquesa' : 'text-gray-400'}`}>
            <Eye className="h-3.5 w-3.5" />
            <span>{t('journal.new_modal.step_preview')}</span>
          </div>
        </div>

        {/* Body content */}
        <div className="overflow-y-auto px-6 py-5">
          {step === 'compose' ? (
            <form onSubmit={handleProceedToPreview} className="space-y-4">
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <div>
                  <label className="block text-xs font-semibold text-gray-700">
                    {t('journal.new_modal.field_type')}
                  </label>
                  <select
                    value={entryType}
                    onChange={(e) => setEntryType(e.target.value as JournalEntryType)}
                    className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-turquesa focus:outline-none"
                  >
                    <option value="follow_up">{t('journal.types.follow_up')}</option>
                    <option value="intake_interview">{t('journal.types.intake_interview')}</option>
                    <option value="referral">{t('journal.types.referral')}</option>
                    <option value="home_visit">{t('journal.types.home_visit')}</option>
                    <option value="incident">{t('journal.types.incident')}</option>
                    <option value="note">{t('journal.types.note')}</option>
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-semibold text-gray-700">
                    {t('journal.new_modal.field_area')}
                  </label>
                  <select
                    value={areaId}
                    onChange={(e) => setAreaId(e.target.value)}
                    className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-turquesa focus:outline-none"
                  >
                    {areas.map(a => (
                      <option key={a.id} value={a.id}>{a.name}</option>
                    ))}
                  </select>
                </div>
              </div>

              <div>
                <label className="flex items-center gap-1.5 text-xs font-semibold text-gray-700">
                  <Calendar className="h-3.5 w-3.5 text-gray-500" />
                  {t('journal.new_modal.field_occurred_at')}
                </label>
                <input
                  type="datetime-local"
                  value={occurredAt}
                  onChange={(e) => setOccurredAt(e.target.value)}
                  className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-turquesa focus:outline-none"
                />
                <p className="mt-1 text-xs text-gray-500">
                  {t('journal.new_modal.field_occurred_help')}
                </p>
              </div>

              {/* Work Note Switch (Ethos E-02 / MD-04) */}
              <div className="rounded-lg border border-amber-200 bg-amber-50/60 p-3.5">
                <label className="flex cursor-pointer items-start gap-3">
                  <input
                    type="checkbox"
                    checked={isWorkNote}
                    onChange={(e) => setIsWorkNote(e.target.checked)}
                    className="mt-1 h-4 w-4 rounded border-gray-300 text-amber-600 focus:ring-amber-500"
                  />
                  <div>
                    <span className="flex items-center gap-1.5 text-xs font-bold text-amber-900">
                      <Shield className="h-4 w-4 text-amber-600" />
                      {t('journal.new_modal.field_work_note')}
                    </span>
                    <p className="mt-0.5 text-xs leading-relaxed text-amber-800/90">
                      {t('journal.new_modal.field_work_note_help')}
                    </p>
                  </div>
                </label>
              </div>

              {/* Body */}
              <div>
                <label className="block text-xs font-semibold text-gray-700">
                  {t('journal.new_modal.field_body')}
                </label>
                <textarea
                  rows={5}
                  value={body}
                  onChange={(e) => setBody(e.target.value)}
                  placeholder={t('journal.new_modal.field_body_placeholder')}
                  required
                  className="mt-1 w-full rounded-lg border border-gray-300 p-3 text-sm focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa"
                />
              </div>

              <div className="flex justify-end pt-2">
                <button
                  type="submit"
                  disabled={!body.trim()}
                  className="flex items-center gap-2 rounded-lg bg-turquesa px-5 py-2.5 text-sm font-semibold text-white shadow-sm hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  <span>{t('journal.new_modal.btn_to_preview')}</span>
                  <ArrowRight className="h-4 w-4" />
                </button>
              </div>
            </form>
          ) : (
            /* PREVIEW STEP - Mitigación UX 5.1 */
            <div className="space-y-4">
              <div className="flex items-start gap-3 rounded-lg border border-blue-200 bg-blue-50/70 p-3.5 text-xs text-blue-900">
                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-blue-600" />
                <div>
                  <p className="font-bold">{t('journal.new_modal.preview_title')}</p>
                  <p className="mt-0.5 text-blue-800/90">
                    {t('journal.new_modal.preview_warning')}
                  </p>
                </div>
              </div>

              {/* Mock Rendered Card */}
              <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
                <div className="flex flex-wrap items-center justify-between gap-2 border-b border-gray-100 pb-3">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="rounded-md bg-gray-100 px-2.5 py-1 text-xs font-bold text-gray-700">
                      {currentArea.name}
                    </span>
                    <span className="rounded-md bg-turquesa/10 px-2.5 py-1 text-xs font-semibold text-turquesa">
                      {getEntryTypeLabel(entryType)}
                    </span>
                    {isWorkNote && (
                      <span className="flex items-center gap-1 rounded-md bg-amber-100 px-2.5 py-1 text-xs font-bold text-amber-800">
                        <Shield className="h-3 w-3" />
                        {t('journal.work_note_badge')}
                      </span>
                    )}
                  </div>
                  <div className="flex items-center gap-1.5 text-xs text-gray-500">
                    <Clock className="h-3.5 w-3.5" />
                    <span>{t('journal.occurred_at')} {new Date(occurredAt).toLocaleString()}</span>
                  </div>
                </div>

                <div className="mt-4 whitespace-pre-wrap text-sm leading-relaxed text-carbon">
                  {body}
                </div>

                <div className="mt-4 border-t border-gray-100 pt-3 text-xs text-gray-400">
                  <span>{t('journal.author_by')} {authorFullName}</span>
                  <span className="mx-2">·</span>
                  <span className="font-medium text-gray-500">{t('journal.visibility_area_private')}</span>
                </div>
              </div>

              <div className="flex items-center justify-between pt-4">
                <button
                  type="button"
                  onClick={() => setStep('compose')}
                  className="flex items-center gap-2 rounded-lg border border-gray-300 px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
                >
                  <ArrowLeft className="h-4 w-4" />
                  <span>{t('journal.new_modal.btn_back_edit')}</span>
                </button>

                <button
                  type="button"
                  onClick={handleSave}
                  className="flex items-center gap-2 rounded-lg bg-carbon px-5 py-2.5 text-sm font-semibold text-white shadow-md hover:bg-gray-800"
                >
                  <CheckCircle2 className="h-4 w-4 text-turquesa" />
                  <span>{t('journal.new_modal.btn_save_entry')}</span>
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
