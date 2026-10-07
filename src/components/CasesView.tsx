import React, { useState } from 'react';
import { FolderPlus, Lock } from 'lucide-react';
import { t } from '../lib/i18n';
import { 
  CaseWithDetails, 
  RoleName, 
  StatusAxisCode, 
  JournalEntry,
  ConsentType,
  ConsentStatus,
  Person
} from '../types/database';
import { CaseDetailView } from './CaseDetailView';
import { NewCaseModal } from './NewCaseModal';
import { CaseList } from './CaseList';
import { NewCaseInput } from '../lib/data';

interface CasesViewProps {
  cases: CaseWithDetails[];
  activeRole: RoleName;
  assignedAreaCode?: string;
  assignedAreaId?: string;
  authorUserId: string;
  authorFullName: string;
  onCaseCreated: (input: NewCaseInput) => void;
  onTransitionStatus: (
    caseId: string, 
    axisCode: StatusAxisCode, 
    newValueCode: string, 
    reason: string
  ) => void;
  onAddJournalEntry?: (entry: JournalEntry) => void;
  onAddClarification?: (originalEntryId: string, clarificationEntry: JournalEntry) => void;
  onShareJournalEntry?: (entryId: string, toAreaId: string, toAreaName: string, reason: string) => void;
  onSaveConsent?: (caseId: string, consent: {
    consent_type: ConsentType;
    status: ConsentStatus;
    is_minor_assent: boolean;
    legal_guardian_name?: string;
    legal_guardian_role?: string;
    authority_letter_ref?: string;
    notes?: string;
  }) => void;
  onRectifyPerson?: (personId: string, updates: Partial<Person>, reason: string) => void;
  onAnonymizePerson?: (personId: string, reason: string) => void;
  onOpposeSecondary?: (personId: string, reason: string) => void;
  // Expediente que debe abrirse al entrar (desde el tablero de operación)
  /** Folio del expediente abierto (viene de la URL) y cómo cambiarlo */
  selectedCaseNumber?: string | null;
  onSelectCase: (caseNumber: string | null) => void;
}

export const CasesView: React.FC<CasesViewProps> = ({
  cases,
  activeRole,
  assignedAreaCode,
  assignedAreaId,
  authorUserId,
  authorFullName,
  onCaseCreated,
  onTransitionStatus,
  onAddJournalEntry,
  onAddClarification,
  onShareJournalEntry,
  onSaveConsent,
  onRectifyPerson,
  onAnonymizePerson,
  onOpposeSecondary,
  selectedCaseNumber,
  onSelectCase,
}) => {
  const [isNewCaseModalOpen, setIsNewCaseModalOpen] = useState(false);


  const canOpenCase = activeRole === 'intake_officer' || activeRole === 'director';

  const selectedCase = cases.find((c) => c.case_number === selectedCaseNumber);


  // Folio de la URL que no existe o que esta persona no puede ver
  if (selectedCaseNumber && !selectedCase) {
    return (
      <div className="mx-auto max-w-lg rounded-xl border border-gray-200 bg-white p-8 text-center shadow-sm">
        <h2 className="text-base font-bold text-carbon">{t('cases.not_found_title')}</h2>
        <p className="mt-2 text-sm text-carbon-muted">{t('cases.not_found_body').replace('{folio}', selectedCaseNumber)}</p>
        <button
          type="button"
          onClick={() => onSelectCase(null)}
          className="mt-5 rounded-lg bg-carbon px-4 py-2 text-sm font-semibold text-white hover:bg-black"
        >
          {t('cases.btn_back')}
        </button>
      </div>
    );
  }

  // Si hay un caso seleccionado, mostrar la vista detallada
  if (selectedCase) {
    return (
      <CaseDetailView
        caseData={selectedCase}
        onBack={() => onSelectCase(null)}
        activeRole={activeRole}
        assignedAreaCode={assignedAreaCode}
        assignedAreaId={assignedAreaId}
        authorUserId={authorUserId}
        authorFullName={authorFullName}
        onTransitionStatus={onTransitionStatus}
        onSelectSubfolio={(subfolio) => onSelectCase(subfolio.case_number)}
        onAddJournalEntry={onAddJournalEntry}
        onAddClarification={onAddClarification}
        onShareJournalEntry={onShareJournalEntry}
        onSaveConsent={onSaveConsent ? (consent) => onSaveConsent(selectedCase.id, consent) : undefined}
        onRectifyPerson={onRectifyPerson ? (updates, reason) => onRectifyPerson(selectedCase.person.id, updates, reason) : undefined}
        onAnonymizePerson={onAnonymizePerson}
        onOpposeSecondary={onOpposeSecondary}
      />
    );
  }

  return (
    <div className="space-y-6">
      {/* Cabecera y botón de nuevo caso */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-white p-6 rounded-2xl border border-gray-200 shadow-sm">
        <div>
          <h2 className="text-xl font-bold text-carbon">{t('cases.title')}</h2>
          <p className="text-xs text-gray-500 mt-1">{t('cases.subtitle')}</p>
        </div>

        <div>
          {canOpenCase ? (
            <button
              onClick={() => setIsNewCaseModalOpen(true)}
              className="px-4 py-2.5 bg-carbon hover:bg-black text-white rounded-xl text-xs font-bold shadow-md flex items-center gap-2 transition-colors"
            >
              <FolderPlus className="w-4 h-4 text-turquesa" />
              <span>{t('cases.btn_new_case')}</span>
            </button>
          ) : (
            <div className="flex items-center space-x-2 bg-gray-100 px-3 py-2 rounded-xl text-gray-600 text-xs border border-gray-200">
              <Lock className="w-3.5 h-3.5" />
              <span>{t('cases.open_restricted')}</span>
            </div>
          )}
        </div>
      </div>

      <CaseList cases={cases} currentUserId={authorUserId} />

      {/* Modal de Nuevo Expediente */}
      <NewCaseModal
        isOpen={isNewCaseModalOpen}
        onClose={() => setIsNewCaseModalOpen(false)}
        onCaseCreated={onCaseCreated}
        authorUserId={authorUserId}
        authorFullName={authorFullName}
      />
    </div>
  );
};
