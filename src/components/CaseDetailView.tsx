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
  FileText, 
  Users, 
  ChevronRight, 
  Send, 
  Lock,
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
import { QuickJournalCapture } from './QuickJournalCapture';
import { CaseAuthorizationsPanel } from './CaseAuthorizationsPanel';
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
import { SocialFichaPanel } from './SocialFichaPanel';
import { IntakePlanModal } from './IntakePlanModal';
import { PersonAvatar } from './PersonAvatar';

interface CaseDetailViewProps {
  caseData: CaseWithDetails;
  onBack: () => void;
  activeRole: RoleName;
  /** Permisos de la cuenta (`fn_my_capabilities`). */
  capabilities?: string[];
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
  capabilities = [],
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
  // Captura rápida de bitácora: en celular empieza plegada (en escritorio siempre está a la vista)
  const [quickOpen, setQuickOpen] = useState(false);
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
  const canChangeLegal = capabilities.includes('change_legal_status');
  const canWriteJournal = activeRole === 'caseworker' || activeRole === 'intake_officer' || activeRole === 'director';
  // Aclarar o compartir una entrada: su autoría, las personas de su área y Dirección (la base lo exige igual)
  const myAreaIds = useSession().user?.areaIds ?? [];
  const canActOnEntry = (entry: JournalEntry) =>
    isDirector || entry.author_user_id === authorUserId || myAreaIds.includes(entry.area_id);
  // Tareas ligadas: las crea quien opera expedientes (el rol de sólo lectura no)
  const canLinkTasks = canWriteJournal;
  // Subfolio (BV-3.2): lo abren ingreso y dirección, sobre un caso principal y abierto
  const canCreateSubfolio =
    !!onStartSubfolio && capabilities.includes('open_cases') && !caseData.parent_case_id && !caseData.closed_at;
  const canManageConsent = activeRole === 'intake_officer' || activeRole === 'caseworker' || activeRole === 'director';
  const canRectify = capabilities.includes('rectify_person_data');
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
    if (transitioningAxis === 'legal_status' && !canChangeLegal) {
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

  // Columna persistente: ficha básica, estatus vigente y alertas de vulnerabilidad (lo que se consulta todo el día)
  const docKeys = caseData.person.identity_documents_presented ?? null;
  const docLabel = (k: string) => catalogItems.find((i) => i.catalog === 'identity_document' && i.key === k)?.label_es ?? k;
  const activeMarkers = caseData.vulnerabilities;
  // La ficha, el estatus y las alertas se dibujan en la columna de escritorio; en celular, estatus y alertas van en un resumen siempre visible y la ficha en un acordeón.
  // Cada dibujo lleva su prefijo para que no se repitan los id
  const fichaSection = (idp: string) => (
      <section aria-labelledby={`${idp}-ficha`} className="space-y-3 rounded-2xl border border-gray-200 bg-white p-4">
        <h3 id={`${idp}-ficha`} className="text-sm font-bold uppercase tracking-wider text-carbon">{t('cases.sheet.title')}</h3>
        <PersonAvatar photoConsent={caseData.photo_consent} />
        <dl className="space-y-2 text-sm">
          <div>
            <dt className="text-gray-700">{t('cases.sheet.docs')}</dt>
            <dd className="font-semibold text-carbon">
              {docKeys == null ? t('common.not_recorded') : (
                <ul className="mt-1 flex flex-wrap gap-1.5">
                  {docKeys.map((k) => <li key={k} className="rounded-md bg-claro px-2 py-0.5 text-xs font-semibold text-carbon">{docLabel(k)}</li>)}
                </ul>
              )}
            </dd>
          </div>
          <div><dt className="text-gray-700">{t('cases.sheet.phone1')}</dt><dd className="font-semibold text-carbon">{freeTextOrNull(caseData.person.phone_number) ?? t('common.not_recorded')}</dd></div>
          <div>
            <dt className="text-gray-700">{t('cases.sheet.phone2')}</dt>
            <dd className="font-semibold text-carbon">
              {freeTextOrNull(caseData.person.secondary_phone)
                ? `${caseData.person.secondary_phone}${caseData.person.secondary_phone_label ? ` (${t(`intake.phone2_labels.${caseData.person.secondary_phone_label}`)})` : ''}`
                : t('common.not_recorded')}
            </dd>
          </div>
          <div><dt className="text-gray-700">{t('cases.sheet.nationality')}</dt><dd className="font-semibold text-carbon">{countryLabel(caseData.person.nationality_country_id, caseData.person.other_nationality) ?? t('common.not_recorded')}</dd></div>
          <div>
            <dt className="text-gray-700">{t('cases.sheet.intake')}</dt>
            <dd className="font-semibold text-carbon">{formatDate(caseData.opened_at)} ({t(`indicators.window.${caseData.intake_window_type}`)})</dd>
          </div>
        </dl>
      </section>
  );
  const statusSection = (idp: string) => (
      <section aria-labelledby={`${idp}-estatus`} className="space-y-2 rounded-2xl border border-gray-200 bg-white p-4">
        <h3 id={`${idp}-estatus`} className="text-sm font-bold uppercase tracking-wider text-carbon">{t('cases.status_now')}</h3>
        <ul className="space-y-1.5 text-sm">
          {statusAxes.map((axis) => (
            <li key={axis.id} className="flex flex-wrap items-baseline justify-between gap-2">
              <span className="text-gray-700">{axis.label_es}</span>
              <span className="font-semibold text-carbon">{caseData.statuses[axis.code]?.label || t('common.not_recorded')}</span>
            </li>
          ))}
        </ul>
      </section>
  );
  const alertsSection = (idp: string) => (
      <section aria-labelledby={`${idp}-alertas`} className="space-y-2 rounded-2xl border border-gray-200 bg-white p-4">
        <h3 id={`${idp}-alertas`} className="text-sm font-bold uppercase tracking-wider text-carbon">{t('cases.alerts')}</h3>
        {activeMarkers.length === 0 ? (
          <p className="text-sm text-gray-700">{t('cases.alerts_none')}</p>
        ) : (
          <ul className="flex flex-wrap gap-1.5">
            {activeMarkers.map((m) => (
              <li key={m.id} className="rounded-md bg-alerta-bg px-2 py-0.5 text-xs font-semibold text-alerta-dark">
                {VULNERABILITY_CATALOG[m.marker_code]?.label ?? m.marker_code}
              </li>
            ))}
          </ul>
        )}
      </section>
  );
  const identityColumn = (idp: string) => (
    <>
      {fichaSection(idp)}
      {statusSection(idp)}
      {alertsSection(idp)}
    </>
  );

  return (
    <div className="space-y-4 md:space-y-6">
      {/* Barra superior de navegación */}
      <div className="flex items-center justify-between gap-2 border-b border-gray-200 pb-3 md:pb-4">
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
          <span className="hidden whitespace-nowrap text-xs bg-claro text-turquesa-dark px-2.5 py-1 rounded-full font-bold md:inline">
            {caseData.statuses.engagement_status?.label || t('common.not_recorded')}
          </span>
        </div>
      </div>

      {/* Cabecera del Expediente */}
      <div className="bg-white rounded-2xl p-3 md:p-6 border border-gray-200 shadow-sm flex flex-col md:flex-row md:items-center justify-between gap-3 md:gap-4">
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
            <span>·</span>
            <span>{countryLabel(caseData.person.nationality_country_id, caseData.person.other_nationality) ?? t('cases.not_specified')}</span>
            <span className="hidden md:inline">·</span>
            <span className="hidden md:inline">{t('cases.opened_label')} {formatDate(caseData.opened_at)}</span>
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
              className="hidden min-h-11 items-center gap-2 rounded-lg border border-gray-300 bg-white px-4 text-sm font-semibold text-carbon hover:bg-gray-50 md:inline-flex"
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

      {/* Dos columnas (ciclo «Ingreso y expediente»): identidad, estatus y alertas siempre a la vista; a la derecha, la vida del caso */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[minmax(0,21rem)_minmax(0,1fr)] lg:gap-6 lg:items-start">
        <div className="space-y-3 lg:hidden">
          <section data-resumen-caso aria-label={t('cases.summary.label')} className="space-y-2 rounded-2xl border border-gray-200 bg-white p-3">
            <ul className="space-y-1 text-xs">
              {statusAxes.map((axis) => (
                <li key={axis.id} className="flex items-baseline justify-between gap-3">
                  <span className="text-gray-700">{axis.label_es}</span>
                  <span className="text-right font-semibold text-carbon">{caseData.statuses[axis.code]?.label || t('common.not_recorded')}</span>
                </li>
              ))}
            </ul>
            <div className="flex flex-wrap items-center gap-1.5 text-xs">
              {activeMarkers.length === 0 ? (
                <span className="text-gray-700">{t('cases.alerts_none')}</span>
              ) : activeMarkers.map((m) => (
                <span key={m.id} className="rounded-md bg-alerta-bg px-2 py-0.5 font-semibold text-alerta-dark">
                  {VULNERABILITY_CATALOG[m.marker_code]?.label ?? m.marker_code}
                </span>
              ))}
              <span className="rounded-md bg-claro px-2 py-0.5 font-semibold text-carbon">
                {caseData.photo_consent === true ? t('cases.summary.photo_authorized') : caseData.photo_consent === false ? t('cases.summary.photo_not_authorized') : t('cases.summary.photo_not_recorded')}
              </span>
            </div>
          </section>
          <details className="rounded-2xl border border-gray-200 bg-white">
            <summary className="flex min-h-11 cursor-pointer items-center px-4 text-sm font-semibold text-carbon">
              {t('cases.mobile_summary')}
            </summary>
            <div className="space-y-4 p-4">{fichaSection('movil')}</div>
          </details>
        </div>
        <div className="hidden space-y-4 lg:sticky lg:top-20 lg:block">{identityColumn('caso')}</div>

        <div className="min-w-0 space-y-4">
          {canWriteJournal && (
            <div data-bitacora-acciones className="flex gap-2 lg:hidden">
              {!caseData.person.is_anonymized && (
                <button
                  type="button"
                  aria-expanded={quickOpen}
                  aria-controls="nota-rapida"
                  onClick={() => setQuickOpen((v) => !v)}
                  className="inline-flex min-h-11 flex-1 items-center justify-center rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50"
                >
                  {t('journal.quick.toggle')}
                </button>
              )}
              <button
                type="button"
                onClick={onStartJournalEntry}
                className="inline-flex min-h-11 flex-1 items-center justify-center gap-2 rounded-lg bg-turquesa px-3 text-sm font-bold text-carbon shadow-sm hover:opacity-90"
              >
                <Plus className="h-4 w-4" aria-hidden="true" />
                <span>{t('journal.btn_new_entry_short')}</span>
              </button>
            </div>
          )}
          {canWriteJournal && !caseData.person.is_anonymized && (
            <div id="nota-rapida" className={quickOpen ? '' : 'hidden lg:block'}>
              <QuickJournalCapture
                caseId={caseData.id}
                assignedAreaId={caseData.assigned_area_id ?? undefined}
                isDirector={isDirector}
                onSaved={async () => { setQuickOpen(false); await onDataChanged?.(); }}
                onOpenFullForm={onStartJournalEntry}
              />
            </div>
          )}
          <div className="space-y-4">
            {/* Header de Bitácora */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 bg-white p-3 sm:p-4 rounded-xl border border-gray-200">
              {/* Filtros */}
              <div className="flex flex-nowrap items-center gap-1.5 overflow-x-auto text-xs sm:flex-wrap sm:overflow-visible">
                <button
                  onClick={() => setJournalFilter('all')}
                  className={`whitespace-nowrap px-3 py-1.5 rounded-lg font-bold transition ${
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
                    className={`whitespace-nowrap px-3 py-1.5 rounded-lg font-bold transition ${
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
                  className={`whitespace-nowrap px-3 py-1.5 rounded-lg font-bold transition ${
                    journalFilter === 'shared'
                      ? 'bg-blue-600 text-white shadow-sm'
                      : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                  }`}
                >
                  {t('journal.filter_shared')}
                </button>
                <button
                  onClick={() => setJournalFilter('work_notes')}
                  className={`whitespace-nowrap px-3 py-1.5 rounded-lg font-bold transition ${
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
                  className="hidden items-center gap-2 rounded-lg bg-turquesa px-4 py-2 text-xs font-bold text-carbon shadow-sm hover:opacity-90 lg:flex"
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
        </div>
      </div>

      {/* Más del expediente: lo que ya no necesita una pestaña para el trabajo diario */}
      <section aria-labelledby="caso-mas" className="space-y-3">
        <h3 id="caso-mas" className="text-sm font-bold uppercase tracking-wider text-gray-700">{t('cases.more')}</h3>
        <MoreSection id="axes" title={t('cases.tabs_short.axes')} hint={[caseData.statuses.engagement_status?.label, caseData.statuses.case_stage?.label].filter(Boolean).join(' · ')} defaultOpen={false}>
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
        </MoreSection>
        <MoreSection id="summary" title={t('cases.tabs_short.summary')} hint={t('cases.more_hint.summary')} defaultOpen={false}>
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

            <SocialFichaPanel
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
        </MoreSection>
        <MoreSection id="vulnerabilities" title={`${t('cases.tabs_short.vulnerabilities')} (${caseData.vulnerabilities.length})`} hint={caseData.vulnerabilities.slice(0, 2).map((m) => VULNERABILITY_CATALOG[m.marker_code]?.label ?? m.marker_code).join(', ') + (caseData.vulnerabilities.length > 2 ? ` +${caseData.vulnerabilities.length - 2}` : '')} defaultOpen={false}>
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
        </MoreSection>
        {((caseData.subfolios && caseData.subfolios.length > 0) || canCreateSubfolio) && (
          <MoreSection id="subfolios" title={`${t('cases.tabs_short.subfolios')} (${caseData.subfolios?.length ?? 0})`} hint={(caseData.subfolios ?? []).slice(0, 2).map((x) => x.case_number).join(', ') + ((caseData.subfolios?.length ?? 0) > 2 ? ` +${(caseData.subfolios?.length ?? 0) - 2}` : '')} defaultOpen={false}>
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
              {canCreateSubfolio && (
                <button
                  type="button"
                  onClick={onStartSubfolio}
                  className="inline-flex min-h-11 items-center gap-2 rounded-lg border border-gray-300 bg-white px-4 text-sm font-semibold text-carbon hover:bg-gray-50 md:hidden"
                >
                  <Users className="h-4 w-4" aria-hidden="true" />
                  {t('cases.btn_new_subfolio')}
                </button>
              )}
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
          </MoreSection>
        )}
        {canLinkTasks && (
          <MoreSection id="tasks" title={t('tasks.case.tab')} defaultOpen={false}>
            <CaseTasksPanel caseId={caseData.id} caseNumber={caseData.case_number} />
          </MoreSection>
        )}
        <MoreSection id="privacy" title={t('cases.tabs_short.privacy') as React.ReactNode} hint={caseData.photo_consent === true ? t('cases.summary.photo_authorized') : caseData.photo_consent === false ? t('cases.summary.photo_not_authorized') : t('cases.summary.photo_not_recorded')} defaultOpen={initialTab === 'privacy'}>
          <div className="space-y-6">
            <CaseAuthorizationsPanel
              caseId={caseData.id}
              photo={caseData.photo_consent}
              coexistence={caseData.coexistence_rules_accepted}
              nna={caseData.nna_responsibility_accepted}
              canEdit={canManageConsent && !caseData.person.is_anonymized && !!onDataChanged}
              onChanged={async () => { await onDataChanged?.(); }}
            />

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
        </MoreSection>
      </section>



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

// «Más del expediente»: secciones que se abren cuando hacen falta (antes eran pestañas)
const MoreSection: React.FC<{ id: string; title: React.ReactNode; hint?: string; defaultOpen?: boolean; children: React.ReactNode }> = ({ id, title, hint, defaultOpen = false, children }) => (
  <details id={`caso-${id}`} open={defaultOpen} className="rounded-2xl border border-gray-200 bg-gray-50">
    <summary className="flex min-h-11 cursor-pointer items-center gap-2 px-4 text-sm font-bold text-carbon">
      <span className="shrink-0">{title}</span>
      {hint && <span data-more-hint className="min-w-0 flex-1 truncate text-right text-xs font-normal text-gray-600">{hint}</span>}
    </summary>
    <div className="space-y-4 p-4">{children}</div>
  </details>
);
