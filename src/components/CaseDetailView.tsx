import React, { useState } from 'react';
import { 
  ArrowLeft, 
  ShieldAlert, 
  Clock, 
  AlertCircle, 
  Layers, 
  FileText, 
  Users, 
  ChevronRight, 
  Send, 
  Lock,
  BookOpen,
  Share2,
  Plus,
  Shield,
  CornerDownRight,
  Eye,
  EyeOff,
  ShieldCheck,
  Edit3,
  Trash2,
  CheckCircle2,
  Scale
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
import { VULNERABILITY_CATALOG } from '../lib/catalogs';
import { useCatalog } from '../lib/catalog';
import { NewJournalEntryModal } from './NewJournalEntryModal';
import { ClarificationNoteModal } from './ClarificationNoteModal';
import { ShareEntryModal } from './ShareEntryModal';
import { ConsentModal } from './ConsentModal';
import { RectifyPersonModal } from './RectifyPersonModal';
import { AnonymizePersonModal } from './AnonymizePersonModal';
import { OpposeSecondaryTreatmentModal } from './OpposeSecondaryTreatmentModal';
import { ArcoAccessExtractModal } from './ArcoAccessExtractModal';
import { formatDate, formatDateTime, formatTime } from '../lib/format';
import { ModalShell } from './ModalShell';
import { Tabs } from './Tabs';
import { StatusHistory } from './StatusHistory';

interface CaseDetailViewProps {
  caseData: CaseWithDetails;
  onBack: () => void;
  activeRole: RoleName;
  assignedAreaCode?: string;
  assignedAreaId?: string;
  authorUserId: string;
  authorFullName: string;
  onTransitionStatus: (
    caseId: string, 
    axisCode: StatusAxisCode, 
    newValueCode: string, 
    reason: string
  ) => void;
  onSelectSubfolio?: (subfolioCase: CaseWithDetails) => void;
  onAddJournalEntry?: (entry: JournalEntry) => void;
  onAddClarification?: (originalEntryId: string, clarificationEntry: JournalEntry) => void;
  onShareJournalEntry?: (entryId: string, toAreaId: string, toAreaName: string, reason: string) => void;
  onSaveConsent?: (consent: {
    consent_type: ConsentType;
    status: ConsentStatus;
    is_minor_assent: boolean;
    legal_guardian_name?: string;
    legal_guardian_role?: string;
    authority_letter_ref?: string;
    notes?: string;
  }) => void;
  onRectifyPerson?: (updates: Partial<Person>, reason: string) => void;
  onAnonymizePerson?: (personId: string, reason: string) => void;
  onOpposeSecondary?: (personId: string, reason: string) => void;
}

export const CaseDetailView: React.FC<CaseDetailViewProps> = ({
  caseData,
  onBack,
  activeRole,
  assignedAreaCode,
  assignedAreaId,
  authorUserId,
  authorFullName,
  onTransitionStatus,
  onSelectSubfolio,
  onAddJournalEntry,
  onAddClarification,
  onShareJournalEntry,
  onSaveConsent,
  onRectifyPerson,
  onAnonymizePerson,
  onOpposeSecondary,
}) => {
  const { statusAxes, statusValues } = useCatalog();
  const [activeTab, setActiveTab] = useState<'axes' | 'journal' | 'summary' | 'vulnerabilities' | 'subfolios' | 'privacy'>('axes');
  const [transitioningAxis, setTransitioningAxis] = useState<StatusAxisCode | null>(null);
  const [targetValueCode, setTargetValueCode] = useState<string>('');
  const [transitionReason, setTransitionReason] = useState<string>('');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Estados para Bitácora (Épica E4)
  const [journalFilter, setJournalFilter] = useState<'all' | 'my_area' | 'shared' | 'work_notes'>('all');
  const [isNewJournalOpen, setIsNewJournalOpen] = useState<boolean>(false);
  const [clarifyingEntry, setClarifyingEntry] = useState<JournalEntry | null>(null);
  const [sharingEntry, setSharingEntry] = useState<JournalEntry | null>(null);
  const [expandedSuperseded, setExpandedSuperseded] = useState<Record<string, boolean>>({});

  // Estados para Privacidad y Derechos ARCO (Épica E5)
  const [isConsentModalOpen, setIsConsentModalOpen] = useState<boolean>(false);
  const [isRectifyModalOpen, setIsRectifyModalOpen] = useState<boolean>(false);
  const [isAnonymizeModalOpen, setIsAnonymizeModalOpen] = useState<boolean>(false);
  const [isOpposeModalOpen, setIsOpposeModalOpen] = useState<boolean>(false);
  const [isAccessExtractModalOpen, setIsAccessExtractModalOpen] = useState<boolean>(false);

  const hasUnaccompaniedChild = caseData.vulnerabilities.some(
    (v) => v.marker_code === 'unaccompanied_child'
  );

  const isDirector = activeRole === 'director';
  const isLegalCaseworker = activeRole === 'caseworker' && assignedAreaCode === 'legal';
  const canWriteJournal = activeRole === 'caseworker' || activeRole === 'intake_officer' || activeRole === 'director';
  const canManageConsent = activeRole === 'intake_officer' || activeRole === 'caseworker' || activeRole === 'director';
  const canRectify = activeRole === 'intake_officer' || activeRole === 'director';

  const consents = caseData.consents || [];
  const arcoRequests = caseData.arco_requests || [];
  const hasSensitiveDataConsent = consents.some(
    (c) => c.consent_type === 'sensitive_data' && c.status === 'granted'
  );

  const journalEntries = caseData.journal_entries || [];

  const filteredJournalEntries = journalEntries.filter((entry) => {
    if (journalFilter === 'my_area') {
      return entry.area_code === assignedAreaCode;
    }
    if (journalFilter === 'shared') {
      return entry.visibility === 'shared';
    }
    if (journalFilter === 'work_notes') {
      return entry.is_work_note;
    }
    return true;
  });

  const toggleSuperseded = (entryId: string) => {
    setExpandedSuperseded((prev) => ({
      ...prev,
      [entryId]: !prev[entryId],
    }));
  };

  const handleOpenTransition = (axisCode: StatusAxisCode) => {
    setTransitioningAxis(axisCode);
    setErrorMessage(null);
    setTransitionReason('');
    const possibleValues = statusValues[axisCode] || [];
    const firstNonCurrent = possibleValues.find(v => v.code !== caseData.statuses[axisCode]?.valueCode);
    setTargetValueCode(firstNonCurrent ? firstNonCurrent.code : (possibleValues[0]?.code || ''));
  };

  const handleConfirmTransition = () => {
    if (!transitioningAxis || !targetValueCode) return;

    if (!transitionReason.trim()) {
      setErrorMessage(t('cases.err_reason_required'));
      return;
    }

    // Regla de gobernanza: legal_status solo director o caseworker de legal
    if (transitioningAxis === 'legal_status' && !isDirector && !isLegalCaseworker) {
      setErrorMessage(t('cases.err_legal_restricted'));
      return;
    }

    // Regla de gobernanza: closed sólo director
    if (targetValueCode === 'closed' && !isDirector) {
      setErrorMessage(t('cases.err_closed_restricted'));
      return;
    }

    onTransitionStatus(caseData.id, transitioningAxis, targetValueCode, transitionReason.trim());
    setTransitioningAxis(null);
  };

  return (
    <div className="space-y-6">
      {/* Barra superior de navegación */}
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-gray-200 pb-4">
        <button
          onClick={onBack}
          className="flex min-h-9 items-center gap-2 whitespace-nowrap text-sm font-semibold text-carbon-muted hover:text-carbon transition"
        >
          <ArrowLeft className="w-4 h-4" />
          <span>{t('cases.btn_back')}</span>
        </button>

        <div className="flex items-center gap-2">
          <span className="whitespace-nowrap font-mono text-xs px-2.5 py-1 rounded bg-carbon text-white font-bold tracking-wider">
            {caseData.case_number}
          </span>
          <span className="whitespace-nowrap text-xs bg-claro text-turquesa-dark px-2.5 py-1 rounded-full font-bold">
            {caseData.statuses.engagement_status?.label || 'Primer Contacto'}
          </span>
        </div>
      </div>

      {/* Cabecera del Expediente */}
      <div className="bg-white rounded-2xl p-6 border border-gray-200 shadow-sm flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <div className="flex items-center gap-3">
            <h2 className="font-title text-2xl font-bold text-carbon">
              {caseData.person.preferred_name || `${caseData.person.given_name} ${caseData.person.paternal_family_name}`}
            </h2>
            {caseData.parent_case_id && (
              <span className="text-xs bg-turquesa/15 text-turquesa px-2 py-0.5 rounded font-bold uppercase tracking-wider">
                {t('cases.badge_subfolio')}
              </span>
            )}
            {hasUnaccompaniedChild && (
              <span className="text-xs bg-alerta text-white px-2 py-0.5 rounded font-bold uppercase tracking-wider">
                {t('cases.badge_unaccompanied')}
              </span>
            )}
          </div>
          <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-gray-500 mt-2">
            <span className="font-medium text-carbon">
              {caseData.person.given_name} {caseData.person.paternal_family_name}
            </span>
            {caseData.person.preferred_name && (
              <span className="text-turquesa-dark italic">
                ("{caseData.person.preferred_name}")
              </span>
            )}
            <span>·</span>
            <span>{caseData.person.other_nationality || 'Honduras'}</span>
            <span>·</span>
            <span>Apertura: {formatDate(caseData.opened_at)}</span>
          </div>
        </div>

        <div className="flex items-center gap-2">
          {caseData.parentCaseNumber && (
            <div className="text-xs bg-gray-50 p-2.5 rounded-xl border border-gray-200">
              <span className="text-gray-500 block">{t('cases.subfolio_of')}</span>
              <span className="font-mono font-bold text-carbon">{caseData.parentCaseNumber}</span>
            </div>
          )}
        </div>
      </div>

      {/* Alerta de Niñez No Acompañada */}
      {hasUnaccompaniedChild && (
        <div className="bg-alerta-bg border border-alerta/30 rounded-2xl p-4 flex items-start gap-3 text-alerta">
          <ShieldAlert className="w-5 h-5 flex-shrink-0 mt-0.5" />
          <div className="text-xs">
            <h4 className="font-bold">{t('cases.badge_unaccompanied')}</h4>
            <p className="mt-0.5 text-carbon-muted">{t('cases.unaccompanied_notice')}</p>
          </div>
        </div>
      )}

      {/* Secciones del expediente */}
      <Tabs
        ariaLabel={t('cases.sections')}
        value={activeTab}
        onChange={(id) => setActiveTab(id as typeof activeTab)}
        items={[
          { id: 'axes', label: t('cases.tab_axes'), icon: <Layers className="h-4 w-4" aria-hidden="true" /> },
          { id: 'journal', label: `${t('journal.tab_title')} (${journalEntries.length})`, icon: <BookOpen className="h-4 w-4" aria-hidden="true" /> },
          { id: 'summary', label: t('cases.tab_summary'), icon: <FileText className="h-4 w-4" aria-hidden="true" /> },
          { id: 'vulnerabilities', label: `${t('cases.tab_vulnerabilities')} (${caseData.vulnerabilities.length})`, icon: <AlertCircle className="h-4 w-4" aria-hidden="true" /> },
          ...(caseData.subfolios && caseData.subfolios.length > 0
            ? [{ id: 'subfolios', label: `${t('cases.tab_subfolios')} (${caseData.subfolios.length})`, icon: <Users className="h-4 w-4" aria-hidden="true" /> }]
            : []),
          {
            id: 'privacy',
            label: t('arco.tab_title'),
            icon: <ShieldCheck className="h-4 w-4" aria-hidden="true" />,
            badge: !hasSensitiveDataConsent ? (
              <span className="h-2 w-2 rounded-full bg-amber-500" role="img" aria-label={t('arco.sensitive_alert_missing')} title={t('arco.sensitive_alert_missing')} />
            ) : undefined,
          },
        ]}
      />

      {/* Tab 1: Los 5 Ejes de Estatus (Regla Dura 7 / ME-02) */}
      {activeTab === 'axes' && (
        <div className="space-y-4">
          <div className="bg-claro/30 p-4 rounded-xl border border-turquesa/30 text-xs text-carbon">
            <h3 className="font-bold text-turquesa-dark mb-1">{t('cases.axes_section_title')}</h3>
            <p className="text-gray-600">
              {t('cases.axes_section_desc')}
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {statusAxes.map((axis) => {
              const currentStatus = caseData.statuses[axis.code];
              const isPrimary = axis.is_primary;

              return (
                <div
                  key={axis.id}
                  className={`bg-white rounded-2xl p-5 border flex flex-col justify-between shadow-sm transition hover:shadow-md ${
                    isPrimary ? 'border-turquesa/60 ring-2 ring-turquesa/20' : 'border-gray-200'
                  }`}
                >
                  <div>
                    <div className="flex items-center justify-between mb-2">
                      <span className="text-xs font-bold uppercase tracking-wider text-gray-500">
                        {axis.label_es}
                      </span>
                      {isPrimary && (
                        <span className="text-xs bg-turquesa/20 text-carbon font-extrabold px-2 py-0.5 rounded-full">
                          {t('cases.axis_primary')}
                        </span>
                      )}
                    </div>

                    <div className="my-2">
                      <h4 className="text-base font-bold text-carbon">
                        {currentStatus?.label || 'Sin Asignar'}
                      </h4>
                      <p className="text-xs text-gray-500 mt-0.5 flex items-center gap-1">
                        <Clock className="w-3 h-3" />
                        <span>{t('cases.status_since')}: {formatDate(currentStatus?.valid_from)}</span>
                      </p>
                    </div>

                    {currentStatus?.reason && (
                      <div className="mt-3 p-3 bg-gray-50 rounded-xl text-xs text-gray-600 border border-gray-100">
                        <span className="font-semibold text-gray-500 block mb-0.5">
                          {t('cases.last_reason')}:
                        </span>
                        <p className="italic">"{currentStatus.reason}"</p>
                      </div>
                    )}
                  </div>

                  <div className="mt-5 pt-3 border-t border-gray-100 flex items-center justify-between">
                    <span className="text-xs text-gray-500 font-mono">
                      {axis.code}
                    </span>
                    <button
                      onClick={() => handleOpenTransition(axis.code)}
                      className="min-h-9 px-3 py-1.5 text-xs font-bold text-carbon bg-turquesa/20 hover:bg-turquesa hover:text-carbon rounded-lg transition"
                    >
                      {t('cases.btn_change_status')}
                    </button>
                  </div>
                </div>
              );
            })}
          </div>

          <StatusHistory caseId={caseData.id} />
        </div>
      )}

      {/* Tab 2: Bitácora de Intervenciones (Épica E4) */}
      {activeTab === 'journal' && (
        <div className="space-y-4">
          {/* Header de Bitácora */}
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 bg-white p-4 rounded-xl border border-gray-200">
            {/* Filtros */}
            <div className="flex flex-wrap items-center gap-1.5 text-xs">
              <button
                onClick={() => setJournalFilter('all')}
                className={`px-3 py-1.5 rounded-lg font-bold transition ${
                  journalFilter === 'all'
                    ? 'bg-carbon text-white shadow-sm'
                    : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                }`}
              >
                {t('journal.filter_all')}
              </button>
              {assignedAreaCode && (
                <button
                  onClick={() => setJournalFilter('my_area')}
                  className={`px-3 py-1.5 rounded-lg font-bold transition ${
                    journalFilter === 'my_area'
                      ? 'bg-turquesa text-carbon shadow-sm'
                      : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                  }`}
                >
                  {t('journal.filter_my_area')}
                </button>
              )}
              <button
                onClick={() => setJournalFilter('shared')}
                className={`px-3 py-1.5 rounded-lg font-bold transition ${
                  journalFilter === 'shared'
                    ? 'bg-blue-600 text-white shadow-sm'
                    : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                }`}
              >
                {t('journal.filter_shared')}
              </button>
              <button
                onClick={() => setJournalFilter('work_notes')}
                className={`px-3 py-1.5 rounded-lg font-bold transition ${
                  journalFilter === 'work_notes'
                    ? 'bg-amber-600 text-white shadow-sm'
                    : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                }`}
              >
                {t('journal.filter_work_notes')}
              </button>
            </div>

            {/* Botón de Nueva Entrada */}
            {canWriteJournal && (
              <button
                onClick={() => setIsNewJournalOpen(true)}
                className="flex items-center gap-2 rounded-lg bg-turquesa px-4 py-2 text-xs font-bold text-white shadow-sm hover:opacity-90"
              >
                <Plus className="h-4 w-4" />
                <span>{t('journal.btn_new_entry')}</span>
              </button>
            )}
          </div>

          {/* Lista de Entradas de Bitácora */}
          {filteredJournalEntries.length === 0 ? (
            <div className="rounded-xl border border-dashed border-gray-300 bg-white p-12 text-center text-sm text-gray-500">
              {t('journal.empty_state')}
            </div>
          ) : (
            <div className="space-y-4">
              {filteredJournalEntries.map((entry) => {
                const isSuperseded = !!entry.superseded_by_id;
                const isExpanded = !!expandedSuperseded[entry.id];
                const isShared = entry.visibility === 'shared';

                return (
                  <div
                    key={entry.id}
                    className={`rounded-2xl border bg-white p-5 shadow-sm transition hover:shadow ${
                      isSuperseded
                        ? 'border-gray-200 bg-gray-50/70 opacity-90'
                        : isShared
                        ? 'border-blue-200 ring-1 ring-blue-100'
                        : 'border-gray-200'
                    }`}
                  >
                    {/* Header de la Tarjeta */}
                    <div className="flex flex-wrap items-center justify-between gap-2 border-b border-gray-100 pb-3">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="rounded-md bg-gray-100 px-2.5 py-1 text-xs font-bold text-gray-700">
                          {entry.area_name || entry.area_code}
                        </span>
                        <span className="rounded-md bg-turquesa/10 px-2.5 py-1 text-xs font-semibold text-turquesa">
                          {t(`journal.types.${entry.entry_type_key}`)}
                        </span>

                        {entry.is_work_note && (
                          <span
                            title={t('journal.work_note_tooltip')}
                            className="flex items-center gap-1 rounded-md bg-amber-100 px-2.5 py-1 text-xs font-bold text-amber-800"
                          >
                            <Shield className="h-3 w-3" />
                            {t('journal.work_note_badge')}
                          </span>
                        )}

                        {isShared ? (
                          <span className="flex items-center gap-1 rounded-md bg-blue-100 px-2 py-0.5 text-xs font-bold text-blue-800">
                            <Share2 className="h-3 w-3" />
                            {t('journal.visibility_shared')} {entry.sharing_event?.to_area_name || 'otra área'}
                          </span>
                        ) : (
                          <span className="flex items-center gap-1 rounded-md bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-500">
                            <Lock className="h-3 w-3" />
                            {t('journal.visibility_area_private')}
                          </span>
                        )}
                      </div>

                      <div className="flex items-center gap-3 text-xs text-gray-500">
                        <span title={`${t('journal.captured')} ${formatDateTime(entry.created_at)}`}>
                          <strong>{t('journal.occurred_at')}</strong> {formatDate(entry.occurred_at)}
                        </span>
                      </div>
                    </div>

                    {/* Banner si la nota fue superada por fe de erratas */}
                    {isSuperseded && (
                      <div className="mt-3 flex items-center justify-between rounded-lg border border-amber-200 bg-amber-50 p-2.5 text-xs text-amber-900">
                        <div className="flex items-center gap-2">
                          <AlertCircle className="h-4 w-4 text-amber-600" />
                          <span>{t('journal.superseded_notice')}</span>
                        </div>
                        <button
                          onClick={() => toggleSuperseded(entry.id)}
                          className="flex items-center gap-1 font-bold text-amber-800 underline hover:text-amber-950"
                        >
                          {isExpanded ? (
                            <>
                              <EyeOff className="h-3.5 w-3.5" />
                              <span>{t('journal.superseded_toggle_hide')}</span>
                            </>
                          ) : (
                            <>
                              <Eye className="h-3.5 w-3.5" />
                              <span>{t('journal.superseded_toggle_show')}</span>
                            </>
                          )}
                        </button>
                      </div>
                    )}

                    {/* Cuerpo de la intervención */}
                    {(!isSuperseded || isExpanded) && (
                      <div className={`mt-3.5 whitespace-pre-wrap text-sm leading-relaxed ${
                        isSuperseded ? 'text-gray-500 line-through' : 'text-carbon'
                      }`}>
                        {entry.body}
                      </div>
                    )}

                    {/* Footer y Acciones */}
                    <div className="mt-4 flex flex-wrap items-center justify-between gap-2 border-t border-gray-100 pt-3 text-xs text-gray-500">
                      <div>
                        <span>{t('journal.author_by')} <strong className="text-gray-700">{entry.author_name || 'Personal Operativo'}</strong></span>
                        <span className="mx-2">·</span>
                        <span>{t('journal.created_at')} {formatTime(entry.created_at)}</span>
                      </div>

                      {/* Botones de Acción (solo en entradas activas) */}
                      {!isSuperseded && canWriteJournal && (
                        <div className="flex items-center gap-2">
                          {/* Botón de Fe de Erratas */}
                          <button
                            onClick={() => setClarifyingEntry(entry)}
                            className="flex items-center gap-1 rounded-md border border-gray-300 px-2.5 py-1 text-xs font-medium text-gray-700 hover:bg-gray-50 hover:text-carbon"
                          >
                            <CornerDownRight className="h-3 w-3 text-turquesa" />
                            <span>{t('journal.btn_clarify')}</span>
                          </button>

                          {/* Botón de Compartir si es privada */}
                          {!isShared && (
                            <button
                              onClick={() => setSharingEntry(entry)}
                              className="flex items-center gap-1 rounded-md bg-blue-50 px-2.5 py-1 text-xs font-bold text-blue-700 hover:bg-blue-100"
                            >
                              <Share2 className="h-3 w-3" />
                              <span>{t('journal.btn_share')}</span>
                            </button>
                          )}
                        </div>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}

      {/* Tab 3: Resumen y Ficha Sociodemográfica MAP-OIM v3 */}
      {activeTab === 'summary' && (
        <div className="bg-white rounded-2xl p-6 border border-gray-200 shadow-sm space-y-6">
          <div>
            <h3 className="text-sm font-bold text-carbon uppercase tracking-wider mb-4 border-b pb-2">
              {t('cases.section_identity')}
            </h3>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 text-xs">
              <div>
                <span className="text-gray-500 block">{t('cases.field_given_name')}</span>
                <span className="font-semibold text-carbon text-sm">{caseData.person.given_name}</span>
              </div>
              <div>
                <span className="text-gray-500 block">{t('cases.field_family_names')}</span>
                <span className="font-semibold text-carbon text-sm">
                  {caseData.person.paternal_family_name} {caseData.person.maternal_family_name || ''}
                </span>
              </div>
              <div>
                <span className="text-gray-500 block">{t('cases.field_preferred_name')}</span>
                <span className="font-semibold text-turquesa-dark text-sm">
                  {caseData.person.preferred_name || 'No especificado'}
                </span>
              </div>
              <div>
                <span className="text-gray-500 block">{t('cases.field_birth_date')}</span>
                <span className="font-semibold text-carbon text-sm">
                  {formatDate(caseData.person.birth_date)} {caseData.person.birth_date_is_estimated && `(${t('cases.estimated_birth')})`}
                </span>
              </div>
              <div>
                <span className="text-gray-500 block">{t('cases.field_nationality')}</span>
                <span className="font-semibold text-carbon text-sm">
                  {caseData.person.other_nationality || 'Honduras'}
                </span>
              </div>
              <div>
                <span className="text-gray-500 block">{t('cases.field_language')}</span>
                <span className="font-semibold text-carbon text-sm">
                  {caseData.person.other_language || 'Español'}
                </span>
              </div>
              <div>
                <span className="text-gray-500 block">{t('cases.field_phone')}</span>
                <span className="font-semibold text-carbon text-sm">
                  {caseData.person.phone_number || 'Sin teléfono'}
                </span>
              </div>
            </div>
          </div>

          <div>
            <h3 className="text-sm font-bold text-carbon uppercase tracking-wider mb-4 border-b pb-2">
              {t('cases.section_intake_context')}
            </h3>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 text-xs">
              <div>
                <span className="text-gray-500 block">{t('cases.field_window_type')}</span>
                <span className="font-semibold text-carbon text-sm capitalize">{caseData.intake_window_type}</span>
              </div>
              <div>
                <span className="text-gray-500 block">{t('cases.field_entry_date')}</span>
                <span className="font-semibold text-carbon text-sm">{caseData.entry_date_str || 'Septiembre 2026'}</span>
              </div>
              <div>
                <span className="text-gray-500 block">{t('cases.field_family_travel')}</span>
                <span className="font-semibold text-carbon text-sm">
                  {caseData.travels_with_family ? t('common.yes') : t('common.no')}
                </span>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Tab 4: Marcadores de Vulnerabilidad (13 MAP-OIM v3) */}
      {activeTab === 'vulnerabilities' && (
        <div className="bg-white rounded-2xl p-6 border border-gray-200 shadow-sm space-y-4">
          <div className="border-b pb-3">
            <h3 className="text-sm font-bold text-carbon uppercase tracking-wider">
              {t('cases.tab_vulnerabilities')} ({caseData.vulnerabilities.length})
            </h3>
            <p className="text-xs text-gray-500 mt-0.5">
              Marcadores objetivos conforme al estándar MAP-OIM v3 (Fase 3).
            </p>
          </div>

          {caseData.vulnerabilities.length === 0 ? (
            <div className="text-xs text-gray-500 italic p-4 text-center">
              No se han afirmado marcadores de vulnerabilidad para este caso.
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {caseData.vulnerabilities.map((v) => {
                const def = VULNERABILITY_CATALOG[v.marker_code];
                return (
                  <div
                    key={v.id}
                    className="p-4 rounded-xl border border-gray-200 bg-gray-50/50 flex flex-col justify-between"
                  >
                    <div>
                      <div className="flex items-center gap-2">
                        <AlertCircle className="w-4 h-4 text-alerta flex-shrink-0" />
                        <h4 className="text-xs font-bold text-carbon">
                          {def?.label || v.marker_code}
                        </h4>
                      </div>
                      <p className="text-xs text-gray-500 mt-1">
                        {def?.description}
                      </p>
                      {v.notes && (
                        <div className="mt-2 text-xs bg-white p-2.5 rounded border border-gray-200 italic text-gray-700">
                          "{v.notes}"
                        </div>
                      )}
                    </div>
                    <div className="mt-3 pt-2 border-t border-gray-200/60 text-xs text-gray-500 flex items-center justify-between">
                      <span>Afirmado por: {v.affirmed_by}</span>
                      <span>{formatDate(v.affirmed_at)}</span>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}

      {/* Tab 5: Subfolios Familiares */}
      {activeTab === 'subfolios' && (
        <div className="bg-white rounded-2xl p-6 border border-gray-200 shadow-sm space-y-4">
          <div className="border-b pb-3">
            <h3 className="text-sm font-bold text-carbon uppercase tracking-wider">
              {t('cases.tab_subfolios')} ({caseData.subfolios?.length || 0})
            </h3>
            <p className="text-xs text-gray-500 mt-0.5">
              Subfolios subordinados (NNA acompañados con expediente propio).
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {caseData.subfolios?.map((sub) => (
              <div
                key={sub.id}
                className="p-4 rounded-xl border border-gray-200 bg-white hover:border-turquesa transition flex items-center justify-between"
              >
                <div>
                  <div className="flex items-center gap-2">
                    <span className="font-mono text-xs font-bold bg-carbon text-white px-2 py-0.5 rounded">
                      {sub.case_number}
                    </span>
                    <span className="text-xs font-bold text-carbon">
                      {sub.person.given_name} {sub.person.paternal_family_name}
                    </span>
                  </div>
                  <span className="text-xs text-gray-500 mt-1 block">
                    {sub.person.preferred_name && `"${sub.person.preferred_name}" · `}
                    {formatDate(sub.person.birth_date)} ({sub.statuses.engagement_status?.label})
                  </span>
                </div>
                {onSelectSubfolio && (
                  <button
                    onClick={() => onSelectSubfolio(sub)}
                    className="p-2 text-carbon hover:text-turquesa"
                  >
                    <ChevronRight className="w-5 h-5" />
                  </button>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Tab 6: Privacidad, Consentimientos y Derechos ARCO (Épica E5) */}
      {activeTab === 'privacy' && (
        <div className="space-y-6">
          {/* Header Card */}
          <div className="bg-white rounded-2xl p-6 border border-gray-200 shadow-sm space-y-4">
            <div className="flex flex-wrap items-center justify-between gap-4 border-b border-gray-100 pb-4">
              <div>
                <div className="flex items-center gap-2">
                  <ShieldCheck className="w-5 h-5 text-turquesa" />
                  <h3 className="text-sm font-bold text-carbon uppercase tracking-wider">
                    {t('arco.section_consent_title')}
                  </h3>
                </div>
                <p className="text-xs text-gray-500 mt-1">
                  {t('arco.section_consent_desc')}
                </p>
              </div>

              <div className="flex items-center gap-3">
                <span className="text-xs font-mono bg-claro text-carbon px-2.5 py-1 rounded-full border border-turquesa/30 font-semibold">
                  {t('arco.privacy_notice_badge')}
                </span>
                {canManageConsent && onSaveConsent && (
                  <button
                    onClick={() => setIsConsentModalOpen(true)}
                    className="px-3 py-1.5 text-xs font-semibold rounded-lg bg-turquesa text-carbon hover:bg-turquesa-light transition flex items-center gap-1.5 shadow-sm"
                  >
                    <Plus className="w-3.5 h-3.5" />
                    <span>{t('arco.btn_manage_consents')}</span>
                  </button>
                )}
              </div>
            </div>

            {/* Alerta de Consentimiento para Datos Sensibles (Control P-06) */}
            {!hasSensitiveDataConsent ? (
              <div className="p-3.5 bg-amber-50 border border-amber-200 rounded-xl flex items-start gap-3 text-xs text-amber-900">
                <ShieldAlert className="w-5 h-5 text-amber-600 shrink-0 mt-0.5" />
                <div>
                  <span className="font-bold block mb-0.5">{t('arco.p06_active')}</span>
                  <p>{t('arco.sensitive_alert_missing')}</p>
                </div>
              </div>
            ) : (
              <div className="p-3 bg-emerald-50 border border-emerald-200 rounded-xl flex items-center gap-2 text-xs text-emerald-800">
                <CheckCircle2 className="w-4 h-4 text-emerald-600 shrink-0" />
                <span className="font-medium">{t('arco.sensitive_alert_ok')}</span>
              </div>
            )}

            {/* Tarjetas de Consentimientos */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 pt-2">
              {(['general_care', 'sensitive_data', 'secondary_use_research'] as ConsentType[]).map((typeKey) => {
                const consentItem = consents.find((c) => c.consent_type === typeKey);
                const isGranted = consentItem?.status === 'granted';
                const isOpposed = consentItem?.status === 'opposed';
                const isRevoked = consentItem?.status === 'revoked';

                return (
                  <div
                    key={typeKey}
                    className={`p-4 rounded-xl border transition ${
                      isGranted
                        ? 'border-emerald-200 bg-emerald-50/20'
                        : isOpposed
                        ? 'border-amber-200 bg-amber-50/20'
                        : 'border-gray-200 bg-gray-50/50'
                    }`}
                  >
                    <div className="flex justify-between items-start mb-2">
                      <span className="font-bold text-xs text-carbon">
                        {t(`arco.consent_types.${typeKey}`)}
                      </span>
                      <span
                        className={`text-xs font-bold px-2 py-0.5 rounded-full ${
                          isGranted
                            ? 'bg-emerald-100 text-emerald-800 border border-emerald-300'
                            : isOpposed
                            ? 'bg-amber-100 text-amber-800 border border-amber-300'
                            : isRevoked
                            ? 'bg-red-100 text-red-800 border border-red-300'
                            : 'bg-gray-200 text-gray-600'
                        }`}
                      >
                        {consentItem ? t(`arco.consent_status.${consentItem.status}`) : 'Pendiente'}
                      </span>
                    </div>

                    {consentItem ? (
                      <div className="text-xs text-gray-600 space-y-1 mt-2">
                        {consentItem.is_minor_assent && (
                          <div className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded bg-amber-100 text-amber-900 text-xs font-semibold mb-1">
                            <Scale className="w-3 h-3 text-amber-700" />
                            <span>{t('arco.assent_label')}</span>
                          </div>
                        )}
                        {consentItem.legal_guardian_name && (
                          <p>
                            <span className="font-medium text-gray-500">{t('arco.guardian_label')}</span> {consentItem.legal_guardian_name} ({consentItem.legal_guardian_role})
                          </p>
                        )}
                        {consentItem.authority_letter_ref && (
                          <p>
                            <span className="font-medium text-gray-500">{t('arco.authority_ref_label')}</span> <span className="font-mono">{consentItem.authority_letter_ref}</span>
                          </p>
                        )}
                        <p>
                          <span className="font-medium text-gray-500">{t('arco.granted_at_label')}</span> {formatDate(consentItem.granted_at)}
                        </p>
                        {consentItem.notes && (
                          <p className="italic text-gray-500 text-xs bg-white/70 p-1.5 rounded border border-gray-100 mt-1">
                            "{consentItem.notes}"
                          </p>
                        )}
                      </div>
                    ) : (
                      <p className="text-xs text-gray-500 italic mt-2">
                        No se ha asentado registro para esta modalidad.
                      </p>
                    )}
                  </div>
                );
              })}
            </div>
          </div>

          {/* Sección: Ejercicio de Derechos ARCO */}
          <div className="bg-white rounded-2xl p-6 border border-gray-200 shadow-sm space-y-5">
            <div className="border-b border-gray-100 pb-3">
              <h3 className="text-sm font-bold text-carbon uppercase tracking-wider">
                {t('arco.arco_section_title')}
              </h3>
              <p className="text-xs text-gray-500 mt-1">
                {t('arco.arco_section_desc')}
              </p>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
              {/* Acceso */}
              <div className="p-4 rounded-xl border border-gray-200 bg-gray-50/50 flex flex-col justify-between space-y-3">
                <div>
                  <div className="flex items-center gap-1.5 text-xs font-bold text-carbon mb-1">
                    <FileText className="w-4 h-4 text-turquesa-dark" />
                    <span>{t('arco.right_access')}</span>
                  </div>
                  <p className="text-xs text-gray-500 leading-relaxed">
                    Expedir extracto oficial depurado (excluye notas de trabajo profesional protegidas por Ethos E-02).
                  </p>
                </div>
                <button
                  onClick={() => setIsAccessExtractModalOpen(true)}
                  disabled={!isDirector}
                  className={`w-full py-2 px-3 rounded-lg text-xs font-semibold flex items-center justify-center gap-1.5 shadow-sm transition ${
                    isDirector
                      ? 'bg-carbon text-white hover:bg-carbon-muted cursor-pointer'
                      : 'bg-gray-200 text-gray-300 cursor-not-allowed'
                  }`}
                  title={!isDirector ? 'Reservado a Dirección (BV-5.2)' : undefined}
                >
                  <FileText className="w-3.5 h-3.5" />
                  <span>{t('arco.btn_access')}</span>
                </button>
              </div>

              {/* Rectificación */}
              <div className="p-4 rounded-xl border border-gray-200 bg-gray-50/50 flex flex-col justify-between space-y-3">
                <div>
                  <div className="flex items-center gap-1.5 text-xs font-bold text-carbon mb-1">
                    <Edit3 className="w-4 h-4 text-turquesa-dark" />
                    <span>{t('arco.right_rectification')}</span>
                  </div>
                  <p className="text-xs text-gray-500 leading-relaxed">
                    Corregir datos biográficos de la ficha de identificación con motivo y auditoría obligatoria.
                  </p>
                </div>
                <button
                  onClick={() => setIsRectifyModalOpen(true)}
                  disabled={!canRectify || caseData.person.is_anonymized}
                  className={`w-full py-2 px-3 rounded-lg text-xs font-semibold flex items-center justify-center gap-1.5 shadow-sm transition ${
                    canRectify && !caseData.person.is_anonymized
                      ? 'bg-turquesa text-carbon hover:bg-turquesa-light cursor-pointer'
                      : 'bg-gray-200 text-gray-500 cursor-not-allowed'
                  }`}
                  title={!canRectify ? 'Reservado a Ingreso y Dirección (BV-5.4)' : undefined}
                >
                  <Edit3 className="w-3.5 h-3.5" />
                  <span>{t('arco.btn_rectify')}</span>
                </button>
              </div>

              {/* Oposición */}
              <div className="p-4 rounded-xl border border-gray-200 bg-gray-50/50 flex flex-col justify-between space-y-3">
                <div>
                  <div className="flex items-center gap-1.5 text-xs font-bold text-carbon mb-1">
                    <ShieldAlert className="w-4 h-4 text-amber-500" />
                    <span>{t('arco.right_opposition')}</span>
                  </div>
                  <p className="text-xs text-gray-500 leading-relaxed">
                    Restringir tratamientos secundarios y reportes externos sin afectar auxilio humanitario ni alojamiento.
                  </p>
                </div>
                <button
                  onClick={() => setIsOpposeModalOpen(true)}
                  disabled={!isDirector || caseData.person.is_anonymized}
                  className={`w-full py-2 px-3 rounded-lg text-xs font-semibold flex items-center justify-center gap-1.5 shadow-sm transition ${
                    isDirector && !caseData.person.is_anonymized
                      ? 'bg-amber-100 text-amber-900 hover:bg-amber-200 border border-amber-300 cursor-pointer'
                      : 'bg-gray-200 text-gray-500 cursor-not-allowed'
                  }`}
                  title={!isDirector ? 'Reservado a Dirección (BV-5.5)' : undefined}
                >
                  <ShieldAlert className="w-3.5 h-3.5" />
                  <span>{t('arco.btn_oppose')}</span>
                </button>
              </div>

              {/* Cancelación / Anonimización */}
              <div className="p-4 rounded-xl border border-red-200 bg-red-50/30 flex flex-col justify-between space-y-3">
                <div>
                  <div className="flex items-center gap-1.5 text-xs font-bold text-red-700 mb-1">
                    <Trash2 className="w-4 h-4 text-red-600" />
                    <span>{t('arco.right_cancellation')}</span>
                  </div>
                  <p className="text-xs text-red-600/80 leading-relaxed">
                    Procedimiento irreversible (ADR-0001): Destruye datos identificables, purga bitácoras y preserva esqueleto estadístico.
                  </p>
                </div>
                <button
                  onClick={() => setIsAnonymizeModalOpen(true)}
                  disabled={!isDirector || caseData.person.is_anonymized}
                  className={`w-full py-2 px-3 rounded-lg text-xs font-bold flex items-center justify-center gap-1.5 shadow-sm transition ${
                    isDirector && !caseData.person.is_anonymized
                      ? 'bg-red-600 text-white hover:bg-red-700 cursor-pointer'
                      : 'bg-gray-200 text-gray-500 cursor-not-allowed'
                  }`}
                  title={!isDirector ? 'Reservado a Dirección (ADR-0001 / BV-5.3)' : undefined}
                >
                  <Trash2 className="w-3.5 h-3.5" />
                  <span>
                    {caseData.person.is_anonymized ? 'Anonimizado' : t('arco.btn_cancel')}
                  </span>
                </button>
              </div>
            </div>
          </div>

          {/* Historial de Solicitudes ARCO */}
          <div className="bg-white rounded-2xl p-6 border border-gray-200 shadow-sm space-y-4">
            <div className="border-b border-gray-100 pb-3 flex justify-between items-center">
              <h3 className="text-sm font-bold text-carbon uppercase tracking-wider">
                {t('arco.history_title')}
              </h3>
              <span className="text-xs font-mono text-gray-500">
                {arcoRequests.length} registros
              </span>
            </div>

            {arcoRequests.length === 0 ? (
              <p className="text-xs text-gray-500 italic py-3 text-center">
                {t('arco.history_empty')}
              </p>
            ) : (
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200 text-xs">
                  <thead className="bg-gray-50 text-gray-500 uppercase font-semibold text-xs">
                    <tr>
                      <th className="px-4 py-2.5 text-left">{t('arco.table_type')}</th>
                      <th className="px-4 py-2.5 text-left">{t('arco.table_status')}</th>
                      <th className="px-4 py-2.5 text-left">{t('arco.table_requested_by')}</th>
                      <th className="px-4 py-2.5 text-left">{t('arco.table_reason')}</th>
                      <th className="px-4 py-2.5 text-left">{t('arco.table_date')}</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100 bg-white">
                    {arcoRequests.map((req) => (
                      <tr key={req.id} className="hover:bg-gray-50">
                        <td className="px-4 py-3 font-semibold text-carbon">
                          <span className="px-2 py-0.5 rounded bg-gray-100 border text-xs">
                            {t(`arco.types.${req.request_type}`)}
                          </span>
                        </td>
                        <td className="px-4 py-3">
                          <span className="px-2 py-0.5 rounded bg-emerald-100 text-emerald-800 font-medium text-xs">
                            {t(`arco.statuses.${req.status}`)}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-gray-700">{req.requested_by_name}</td>
                        <td className="px-4 py-3 text-gray-600 max-w-xs truncate" title={req.reason}>
                          {req.reason}
                        </td>
                        <td className="px-4 py-3 text-gray-500 font-mono text-xs">
                          {formatDate(req.received_at)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Modal de Cambio de Estatus Multieje (Regla Dura 7) */}
      {transitioningAxis && (
        <ModalShell onClose={() => setTransitioningAxis(null)} className="fixed inset-0 bg-carbon/50 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-lg w-full overflow-hidden shadow-2xl border border-gray-200">
            <div className="px-6 py-4 bg-carbon text-white flex items-center justify-between">
              <div>
                <h3 className="font-bold text-sm">
                  {t('cases.transition_modal_title')}
                </h3>
                <span className="text-xs text-turquesa font-mono">
                  {transitioningAxis}
                </span>
              </div>
              <button
                onClick={() => setTransitioningAxis(null)}
                aria-label={t('common.close')}
                className="text-gray-300 hover:text-white text-sm p-2"
              >
                ✕
              </button>
            </div>

            <div className="p-6 space-y-4 text-xs">
              {errorMessage && (
                <div className="p-3 bg-alerta-bg text-alerta border border-alerta/30 rounded-xl flex items-start gap-2">
                  <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" />
                  <div>
                    <span className="font-bold">{t('cases.governance_error')}</span>
                    <p>{errorMessage}</p>
                  </div>
                </div>
              )}

              <div>
                <label className="block font-semibold text-carbon mb-1" htmlFor="casede-1">
                  {t('cases.field_target_status')}
                </label>
                <select id="casede-1" name="casede-1" autoComplete="off"
                  value={targetValueCode}
                  onChange={(e) => setTargetValueCode(e.target.value)}
                  className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                >
                  {(statusValues[transitioningAxis] || []).map((val) => (
                    <option key={val.code} value={val.code}>
                      {val.label_es} ({val.code})
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block font-semibold text-carbon mb-1" htmlFor="casede-2">
                  {t('cases.field_reason')}
                </label>
                <textarea id="casede-2" name="casede-2" autoComplete="off"
                  rows={3}
                  required
                  value={transitionReason}
                  onChange={(e) => setTransitionReason(e.target.value)}
                  placeholder={t('cases.field_reason_placeholder')}
                  className="w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa"
                />
              </div>

              <div className="p-3 bg-gray-50 rounded-xl border border-gray-200 text-xs text-gray-500 space-y-1">
                <p className="font-semibold text-carbon">{t('cases.rule7_note')}</p>
                <p>
                  Esta acción cerrará el registro anterior con marca de tiempo actual y abrirá el nuevo estado de manera transaccional. No es posible sobrescribir ni revertir sin dejar un nuevo rastro auditable.
                </p>
              </div>
            </div>

            <div className="px-6 py-4 bg-gray-50 border-t border-gray-200 flex justify-end gap-2 text-xs">
              <button
                type="button"
                onClick={() => setTransitioningAxis(null)}
                className="px-4 py-2 font-medium text-gray-600 hover:bg-gray-100 rounded-lg"
              >
                {t('cases.btn_cancel')}
              </button>
              <button
                type="button"
                onClick={handleConfirmTransition}
                className="px-4 py-2 font-bold text-carbon bg-turquesa hover:bg-turquesa-hover rounded-lg shadow-sm flex items-center gap-1.5"
              >
                <Send className="w-3.5 h-3.5" />
                {t('cases.btn_confirm_transition')}
              </button>
            </div>
          </div>
        </ModalShell>
      )}

      {/* Modal: Nueva Entrada de Bitácora (BV-4.1) */}
      {isNewJournalOpen && onAddJournalEntry && (
        <NewJournalEntryModal
          isOpen={isNewJournalOpen}
          onClose={() => setIsNewJournalOpen(false)}
          caseId={caseData.id}
          caseNumber={caseData.case_number}
          authorUserId={authorUserId}
          authorFullName={authorFullName}
          assignedAreaId={assignedAreaId}
          onEntryCreated={onAddJournalEntry}
        />
      )}

      {/* Modal: Fe de Erratas / Aclaración (BV-4.2) */}
      {clarifyingEntry && onAddClarification && (
        <ClarificationNoteModal
          isOpen={!!clarifyingEntry}
          onClose={() => setClarifyingEntry(null)}
          originalEntry={clarifyingEntry}
          authorUserId={authorUserId}
          authorFullName={authorFullName}
          onSubmitClarification={onAddClarification}
        />
      )}

      {/* Modal: Compartir Entrada (BV-4.3) */}
      {sharingEntry && onShareJournalEntry && (
        <ShareEntryModal
          isOpen={!!sharingEntry}
          onClose={() => setSharingEntry(null)}
          entry={sharingEntry}
          authorUserId={authorUserId}
          authorFullName={authorFullName}
          onSubmitShare={onShareJournalEntry}
        />
      )}

      {/* Modales de Épica E5: Consentimiento y Derechos ARCO */}
      {isConsentModalOpen && onSaveConsent && (
        <ConsentModal
          isOpen={isConsentModalOpen}
          onClose={() => setIsConsentModalOpen(false)}
          caseData={caseData}
          onSaveConsent={onSaveConsent}
        />
      )}

      {isRectifyModalOpen && onRectifyPerson && (
        <RectifyPersonModal
          isOpen={isRectifyModalOpen}
          onClose={() => setIsRectifyModalOpen(false)}
          person={caseData.person}
          onRectify={onRectifyPerson}
        />
      )}

      {isAnonymizeModalOpen && onAnonymizePerson && (
        <AnonymizePersonModal
          isOpen={isAnonymizeModalOpen}
          onClose={() => setIsAnonymizeModalOpen(false)}
          caseData={caseData}
          onAnonymize={onAnonymizePerson}
        />
      )}

      {isOpposeModalOpen && onOpposeSecondary && (
        <OpposeSecondaryTreatmentModal
          isOpen={isOpposeModalOpen}
          onClose={() => setIsOpposeModalOpen(false)}
          caseData={caseData}
          onOppose={onOpposeSecondary}
        />
      )}

      {isAccessExtractModalOpen && (
        <ArcoAccessExtractModal
          isOpen={isAccessExtractModalOpen}
          onClose={() => setIsAccessExtractModalOpen(false)}
          caseData={caseData}
        />
      )}
    </div>
  );
};
