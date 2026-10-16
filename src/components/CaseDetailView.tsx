// CaseDetailView.tsx · el expediente de una persona. Es la pantalla más grande del producto; léela por pestañas.
//
//   axes             estatus en cinco ejes (etapa, acompañamiento, alojamiento, jurídico, registro) y su historia
//   journal          bitácora del caso: filtros, fe de erratas, compartir con otra área (inmutable y privada por defecto)
//   summary          ficha de la persona y del caso: identificación, documentos, idioma y religión, fechas, familia,
//                    necesidades, contexto de ingreso, plan y datos calculados (cada dato sensible en su propio modal)
//   vulnerabilities  marcadores de vulnerabilidad y su detalle
//   subfolios        niñez y adolescencia acompañadas (folio hijo)
//   tasks            tareas ligadas al caso (solo quien opera expedientes)
//   privacy          consentimientos, derechos ARCO y anonimización (qué acciones se ofrecen depende del rol)
//
// Esta vista solo MUESTRA y dispara acciones: cada escritura llega por una `on…` desde `App.tsx` o por `dataApi`, y la base
// la vuelve a validar. Los formularios largos viven aparte, como páginas (`NewJournalEntryPage`, `RectifyPersonPage`…);
// los datos sensibles sueltos, en modales cortos (`SmallFieldModal`, `CatalogItemModal`) y en paneles (`Case…Panel`).
import React, { useEffect, useState } from 'react';
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
  Scale,
  ListChecks
} from 'lucide-react';
import { t, tStored } from '../lib/i18n';
import { 
  CaseWithDetails, 
  RoleName, 
  StatusAxisCode,
  JournalEntry,
  ConsentType,
  ConsentStatus,
  ArcoRequest,
  VulnerabilityMarkerCode
} from '../types/database';
import { VULNERABILITY_CATALOG, countryLabel, itemLabel, freeTextOrNull } from '../lib/catalogs';
import { warningOrdinals } from '../lib/journalTemplates';
import { useCatalog } from '../lib/catalog';
import { useSession } from '../lib/session';
import { ClarificationNoteModal } from './ClarificationNoteModal';
import { ShareEntryModal } from './ShareEntryModal';
import { AnonymizePersonModal } from './AnonymizePersonModal';
import { OpposeSecondaryTreatmentModal } from './OpposeSecondaryTreatmentModal';
import { ArcoAccessExtractModal } from './ArcoAccessExtractModal';
import { ArcoReceiptModal, computeArcoDocket, computeBusinessDaysDeadline } from './ArcoReceiptModal';
import { formatDate, formatDateTime, formatTime } from '../lib/format';
import { ModalShell } from './ModalShell';
import { Tabs } from './Tabs';
import { CaseTasksPanel } from './CaseTasksPanel';
import { StatusHistory } from './StatusHistory';
import { DisabledReason, describedBy } from './DisabledReason';
import { dataApi } from '../lib/data';
import { hasCurrentSensitiveConsent } from '../lib/privacy';
import { useToast } from '../lib/toast';
import { PersonDocumentsPanel } from './PersonDocumentsPanel';
import { MunicipalityName } from './MunicipalityName';
import { CaseDatesPanel } from './CaseDatesPanel';
import { CaseDerivedPanel } from './CaseDerivedPanel';
import { CaseFamilyPanel } from './CaseFamilyPanel';
import { FlexibleDateInput } from './FlexibleDateInput';
import { DatePrecision, startsInFuture, toStoredDate, todayLocalIso } from '../lib/flexDate';
import { SmallFieldModal } from './SmallFieldModal';
import { CatalogItemModal } from './CatalogItemModal';
import { CaseNeedsPanel } from './CaseNeedsPanel';
import { PersonProfilePanel } from './PersonProfilePanel';
import { IntakePlanModal } from './IntakePlanModal';

