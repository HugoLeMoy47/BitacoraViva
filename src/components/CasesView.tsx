import React, { useState } from 'react';
import { 
  FolderPlus, 
  Search, 
  ChevronRight, 
  Lock
} from 'lucide-react';
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

interface CasesViewProps {
  cases: CaseWithDetails[];
  activeRole: RoleName;
  assignedAreaCode?: string;
  assignedAreaId?: string;
  authorUserId: string;
  authorFullName: string;
  onCaseCreated: (newCase: CaseWithDetails) => void;
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
}) => {
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedCaseId, setSelectedCaseId] = useState<string | null>(null);
  const [isNewCaseModalOpen, setIsNewCaseModalOpen] = useState(false);

  const canOpenCase = activeRole === 'intake_officer' || activeRole === 'director';

  const selectedCase = cases.find((c) => c.id === selectedCaseId);

  const filteredCases = cases.filter((c) => {
    const term = searchTerm.toLowerCase();
    const matchesNumber = c.case_number.toLowerCase().includes(term);
    const matchesName = `${c.person.given_name} ${c.person.paternal_family_name}`.toLowerCase().includes(term);
    const matchesPreferred = c.person.preferred_name?.toLowerCase().includes(term);
    const matchesCountry = c.person.other_nationality?.toLowerCase().includes(term);
    const matchesVulnerability = c.vulnerabilities.some(v => v.marker_code.toLowerCase().includes(term));
    return matchesNumber || matchesName || matchesPreferred || matchesCountry || matchesVulnerability;
  });

  // Si hay un caso seleccionado, mostrar la vista detallada
  if (selectedCase) {
    return (
      <CaseDetailView
        caseData={selectedCase}
        onBack={() => setSelectedCaseId(null)}
        activeRole={activeRole}
        assignedAreaCode={assignedAreaCode}
        assignedAreaId={assignedAreaId}
        authorUserId={authorUserId}
        authorFullName={authorFullName}
        onTransitionStatus={onTransitionStatus}
        onSelectSubfolio={(subfolio) => setSelectedCaseId(subfolio.id)}
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
            <div className="flex items-center space-x-2 bg-gray-100 px-3 py-2 rounded-xl text-gray-400 text-xs border border-gray-200">
              <Lock className="w-3.5 h-3.5" />
              <span>Apertura exclusiva Intake / Dirección</span>
            </div>
          )}
        </div>
      </div>

      {/* Barra de búsqueda y filtros */}
      <div className="bg-white p-4 rounded-xl border border-gray-200 shadow-xs flex items-center gap-3">
        <div className="relative flex-1">
          <Search className="w-4 h-4 text-gray-400 absolute left-3 top-3" />
          <input
            type="text"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            placeholder={t('cases.search_placeholder')}
            className="w-full text-xs pl-9 pr-4 py-2 border border-gray-200 rounded-lg focus:outline-none focus:border-turquesa"
          />
        </div>
        <span className="text-xs text-gray-400 font-mono whitespace-nowrap">
          {filteredCases.length} expedientes
        </span>
      </div>

      {/* Tabla de Casos */}
      <div className="bg-white rounded-2xl border border-gray-200 shadow-sm overflow-hidden">
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200 text-xs">
            <thead className="bg-gray-50 text-gray-500 font-semibold uppercase text-[11px]">
              <tr>
                <th className="px-6 py-3.5 text-left">{t('cases.col_folio')}</th>
                <th className="px-6 py-3.5 text-left">{t('cases.col_person')}</th>
                <th className="px-6 py-3.5 text-left">{t('cases.col_nationality')}</th>
                <th className="px-6 py-3.5 text-left">{t('cases.col_priority_status')}</th>
                <th className="px-6 py-3.5 text-left">{t('cases.col_vulnerabilities')}</th>
                <th className="px-6 py-3.5 text-right">{t('cases.col_actions')}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100 bg-white">
              {filteredCases.map((c) => {
                const isUnaccompanied = c.vulnerabilities.some(v => v.marker_code === 'unaccompanied_child');
                const isSubfolio = !!c.parent_case_id;
                const isReentry = !!c.previous_case_id;

                return (
                  <tr key={c.id} className="hover:bg-gray-50 transition-colors">
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="flex items-center space-x-2">
                        <span className="font-mono font-bold text-carbon text-sm">{c.case_number}</span>
                      </div>
                      <div className="flex items-center gap-1 mt-1">
                        {isUnaccompanied && (
                          <span className="bg-red-100 text-red-800 text-[10px] font-bold px-1.5 py-0.2 rounded">
                            NNA No Acompañado
                          </span>
                        )}
                        {isSubfolio && (
                          <span className="bg-purple-100 text-purple-800 text-[10px] font-medium px-1.5 py-0.2 rounded">
                            Subfolio
                          </span>
                        )}
                        {isReentry && (
                          <span className="bg-blue-100 text-blue-800 text-[10px] font-medium px-1.5 py-0.2 rounded">
                            Reingreso
                          </span>
                        )}
                      </div>
                    </td>

                    <td className="px-6 py-4">
                      <div className="font-bold text-carbon">
                        {c.person.given_name} {c.person.paternal_family_name}
                      </div>
                      {c.person.preferred_name && (
                        <div className="text-turquesa-dark italic text-[11px]">
                          "{c.person.preferred_name}"
                        </div>
                      )}
                    </td>

                    <td className="px-6 py-4 text-gray-600">
                      <div>{c.person.other_nationality || 'Honduras'}</div>
                      <div className="text-[11px] text-gray-400">{c.person.other_language || 'Español'}</div>
                    </td>

                    <td className="px-6 py-4">
                      <span className="px-2.5 py-1 bg-claro text-turquesa-dark border border-turquesa/30 rounded-full font-bold text-[11px] inline-block">
                        {c.statuses.engagement_status?.label || 'Primer contacto'}
                      </span>
                    </td>

                    <td className="px-6 py-4">
                      <div className="flex flex-wrap gap-1 max-w-xs">
                        {c.vulnerabilities.map((v) => (
                          <span
                            key={v.id}
                            className="bg-gray-100 text-gray-700 px-2 py-0.5 rounded text-[10px] border border-gray-200"
                          >
                            {v.marker_code === 'unaccompanied_child'
                              ? 'Niñez no acompañada'
                              : v.marker_code === 'separated_child'
                              ? 'Niñez separada'
                              : v.marker_code === 'victim_of_violence'
                              ? 'Sobreviviente violencia'
                              : v.marker_code === 'medical_condition'
                              ? 'Condición médica'
                              : v.marker_code === 'indigenous_language_speaker'
                              ? 'Lengua indígena'
                              : v.marker_code}
                          </span>
                        ))}
                      </div>
                    </td>

                    <td className="px-6 py-4 text-right whitespace-nowrap">
                      <button
                        onClick={() => setSelectedCaseId(c.id)}
                        className="px-3 py-1.5 text-xs font-semibold text-carbon bg-gray-100 hover:bg-claro border border-gray-200 rounded-lg inline-flex items-center gap-1 transition-colors"
                      >
                        <span>{t('cases.action_view_detail')}</span>
                        <ChevronRight className="w-3.5 h-3.5 text-turquesa-dark" />
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

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