interface CaseDetailViewProps {
  caseData: CaseWithDetails;
  onBack: () => void;
  activeRole: RoleName;
  assignedAreaCode?: string;
  authorUserId: string;
  authorFullName: string;
  onTransitionStatus: (
    caseId: string, 
    axisCode: StatusAxisCode, 
    newValueCode: string, 
    reason: string,
    /** Fecha del movimiento: obligatoria al pasar a «albergada» o a «salida del albergue» (E14 fase 2b) */
    movement?: { value: string; precision: string }
  ) => void;
  onSelectSubfolio?: (subfolioCase: CaseWithDetails) => void;
  onOpenCase?: (caseNumber: string) => void;
  onStartSubfolio?: () => void;
  onStartJournalEntry?: () => void;
  /** Pestaña con la que se abre el expediente (p. ej. al volver de escribir una entrada) */
  initialTab?: 'axes' | 'journal' | 'privacy';
  onStartRectify?: () => void;
  onStartConsent?: () => void;
  onAddClarification?: (originalEntryId: string, clarificationEntry: JournalEntry) => void;
  onShareJournalEntry?: (entryId: string, toAreaId: string, toAreaName: string, reason: string) => void;
  /** (en uso solo para saber si se ofrece registrar consentimientos) */
  onSaveConsent?: (consent: {
    consent_type: ConsentType;
    status: ConsentStatus;
    is_minor_assent: boolean;
    legal_guardian_name?: string;
    legal_guardian_role?: string;
    authority_letter_ref?: string;
    notes?: string;
  }) => void;
  onAnonymizePerson?: (personId: string, reason: string) => void;
  onOpposeSecondary?: (personId: string, reason: string) => void;
  /** Vuelve a leer lo que RLS permite ver después de escribir (documentos, religión, detalles, referencia) */
  onDataChanged?: () => Promise<void>;
}

export const CaseDetailView: React.FC<CaseDetailViewProps> = ({
  caseData,
  onBack,
  activeRole,
  assignedAreaCode,
  authorUserId,
  authorFullName,
  onTransitionStatus,
  onSelectSubfolio,
  onOpenCase,
  onStartSubfolio,
  onStartJournalEntry,
  initialTab,
  onStartRectify,
  onStartConsent,
  onAddClarification,
  onShareJournalEntry,
  onSaveConsent,
  onAnonymizePerson,
  onOpposeSecondary,
  onDataChanged,
}) => {
  const toast = useToast();
  const { statusAxes, statusValues, organizationName, organizationInfo, geoStates, intakeChannels, entryRoutes, catalogItems } = useCatalog();
  const legalValues = statusValues.legal_status ?? [];
  const [activeTab, setActiveTab] = useState<'axes' | 'journal' | 'summary' | 'vulnerabilities' | 'subfolios' | 'privacy' | 'tasks'>(initialTab ?? 'axes');
  // E14 fase 1: datos cortos que se editan en un modal de un solo campo
  const [field, setField] = useState<null | { kind: 'religion' } | { kind: 'language' } | { kind: 'plan' } | { kind: 'legacy' } | { kind: 'marker'; code: VulnerabilityMarkerCode }>(null);
  const [transitioningAxis, setTransitioningAxis] = useState<StatusAxisCode | null>(null);
  // Ingreso y egreso del albergue llevan la fecha del movimiento: por defecto hoy, y se puede cambiar (E14 fase 2b)
  const [movementPrecision, setMovementPrecision] = useState<DatePrecision>('day');
  const [movementRaw, setMovementRaw] = useState(todayLocalIso());
  const [targetValueCode, setTargetValueCode] = useState<string>('');
  const [transitionReason, setTransitionReason] = useState<string>('');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Estados para Bitácora (Épica E4)
  const [journalFilter, setJournalFilter] = useState<'all' | 'my_area' | 'shared' | 'work_notes'>('all');
  const [clarifyingEntry, setClarifyingEntry] = useState<JournalEntry | null>(null);
  const [sharingEntry, setSharingEntry] = useState<JournalEntry | null>(null);
  const [expandedSuperseded, setExpandedSuperseded] = useState<Record<string, boolean>>({});

  // Estados para Privacidad y Derechos ARCO (Épica E5)
  const [isAnonymizeModalOpen, setIsAnonymizeModalOpen] = useState<boolean>(false);
  const [isOpposeModalOpen, setIsOpposeModalOpen] = useState<boolean>(false);
  const [isAccessExtractModalOpen, setIsAccessExtractModalOpen] = useState<boolean>(false);
  const [receiptRequest, setReceiptRequest] = useState<ArcoRequest | null>(null);

  const hasUnaccompaniedChild = caseData.vulnerabilities.some(
    (v) => v.marker_code === 'unaccompanied_child'
  );

  // D-12 / P-04: Auditoría de lectura de expediente registrada por la base
  useEffect(() => {
    if (caseData?.id) {
      void dataApi.readCaseDetail(caseData.id).catch(() => {
        // La lectura continúa si falla la auditoría silenciosa
      });
    }
  }, [caseData?.id]);

  const isDirector = activeRole === 'director';
  const isLegalCaseworker = activeRole === 'caseworker' && assignedAreaCode === 'legal';
  const canWriteJournal = activeRole === 'caseworker' || activeRole === 'intake_officer' || activeRole === 'director';
  // Aclarar o compartir una entrada: su autoría, las personas de su área y Dirección (la base lo exige igual)
  const myAreaIds = useSession().user?.areaIds ?? [];
  const canActOnEntry = (entry: JournalEntry) =>
    isDirector || entry.author_user_id === authorUserId || myAreaIds.includes(entry.area_id);
  // Tareas ligadas: las crea quien opera expedientes (el rol de sólo lectura no)
  const canLinkTasks = canWriteJournal;
  // Subfolio (BV-3.2): lo abren ingreso y dirección, sobre un caso principal y abierto
  const canCreateSubfolio =
    !!onStartSubfolio && (activeRole === 'intake_officer' || activeRole === 'director') && !caseData.parent_case_id && !caseData.closed_at;
  const canManageConsent = activeRole === 'intake_officer' || activeRole === 'caseworker' || activeRole === 'director';
  const canRectify = activeRole === 'intake_officer' || activeRole === 'director';
  // E14: los datos sensibles nuevos solo se registran con consentimiento sensible vigente (D-14)
  const sensitiveOk = hasCurrentSensitiveConsent(caseData.consents);
  const canEditExtra = canWriteJournal && !!onDataChanged && !caseData.person.is_anonymized;
  // Por qué un derecho no está disponible: por rol, o porque la persona ya fue anonimizada (texto visible, no solo un tooltip)
  const arcoReason = (allowed: boolean, restrictedKey: string): string | null =>
    !allowed ? t(restrictedKey) : caseData.person.is_anonymized ? t('arco.person_anonymized') : null;

  const consents = caseData.consents || [];
  const arcoRequests = caseData.arco_requests || [];
  const hasSensitiveDataConsent = consents.some(
    (c) => c.consent_type === 'sensitive_data' && c.status === 'granted'
  );

  const journalEntries = caseData.journal_entries || [];
  const warningNumbers = warningOrdinals(journalEntries);

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
    setMovementPrecision('day');
    setMovementRaw(todayLocalIso());
    const possibleValues = statusValues[axisCode] || [];
    const firstNonCurrent = possibleValues.find(v => v.code !== caseData.statuses[axisCode]?.valueCode);
    setTargetValueCode(firstNonCurrent ? firstNonCurrent.code : (possibleValues[0]?.code || ''));
  };

  // «Albergada» (ingreso) y «salida del albergue» (egreso) llevan la fecha del movimiento
  const needsMovementDate = transitioningAxis === 'shelter_status' && (targetValueCode === 'sheltered' || targetValueCode === 'left_shelter');

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

    if (needsMovementDate) {
      const stored = toStoredDate(movementPrecision, movementRaw);
      if (!stored) { setErrorMessage(t('dates.reason_missing_value')); return; }
      if (startsInFuture(stored)) { setErrorMessage(t('dates.reason_future')); return; }
      onTransitionStatus(caseData.id, transitioningAxis, targetValueCode, transitionReason.trim(), { value: stored, precision: movementPrecision });
    } else {
      onTransitionStatus(caseData.id, transitioningAxis, targetValueCode, transitionReason.trim());
    }
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
            {caseData.statuses.engagement_status?.label || t('common.not_recorded')}
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
              <span className="text-xs bg-turquesa/15 text-turquesa-dark px-2 py-0.5 rounded font-bold uppercase tracking-wider">
                {t('cases.badge_subfolio')}
              </span>
            )}
            {hasUnaccompaniedChild && (
              <span className="text-xs bg-alerta-dark text-white px-2 py-0.5 rounded font-bold uppercase tracking-wider">
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
            <span>{countryLabel(caseData.person.nationality_country_id, caseData.person.other_nationality) ?? t('cases.not_specified')}</span>
            <span>·</span>
            <span>{t('cases.opened_label')} {formatDate(caseData.opened_at)}</span>
          </div>
        </div>

        <div className="flex items-center gap-2">
          {caseData.parentCaseNumber && (
            <div className="text-xs bg-gray-50 p-2.5 rounded-xl border border-gray-200">
              <span className="text-gray-500 block">{t('cases.subfolio_of')}</span>
              {onOpenCase ? (
                <button
                  type="button"
                  onClick={() => onOpenCase(caseData.parentCaseNumber as string)}
                  aria-label={`${t('subfolio.open_parent')}: ${caseData.parentCaseNumber}`}
                  className="font-mono font-bold text-carbon underline decoration-turquesa underline-offset-2 hover:text-turquesa-dark"
                >
                  {caseData.parentCaseNumber}
                </button>
              ) : (
                <span className="font-mono font-bold text-carbon">{caseData.parentCaseNumber}</span>
              )}
            </div>
          )}
          {canCreateSubfolio && (
            <button
              type="button"
              onClick={onStartSubfolio}
              className="inline-flex min-h-11 items-center gap-2 rounded-lg border border-gray-300 bg-white px-4 text-sm font-semibold text-carbon hover:bg-gray-50"
            >
              <Users className="h-4 w-4" aria-hidden="true" />
              {t('cases.btn_new_subfolio')}
            </button>
          )}
        </div>
      </div>

      {/* Alerta de Niñez No Acompañada */}
      {hasUnaccompaniedChild && (
        <div className="bg-alerta-bg border border-alerta/30 rounded-2xl p-4 flex items-start gap-3 text-alerta-dark">
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
          { id: 'axes', label: t('cases.tabs_short.axes'), icon: <Layers className="h-4 w-4" aria-hidden="true" /> },
          { id: 'journal', label: `${t('cases.tabs_short.journal')} (${journalEntries.length})`, icon: <BookOpen className="h-4 w-4" aria-hidden="true" /> },
          { id: 'summary', label: t('cases.tabs_short.summary'), icon: <FileText className="h-4 w-4" aria-hidden="true" /> },
          { id: 'vulnerabilities', label: `${t('cases.tabs_short.vulnerabilities')} (${caseData.vulnerabilities.length})`, icon: <AlertCircle className="h-4 w-4" aria-hidden="true" /> },
          ...((caseData.subfolios && caseData.subfolios.length > 0) || canCreateSubfolio
            ? [{ id: 'subfolios', label: `${t('cases.tabs_short.subfolios')} (${caseData.subfolios?.length ?? 0})`, icon: <Users className="h-4 w-4" aria-hidden="true" /> }]
            : []),
          ...(canLinkTasks ? [{ id: 'tasks', label: t('tasks.case.tab'), icon: <ListChecks className="h-4 w-4" aria-hidden="true" /> }] : []),
          {
            id: 'privacy',
            label: t('cases.tabs_short.privacy'),
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
                        {currentStatus?.label || t('cases.status_unassigned')}
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
                        <p className="italic">"{tStored(currentStatus.reason)}"</p>
                      </div>
                    )}
                  </div>

                  <div className="mt-5 pt-3 border-t border-gray-100 flex items-center justify-end">
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
                onClick={onStartJournalEntry}
                className="flex items-center gap-2 rounded-lg bg-turquesa px-4 py-2 text-xs font-bold text-carbon shadow-sm hover:opacity-90"
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
                        <span className="rounded-md bg-turquesa/10 px-2.5 py-1 text-xs font-semibold text-turquesa-dark">
                          {t(`journal.types.${entry.entry_type_key}`)}
                        </span>
                        {entry.entry_type_key === 'warning' && warningNumbers.has(entry.id) && (
                          <span className="rounded-md bg-amber-100 px-2.5 py-1 text-xs font-bold text-amber-800">
                            {warningNumbers.get(entry.id)! <= 3
                              ? t(`journal.warning_badge_${warningNumbers.get(entry.id)}`)
                              : t('journal.warning_badge_n').replace('{n}', String(warningNumbers.get(entry.id)))}
                          </span>
                        )}
                        {entry.service_line_item_id && (
                          <span className="rounded-md bg-gray-100 px-2.5 py-1 text-xs font-semibold text-gray-700">
                            {itemLabel(catalogItems, entry.service_line_item_id, null)}
                          </span>
                        )}
                        {entry.source === 'import' && (
                          <span
                            title={t('journal.imported_author').replace('{author}', entry.source_author_label ?? '')}
                            className="rounded-md bg-violet-100 px-2.5 py-1 text-xs font-bold text-violet-800"
                          >
                            {t('journal.imported_badge')}
                          </span>
                        )}

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
                          <span className="flex items-center gap-1 rounded-md bg-gray-100 px-2 py-0.5 text-xs font-medium text-gray-600">
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
                          className="flex min-h-9 items-center gap-1 px-2 font-bold text-amber-800 underline hover:text-amber-950"
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
                      {!isSuperseded && canWriteJournal && canActOnEntry(entry) && (
                        <div className="flex items-center gap-2">
                          {/* Botón de Fe de Erratas */}
                          <button
                            onClick={() => setClarifyingEntry(entry)}
                            className="flex items-center gap-1 rounded-md border border-gray-300 px-2.5 py-1 text-xs font-medium text-gray-700 hover:bg-gray-50 hover:text-carbon"
                          >
                            <CornerDownRight className="h-3 w-3 text-turquesa-dark" />
                            <span>{t('journal.btn_clarify')}</span>
                          </button>

                          {/* Botón de Compartir si es privada */}
                          {!isShared && !entry.is_work_note && (
                            <button
                              onClick={() => setSharingEntry(entry)}
                              className="flex items-center gap-1 rounded-md bg-blue-50 px-2.5 py-1 text-xs font-bold text-blue-700 hover:bg-blue-100"
                            >
                              <Share2 className="h-3 w-3" />
                              <span>{t('journal.btn_share')}</span>
                            </button>
                          )}
                          {entry.is_work_note && (
                            <span className="text-xs text-gray-500">{t('journal.work_note_no_share')}</span>
                          )}
                        </div>
                      )}
                      {/* Sin acciones: se dice por qué, para que no parezca un fallo */}
                      {!isSuperseded && canWriteJournal && !canActOnEntry(entry) && (
                        <span className="text-xs text-gray-500">{t('journal.no_actions_hint')}</span>
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
                  {caseData.person.preferred_name || t('cases.not_specified')}
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
                  {countryLabel(caseData.person.nationality_country_id, caseData.person.other_nationality) ?? t('cases.not_specified')}
                </span>
              </div>
              <div>
                <span className="text-gray-500 block">{t('cases.field_language')}</span>
                <span className="font-semibold text-carbon text-sm">
                  {itemLabel(catalogItems, caseData.person.primary_language_item_id, caseData.person.other_language) ?? t('cases.not_specified')}
                </span>
                {canEditExtra && (
                  <button type="button" onClick={() => setField({ kind: 'language' })} className="mt-1 inline-flex min-h-11 items-center rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50">
                    {caseData.person.primary_language_item_id || caseData.person.other_language ? t('case_extra.change') : t('diccionarios.language_register')}
                  </button>
                )}
                {canEditExtra && !sensitiveOk && <p className="mt-1 text-sm text-gray-700">{t('diccionarios.only_no_response')}</p>}
              </div>
              <div>
                <span className="text-gray-500 block">{t('cases.field_phone')}</span>
                <span className="font-semibold text-carbon text-sm">
                  {caseData.person.phone_number || t('cases.no_phone')}
                </span>
              </div>
              <div>
                <span className="text-gray-500 block">{t('case_extra.religion_label')}</span>
                <span className="font-semibold text-carbon text-sm">
                  {itemLabel(catalogItems, caseData.person.religion_item_id, caseData.person.religion_detail) ?? t('case_extra.religion_none')}
                </span>
                {canRectify && canEditExtra && (
                  <button type="button" onClick={() => setField({ kind: 'religion' })} className="mt-1 inline-flex min-h-11 items-center rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50">
                    {caseData.person.religion_item_id || caseData.person.religion_detail ? t('case_extra.change') : t('case_extra.religion_register')}
                  </button>
                )}
                {canRectify && canEditExtra && !sensitiveOk && <p className="mt-1 text-sm text-gray-700">{t('diccionarios.only_no_response')}</p>}
              </div>
            </div>
          </div>

          <PersonDocumentsPanel
            personId={caseData.titular_person_id}
            documents={caseData.documents ?? []}
            canEdit={canEditExtra}
            onChanged={onDataChanged ?? (async () => {})}
          />

          <PersonProfilePanel
            caseData={caseData}
            canEdit={canEditExtra}
            sensitiveOk={sensitiveOk}
            onChanged={onDataChanged ?? (async () => {})}
          />

          <CaseNeedsPanel
            caseId={caseData.id}
            items={catalogItems.filter((i) => i.catalog === 'specific_need')}
            currentIds={caseData.needs ?? []}
            sensitiveOk={sensitiveOk}
            canEdit={canEditExtra}
            onChanged={onDataChanged ?? (async () => {})}
          />

          <CaseFamilyPanel
            caseId={caseData.id}
            family={caseData.family}
            canEdit={canEditExtra}
            onChanged={onDataChanged ?? (async () => {})}
          />

          <CaseDatesPanel
            caseId={caseData.id}
            dates={caseData.dates ?? []}
            legacyEntryText={freeTextOrNull(caseData.entry_date_str)}
            canEdit={canEditExtra}
            onChanged={onDataChanged ?? (async () => {})}
          />

          <CaseDerivedPanel caseData={caseData} />

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
                <span className="text-gray-500 block">{t('cases.field_family_travel')}</span>
                <span className="font-semibold text-carbon text-sm">
                  {caseData.travels_with_family == null ? t('common.not_recorded') : caseData.travels_with_family ? t('common.yes') : t('common.no')}
                </span>
              </div>
              <div>
                <span className="text-gray-500 block">{t('cases.field_state')}</span>
                <span className="font-semibold text-carbon text-sm">
                  {geoStates.find((s) => Number(s.cve_ent) === caseData.intake_state_id)?.name ?? t('common.not_recorded')}
                </span>
              </div>
              <div>
                <span className="text-gray-500 block">{t('cases.field_municipality')}</span>
                <span className="font-semibold text-carbon text-sm">
                  <MunicipalityName municipalityKey={caseData.intake_municipality_key} />
                </span>
              </div>
              <div>
                <span className="text-gray-500 block">{t('cases.field_channel')}</span>
                <span className="font-semibold text-carbon text-sm">
                  {intakeChannels.find((c) => c.code === caseData.intake_channel_id)?.label_es ?? t('common.not_recorded')}
                </span>
              </div>
              <div>
                <span className="text-gray-500 block">{t('cases.field_route')}</span>
                <span className="font-semibold text-carbon text-sm">
                  {entryRoutes.find((r) => r.code === caseData.entry_route_id)?.label_es ?? t('common.not_recorded')}
                </span>
              </div>
              <div>
                <span className="text-gray-500 block">{t('plan.label')}</span>
                <span className="font-semibold text-carbon text-sm">
                  {legalValues.find((v) => v.id === caseData.intake_plan_value_id)?.label_es ?? t('common.not_recorded')}
                </span>
                {canEditExtra && (
                  <button type="button" onClick={() => setField({ kind: 'plan' })} className="mt-1 inline-flex min-h-11 items-center rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50">
                    {caseData.intake_plan_value_id ? t('case_extra.change') : t('plan.register')}
                  </button>
                )}
              </div>
              <div>
                <span className="text-gray-500 block">{t('case_extra.legacy_label')}</span>
                <span className="font-mono font-semibold text-carbon text-sm">
                  {caseData.legacy_reference || t('case_extra.legacy_none')}
                </span>
                {canEditExtra && (
                  <button type="button" onClick={() => setField({ kind: 'legacy' })} className="mt-1 inline-flex min-h-11 items-center rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50">
                    {caseData.legacy_reference ? t('case_extra.change') : t('case_extra.legacy_register')}
                  </button>
                )}
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
              {t('cases.markers_subtitle')}
            </p>
          </div>

          {caseData.vulnerabilities.length === 0 ? (
            <div className="text-xs text-gray-500 italic p-4 text-center">
              {t('cases.no_markers')}
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
                        <AlertCircle className="w-4 h-4 text-alerta-dark flex-shrink-0" />
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
                      {canEditExtra && (sensitiveOk ? (
                        <button type="button" onClick={() => setField({ kind: 'marker', code: v.marker_code })} className="mt-1 inline-flex min-h-11 items-center rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50">
                          {v.notes ? t('case_extra.marker_detail_edit') : t('case_extra.marker_detail_add')}
                        </button>
                      ) : (
                        <p className="mt-2 text-sm text-gray-700">{t('case_extra.needs_sensitive_consent')}</p>
                      ))}
                    </div>
                    <div className="mt-3 pt-2 border-t border-gray-200/60 text-xs text-gray-500 flex items-center justify-between">
                      <span>{t('cases.affirmed_by')} {v.affirmed_by_name ?? '—'}</span>
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
              {t('cases.subfolios_subtitle')}
            </p>
          </div>

          {(caseData.subfolios?.length ?? 0) === 0 && <p className="text-xs text-gray-600">{t('subfolio.no_subfolios')}</p>}
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
                    aria-label={`${t('cases.tab_subfolios')}: ${sub.case_number}`}
                    className="p-2 text-carbon hover:text-turquesa-dark"
                  >
                    <ChevronRight className="w-5 h-5" />
                  </button>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Tab: Tareas ligadas al caso (Épica E7, BV-7.16) */}
      {activeTab === 'tasks' && canLinkTasks && <CaseTasksPanel caseId={caseData.id} caseNumber={caseData.case_number} />}

      {/* Tab 6: Privacidad, Consentimientos y Derechos ARCO (Épica E5) */}
      {activeTab === 'privacy' && (
        <div className="space-y-6">
          {/* Header Card */}
          <div className="bg-white rounded-2xl p-6 border border-gray-200 shadow-sm space-y-4">
            <div className="flex flex-wrap items-center justify-between gap-4 border-b border-gray-100 pb-4">
              <div>
                <div className="flex items-center gap-2">
                  <ShieldCheck className="w-5 h-5 text-turquesa-dark" />
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
                    onClick={onStartConsent}
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
                        {consentItem ? t(`arco.consent_status.${consentItem.status}`) : t('arco.consent_pending')}
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
                        {t('arco.no_record')}
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
                    {t('arco.access_desc')}
                  </p>
                </div>
                <DisabledReason id="arco-acceso" reason={isDirector ? null : t('arco.reserved_director')} />
                <button
                  onClick={() => setIsAccessExtractModalOpen(true)}
                  disabled={!isDirector}
                  {...describedBy('arco-acceso', isDirector ? null : 'x')}
                  className={`w-full py-2 px-3 rounded-lg text-xs font-semibold flex items-center justify-center gap-1.5 shadow-sm transition ${
                    isDirector
                      ? 'bg-carbon text-white hover:bg-carbon-muted cursor-pointer'
                      : 'bg-gray-200 text-gray-500 cursor-not-allowed'
                  }`}
                  title={!isDirector ? t('arco.reserved_director') : undefined}
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
                    {t('arco.rectify_desc')}
                  </p>
                </div>
                <DisabledReason id="arco-rectificar" reason={arcoReason(canRectify, 'arco.reserved_intake_director')} />
                <button
                  onClick={onStartRectify}
                  disabled={!canRectify || caseData.person.is_anonymized}
                  {...describedBy('arco-rectificar', arcoReason(canRectify, 'arco.reserved_intake_director'))}
                  className={`w-full py-2 px-3 rounded-lg text-xs font-semibold flex items-center justify-center gap-1.5 shadow-sm transition ${
                    canRectify && !caseData.person.is_anonymized
                      ? 'bg-turquesa text-carbon hover:bg-turquesa-light cursor-pointer'
                      : 'bg-gray-200 text-gray-500 cursor-not-allowed'
                  }`}
                  title={!canRectify ? t('arco.reserved_intake_director') : undefined}
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
                    {t('arco.oppose_desc')}
                  </p>
                </div>
                <DisabledReason id="arco-oposicion" reason={arcoReason(isDirector, 'arco.reserved_director')} />
                <button
                  onClick={() => setIsOpposeModalOpen(true)}
                  disabled={!isDirector || caseData.person.is_anonymized}
                  {...describedBy('arco-oposicion', arcoReason(isDirector, 'arco.reserved_director'))}
                  className={`w-full py-2 px-3 rounded-lg text-xs font-semibold flex items-center justify-center gap-1.5 shadow-sm transition ${
                    isDirector && !caseData.person.is_anonymized
                      ? 'bg-amber-100 text-amber-900 hover:bg-amber-200 border border-amber-300 cursor-pointer'
                      : 'bg-gray-200 text-gray-500 cursor-not-allowed'
                  }`}
                  title={!isDirector ? t('arco.reserved_director') : undefined}
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
                  <p className="text-xs text-red-700 leading-relaxed">
                    {t('arco.cancel_desc')}
                  </p>
                </div>
                <DisabledReason id="arco-anonimizar" reason={arcoReason(isDirector, 'arco.reserved_director')} />
                <button
                  onClick={() => setIsAnonymizeModalOpen(true)}
                  disabled={!isDirector || caseData.person.is_anonymized}
                  {...describedBy('arco-anonimizar', arcoReason(isDirector, 'arco.reserved_director'))}
                  className={`w-full py-2 px-3 rounded-lg text-xs font-bold flex items-center justify-center gap-1.5 shadow-sm transition ${
                    isDirector && !caseData.person.is_anonymized
                      ? 'bg-red-600 text-white hover:bg-red-700 cursor-pointer'
                      : 'bg-gray-200 text-gray-500 cursor-not-allowed'
                  }`}
                  title={!isDirector ? t('arco.reserved_director') : undefined}
                >
                  <Trash2 className="w-3.5 h-3.5" />
                  <span>
                    {caseData.person.is_anonymized ? t('arco.anonymized_label') : t('arco.btn_cancel')}
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
                {t('arco.records_count').replace('{n}', String(arcoRequests.length))}
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
                      <th className="px-4 py-2.5 text-left">{t('arco.table_docket')}</th>
                      <th className="px-4 py-2.5 text-left">{t('arco.table_type')}</th>
                      <th className="px-4 py-2.5 text-left">{t('arco.table_status')}</th>
                      <th className="px-4 py-2.5 text-left">{t('arco.table_requested_by')}</th>
                      <th className="px-4 py-2.5 text-left">{t('arco.table_reason')}</th>
                      <th className="px-4 py-2.5 text-left">{t('arco.table_date')}</th>
                      <th className="px-4 py-2.5 text-left">{t('arco.table_deadline')}</th>
                      <th className="px-4 py-2.5 text-right">{t('arco.table_actions')}</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100 bg-white">
                    {arcoRequests.map((req) => {
                      const docket = computeArcoDocket(req, caseData.organization_id?.slice(0, 3) || 'BV');
                      const deadline = computeBusinessDaysDeadline(req.received_at, 20);
                      return (
                        <tr key={req.id} className="hover:bg-gray-50">
                          <td className="px-4 py-3 font-mono font-bold text-carbon text-xs">
                            {docket}
                          </td>
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
                          <td className="px-4 py-3 text-gray-700 font-mono text-xs">
                            {formatDate(deadline)}
                          </td>
                          <td className="px-4 py-3 text-right">
                            <button
                              type="button"
                              onClick={() => setReceiptRequest(req)}
                              className="inline-flex items-center gap-1 px-2.5 py-1 rounded-lg bg-white border border-gray-300 text-xs font-semibold text-carbon shadow-2xs hover:bg-gray-50"
                            >
                              <FileText className="w-3.5 h-3.5 text-turquesa-dark" />
                              <span>{t('arco.receipt_btn')}</span>
                            </button>
                          </td>
                        </tr>
                      );
                    })}
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
                <div className="p-3 bg-alerta-bg text-alerta-dark border border-alerta/30 rounded-xl flex items-start gap-2">
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

              {needsMovementDate && (
                <div>
                  <FlexibleDateInput
                    id="casede-date"
                    label={targetValueCode === 'sheltered' ? t('dates.kind.shelter_entry') : t('dates.kind.shelter_exit')}
                    precision={movementPrecision}
                    value={movementRaw}
                    onChange={(p, v) => { setMovementPrecision(p); setMovementRaw(v); }}
                    collapsible
                    problem={(() => { const s = toStoredDate(movementPrecision, movementRaw); return s && startsInFuture(s) ? t('dates.reason_future') : null; })()}
                  />
                  <p className="mt-1 text-gray-600">{t('dates.movement_hint')}</p>
                </div>
              )}

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
                <p>{t('cases.rule7_body')}</p>
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

      {/* E14 fase 4a: religión e idioma son un valor del diccionario con su detalle */}
      {(field?.kind === 'religion' || field?.kind === 'language') && onDataChanged && (
        <CatalogItemModal
          title={field.kind === 'religion' ? t('case_extra.religion_title') : t('diccionarios.language_title')}
          hint={field.kind === 'religion' ? t('diccionarios.religion_hint') : t('diccionarios.language_hint')}
          items={catalogItems.filter((i) => i.catalog === field.kind)}
          sensitiveOk={sensitiveOk}
          initialItemId={field.kind === 'religion' ? caseData.person.religion_item_id ?? null : caseData.person.primary_language_item_id ?? null}
          initialDetail={(field.kind === 'religion' ? caseData.person.religion_detail : caseData.person.other_language) ?? ''}
          onSubmit={async (itemId, detail, reason) => {
            if (field.kind === 'religion') await dataApi.setPersonReligion(caseData.titular_person_id, itemId, detail, reason);
            else await dataApi.setPersonLanguage(caseData.titular_person_id, itemId, detail, reason);
            toast.success(t('case_extra.saved'));
            await onDataChanged();
          }}
          onClose={() => setField(null)}
        />
      )}

      {field?.kind === 'plan' && onDataChanged && (
        <IntakePlanModal
          values={legalValues}
          initialValueId={caseData.intake_plan_value_id ?? null}
          onSubmit={async (valueId, reason) => {
            await dataApi.setCaseIntakePlan(caseData.id, valueId, reason);
            toast.success(t('case_extra.saved'));
            await onDataChanged();
          }}
          onClose={() => setField(null)}
        />
      )}

      {/* E14 fase 1: referencia heredada y detalle de un marcador (un campo cada uno) */}
      {field && field.kind !== 'religion' && field.kind !== 'language' && field.kind !== 'plan' && onDataChanged && (() => {
        const markerNotes = field.kind === 'marker' ? caseData.vulnerabilities.find((v) => v.marker_code === field.code)?.notes ?? '' : '';
        const cfg = field.kind === 'legacy'
            ? { title: t('case_extra.legacy_title'), hint: t('case_extra.legacy_hint'), label: t('case_extra.legacy_label'), initial: caseData.legacy_reference ?? '', max: 120, multiline: false }
            : { title: t('case_extra.marker_detail_title'), hint: t('case_extra.marker_detail_hint'), label: t('case_extra.marker_detail_label'), initial: markerNotes, max: 500, multiline: true };
        return (
          <SmallFieldModal
            title={cfg.title}
            hint={cfg.hint}
            label={cfg.label}
            initialValue={cfg.initial}
            maxLength={cfg.max}
            multiline={cfg.multiline}
            reasonWhenChanged={field.kind !== 'marker' && cfg.initial !== ''}
            allowClear
            onSubmit={async (value, reason) => {
              if (field.kind === 'legacy') await dataApi.setCaseLegacyReference(caseData.id, value, reason);
              else await dataApi.setMarkerDetail(caseData.id, field.code, value);
              toast.success(t('case_extra.saved'));
              await onDataChanged();
            }}
            onClose={() => setField(null)}
          />
        );
      })()}

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

      {receiptRequest && (
        <ArcoReceiptModal
          isOpen={!!receiptRequest}
          onClose={() => setReceiptRequest(null)}
          arcoRequest={receiptRequest}
          caseData={caseData}
          organizationName={organizationName}
          organizationPrefix={caseData.organization_id?.slice(0, 3) || 'BV'}
          organizationInfo={organizationInfo}
        />
      )}
    </div>
  );
};
