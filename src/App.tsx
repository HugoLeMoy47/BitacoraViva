import React, { useCallback, useEffect, useState } from 'react';
import {
  ShieldCheck,
  Layers,
  Users,
  CheckCircle2,
  AlertTriangle,
  Building2,
  Lock,
  Database,
  History,
  Scale,
  FolderOpen,
  FileText,
  Bell,
  LogOut,
  X
} from 'lucide-react';
import { t } from './lib/i18n';
import {
  RoleName,
  StatusAxisCode,
  CaseWithDetails,
  JournalEntry,
  ConsentType,
  ConsentStatus,
  Person
} from './types/database';
import { api, EMPTY_ORG_DATA, getTitularPersonId, loadOrgData, OrgData } from './lib/data';
import { SessionProvider, SessionUser, useSession } from './lib/session';
import { CatalogProvider } from './lib/catalog';
import { CasesView } from './components/CasesView';
import { DirectorSharingInbox } from './components/DirectorSharingInbox';
import { LoginView } from './components/LoginView';

const ROLE_NAMES: RoleName[] = ['director', 'intake_officer', 'caseworker', 'viewer'];

const errorMessage = (e: unknown): string => (e instanceof Error ? e.message : String(e));

const Workspace: React.FC<{ currentUser: SessionUser }> = ({ currentUser }) => {
  const { signOut } = useSession();
  const activeRole = currentUser.role;
  const isDirector = activeRole === 'director';

  const [activeTab, setActiveTab] = useState<'overview' | 'cases' | 'areas' | 'audit' | 'authority_requests' | 'rules'>('cases');
  const [isDirectorDigestOpen, setIsDirectorDigestOpen] = useState<boolean>(false);
  const [data, setData] = useState<OrgData>(EMPTY_ORG_DATA);
  const [loadState, setLoadState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [loadError, setLoadError] = useState<string>('');
  const [actionError, setActionError] = useState<string | null>(null);

  const casesList = data.cases;
  const sharingEventsList = data.sharingEvents;
  const organization = data.organization;

  const reload = useCallback(async () => {
    try {
      setData(await loadOrgData());
      setLoadState('ready');
    } catch (e) {
      setLoadError(errorMessage(e));
      setLoadState((s) => (s === 'ready' ? 'ready' : 'error'));
      setActionError(errorMessage(e));
    }
  }, []);

  useEffect(() => {
    reload();
  }, [reload]);

  // Toda escritura es una función de la base (valida rol, audita y es transaccional).
  // La interfaz sólo informa el resultado y vuelve a leer lo que RLS permite ver.
  const run = async (action: () => Promise<unknown>) => {
    setActionError(null);
    try {
      await action();
    } catch (e) {
      setActionError(errorMessage(e));
    }
    await reload();
  };

  const personIdOfCase = (caseId: string) => casesList.find((c) => c.id === caseId)?.titular_person_id;

  const handleCaseCreated = (newCase: CaseWithDetails) =>
    run(async () => {
      const p = newCase.person;
      const caseId = await api.createCaseWithPerson({
        given_name: p.given_name,
        paternal_family_name: p.paternal_family_name,
        maternal_family_name: p.maternal_family_name ?? null,
        preferred_name: p.preferred_name ?? null,
        birth_date: p.birth_date,
        birth_date_is_estimated: p.birth_date_is_estimated,
        sex_id: p.sex_id,
        nationality_country_id: p.nationality_country_id,
        other_nationality: p.other_nationality ?? null,
        primary_language_id: p.primary_language_id,
        other_language: p.other_language ?? null,
        phone_number: p.phone_number ?? null,
        intake_window_type: newCase.intake_window_type,
        travels_with_family: newCase.travels_with_family,
        intake_state_id: newCase.intake_state_id,
        intake_municipality_id: newCase.intake_municipality_id,
        intake_channel_id: newCase.intake_channel_id,
        entry_route_id: newCase.entry_route_id,
        entry_date_str: newCase.entry_date_str ?? null,
        assigned_area_id: newCase.assigned_area_id ?? null,
        vulnerability_codes: newCase.vulnerabilities.map((v) => v.marker_code),
      });
      const personId = await getTitularPersonId(caseId);
      for (const k of newCase.consents || []) {
        await api.registerConsent({
          person_id: personId,
          case_id: caseId,
          consent_type: k.consent_type,
          status: k.status,
          is_minor_assent: k.is_minor_assent,
          notes: k.notes,
        });
      }
    });

  const handleTransitionStatus = (
    caseId: string,
    axisCode: StatusAxisCode,
    newValueCode: string,
    reason: string
  ) => run(() => api.changeCaseStatus(caseId, axisCode, newValueCode, reason));

  // Handlers para Bitácora de Área (Épica E4)
  const handleAddJournalEntry = (entry: JournalEntry) =>
    run(() =>
      api.createJournalEntry({
        case_id: entry.case_id,
        entry_type_key: entry.entry_type_key,
        body: entry.body,
        occurred_at: entry.occurred_at,
        is_work_note: entry.is_work_note,
        area_id: entry.area_id || null,
      })
    );

  const handleAddClarification = (originalEntryId: string, clarification: JournalEntry) =>
    run(() =>
      api.createClarificationNote(
        originalEntryId,
        clarification.body,
        clarification.occurred_at,
        clarification.is_work_note
      )
    );

  const handleShareJournalEntry = (
    entryId: string,
    toAreaId: string,
    _toAreaName: string,
    reason: string
  ) => run(() => api.shareJournalEntry(entryId, toAreaId, reason));

  const handleAcknowledgeSharing = (sharingEventId: string) =>
    run(() => api.acknowledgeSharing(sharingEventId));

  const handleSaveConsent = (
    caseId: string,
    consentData: {
      consent_type: ConsentType;
      status: ConsentStatus;
      is_minor_assent: boolean;
      legal_guardian_name?: string;
      legal_guardian_role?: string;
      authority_letter_ref?: string;
      notes?: string;
    }
  ) =>
    run(async () => {
      const personId = personIdOfCase(caseId);
      if (!personId) throw new Error('Expediente no encontrado.');
      await api.registerConsent({ person_id: personId, case_id: caseId, ...consentData });
    });

  const handleRectifyPerson = (personId: string, updates: Partial<Person>, reason: string) =>
    run(async () => {
      const current = casesList.find((c) => c.titular_person_id === personId)?.person;
      if (!current) throw new Error('Persona no encontrada.');
      await api.rectifyPerson({ ...current, ...updates }, reason);
    });

  const handleAnonymizePerson = (personId: string, reason: string) =>
    run(() => api.anonymizePerson(personId, reason));

  const handleOpposeSecondary = (personId: string, reason: string) =>
    run(() => api.applyOpposition(personId, reason));

  if (loadState === 'loading') {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center text-sm text-gray-500">
        {t('session.loading')}
      </div>
    );
  }

  if (loadState === 'error') {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center p-4">
        <div className="bg-white rounded-xl border border-gray-200 shadow-sm p-6 max-w-md text-center space-y-3">
          <p className="text-sm font-semibold text-carbon">{t('session.data_error')}</p>
          <p className="text-xs text-gray-500 break-words">{loadError}</p>
          <div className="flex justify-center gap-2">
            <button
              onClick={() => { setLoadState('loading'); reload(); }}
              className="px-3 py-1.5 text-xs font-semibold rounded-lg bg-carbon text-white"
            >
              {t('session.retry')}
            </button>
            <button onClick={signOut} className="px-3 py-1.5 text-xs font-semibold rounded-lg border border-gray-300">
              {t('session.sign_out')}
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <CatalogProvider value={{ areas: data.areas, statusAxes: data.statusAxes, statusValues: data.statusValues }}>
    <div className="min-h-screen bg-gray-50 flex flex-col text-carbon font-sans">
      {/* Header Superior con Branding Freejolitos */}
      <header className="bg-carbon text-white border-b-4 border-turquesa sticky top-0 z-50">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-3 flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-center space-x-3">
            <div className="w-10 h-10 rounded bg-turquesa text-carbon flex items-center justify-center font-bold text-xl shadow">
              BV
            </div>
            <div>
              <div className="flex items-center space-x-2">
                <h1 className="text-xl font-bold tracking-tight text-white">{t('app.title')}</h1>
                <span className="bg-turquesa/20 text-turquesa-light text-xs font-semibold px-2 py-0.5 rounded border border-turquesa/30">
                  {t('app.badge_poc')}
                </span>
              </div>
              <p className="text-xs text-gray-400">{t('app.tagline')}</p>
            </div>
          </div>

          <div className="flex items-center gap-3">
            <div className="hidden md:flex items-center bg-carbon-light px-3 py-1.5 rounded-full border border-gray-700 text-xs text-turquesa-light">
              <ShieldCheck className="w-4 h-4 mr-1.5 text-turquesa" />
              {t('app.ethos_commitment')}
            </div>
            <div className="flex items-center bg-gray-800 text-xs text-gray-300 px-3 py-1 rounded border border-gray-700">
              <Database className="w-3.5 h-3.5 mr-1.5 text-turquesa" />
              {t('session.mode_emulation')}
            </div>

            {isDirector && (
              <button
                onClick={() => setIsDirectorDigestOpen(true)}
                className="relative flex items-center gap-1.5 rounded-lg bg-gray-800 px-3 py-1.5 text-xs font-semibold text-gray-200 border border-gray-700 hover:bg-gray-700 hover:text-white transition"
                title={t('journal.director_digest.title')}
              >
                <Bell className="w-3.5 h-3.5 text-turquesa" />
                <span>Digest</span>
                {sharingEventsList.filter(e => !e.acknowledged_at).length > 0 && (
                  <span className="flex h-4 min-w-4 items-center justify-center rounded-full bg-alerta px-1 text-[10px] font-bold text-white">
                    {sharingEventsList.filter(e => !e.acknowledged_at).length}
                  </span>
                )}
              </button>
            )}
          </div>
        </div>
      </header>

      {/* Identidad de la sesión autenticada (el rol lo determina la base, no la interfaz) */}
      <div className="bg-white border-b border-gray-200 shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-3">
          <div className="bg-gray-50 rounded-lg p-3 border border-gray-200 flex flex-col sm:flex-row sm:items-center justify-between text-xs gap-2">
            <div className="flex items-center flex-wrap gap-2">
              <Users className="w-4 h-4 text-turquesa-dark" />
              <span className="font-semibold text-carbon">{currentUser.profile.full_name}</span>
              <span className="text-gray-400">({currentUser.profile.email})</span>
              <span className="bg-gray-200 text-carbon px-2 py-0.5 rounded font-mono text-[11px]">
                {t(`roles.${activeRole}.badge`)}
              </span>
              <span className="bg-claro text-turquesa-dark px-2 py-0.5 rounded text-[11px] font-medium border border-turquesa/30">
                {t('session.assigned_area')}{' '}
                {currentUser.assignedAreaName || t('session.transversal_role')}
              </span>
            </div>
            <div className="flex items-center gap-3">
              <p className="text-carbon-muted italic text-[11px]">
                {t(`roles.${activeRole}.description`)}
              </p>
              <button
                onClick={signOut}
                className="flex items-center gap-1.5 rounded-lg border border-gray-300 bg-white px-2.5 py-1 text-[11px] font-semibold text-gray-700 hover:bg-gray-100"
              >
                <LogOut className="w-3.5 h-3.5" />
                {t('session.sign_out')}
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Contenedor Principal */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6 flex-1 w-full">
        {actionError && (
          <div role="alert" className="mb-4 flex items-start justify-between gap-3 rounded-lg border border-alerta/20 bg-alerta-bg p-3 text-xs text-alerta">
            <span>
              <strong>{t('session.action_error')}</strong> {actionError}
            </span>
            <button onClick={() => setActionError(null)} aria-label={t('session.dismiss')} className="shrink-0">
              <X className="w-4 h-4" />
            </button>
          </div>
        )}

        {/* Pestañas de Navegación */}
        <div className="flex space-x-2 border-b border-gray-200 mb-6 overflow-x-auto">
          <button
            onClick={() => setActiveTab('cases')}
            className={`pb-3 px-4 text-sm font-semibold border-b-2 flex items-center gap-2 whitespace-nowrap ${
              activeTab === 'cases'
                ? 'border-turquesa text-carbon'
                : 'border-transparent text-gray-500 hover:text-carbon'
            }`}
          >
            <FolderOpen className="w-4 h-4 text-turquesa-dark" />
            <span className="font-bold">{t('navigation.cases')}</span>
            <span className="bg-gray-200 text-carbon px-1.5 py-0.2 rounded-full text-[10px] font-mono">
              {casesList.length}
            </span>
          </button>
          <button
            onClick={() => setActiveTab('overview')}
            className={`pb-3 px-4 text-sm font-semibold border-b-2 flex items-center gap-2 whitespace-nowrap ${
              activeTab === 'overview'
                ? 'border-turquesa text-carbon'
                : 'border-transparent text-gray-500 hover:text-carbon'
            }`}
          >
            <Building2 className="w-4 h-4" />
            {t('navigation.overview')}
          </button>
          <button
            onClick={() => setActiveTab('areas')}
            className={`pb-3 px-4 text-sm font-semibold border-b-2 flex items-center gap-2 whitespace-nowrap ${
              activeTab === 'areas'
                ? 'border-turquesa text-carbon'
                : 'border-transparent text-gray-500 hover:text-carbon'
            }`}
          >
            <Layers className="w-4 h-4" />
            {t('navigation.areas')}
          </button>
          <button
            onClick={() => setActiveTab('audit')}
            className={`pb-3 px-4 text-sm font-semibold border-b-2 flex items-center gap-2 whitespace-nowrap ${
              activeTab === 'audit'
                ? 'border-turquesa text-carbon'
                : 'border-transparent text-gray-500 hover:text-carbon'
            }`}
          >
            <History className="w-4 h-4" />
            {t('navigation.audit_trail')}
            {!isDirector && (
              <span className="bg-gray-200 text-gray-600 text-[10px] px-1.5 py-0.2 rounded font-mono">
                RLS
              </span>
            )}
          </button>
          <button
            onClick={() => setActiveTab('authority_requests')}
            className={`pb-3 px-4 text-sm font-semibold border-b-2 flex items-center gap-2 whitespace-nowrap ${
              activeTab === 'authority_requests'
                ? 'border-turquesa text-carbon'
                : 'border-transparent text-gray-500 hover:text-carbon'
            }`}
          >
            <Scale className="w-4 h-4" />
            {t('navigation.authority_requests')}
            {!isDirector && (
              <span className="bg-gray-200 text-gray-600 text-[10px] px-1.5 py-0.2 rounded font-mono">
                E-03
              </span>
            )}
          </button>
          <button
            onClick={() => setActiveTab('rules')}
            className={`pb-3 px-4 text-sm font-semibold border-b-2 flex items-center gap-2 whitespace-nowrap ${
              activeTab === 'rules'
                ? 'border-turquesa text-carbon'
                : 'border-transparent text-gray-500 hover:text-carbon'
            }`}
          >
            <Lock className="w-4 h-4" />
            {t('navigation.rules')}
          </button>
        </div>

        {/* Tab 1: Gestión de Expedientes y Casos (Épicas E2, E3 y E4) */}
        {activeTab === 'cases' && (
          <CasesView
            cases={casesList}
            activeRole={activeRole}
            assignedAreaCode={currentUser.assignedAreaCode}
            assignedAreaId={currentUser.userRole?.area_id || undefined}
            authorUserId={currentUser.profile.id}
            authorFullName={currentUser.profile.full_name}
            onCaseCreated={handleCaseCreated}
            onTransitionStatus={handleTransitionStatus}
            onAddJournalEntry={handleAddJournalEntry}
            onAddClarification={handleAddClarification}
            onShareJournalEntry={handleShareJournalEntry}
            onSaveConsent={handleSaveConsent}
            onRectifyPerson={handleRectifyPerson}
            onAnonymizePerson={handleAnonymizePerson}
            onOpposeSecondary={handleOpposeSecondary}
          />
        )}

        {/* Tab 2: Resumen de Tenancy y Seguridad */}
        {activeTab === 'overview' && (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div className="bg-white p-6 rounded-xl border border-gray-200 shadow-sm">
              <div className="flex items-center space-x-3 mb-4">
                <div className="p-2 bg-claro rounded-lg text-turquesa-dark">
                  <Building2 className="w-5 h-5" />
                </div>
                <h2 className="text-base font-bold text-carbon">{t('dashboard.organization_details')}</h2>
              </div>
              <dl className="space-y-3 text-sm">
                <div>
                  <dt className="text-gray-500 text-xs font-medium">{t('dashboard.org_display')}</dt>
                  <dd className="font-semibold text-carbon text-lg">{organization?.display_name}</dd>
                </div>
                <div>
                  <dt className="text-gray-500 text-xs font-medium">{t('dashboard.org_legal')}</dt>
                  <dd className="text-carbon">{organization?.legal_name}</dd>
                </div>
                <div>
                  <dt className="text-gray-500 text-xs font-medium">{t('dashboard.org_slug')}</dt>
                  <dd className="font-mono text-xs bg-gray-100 p-1.5 rounded inline-block text-gray-800">
                    {organization?.slug}
                  </dd>
                </div>
                <div className="pt-2 border-t border-gray-100 flex items-center justify-between text-xs">
                  <span className="text-gray-500">Estado Multi-Tenant:</span>
                  <span className="bg-green-100 text-green-800 px-2 py-0.5 rounded-full font-medium">
                    {t('dashboard.active_badge')}
                  </span>
                </div>
              </dl>
            </div>

            <div className="bg-white p-6 rounded-xl border border-gray-200 shadow-sm flex flex-col justify-between">
              <div>
                <div className="flex items-center space-x-3 mb-4">
                  <div className="p-2 bg-claro rounded-lg text-turquesa-dark">
                    <ShieldCheck className="w-5 h-5" />
                  </div>
                  <h2 className="text-base font-bold text-carbon">{t('dashboard.security_status')}</h2>
                </div>
                <p className="text-sm text-carbon-muted leading-relaxed">
                  {t('dashboard.security_status_desc')}
                </p>
                <div className="mt-4 bg-alerta-bg border border-alerta/20 p-3 rounded-lg text-xs text-alerta flex items-start space-x-2">
                  <AlertTriangle className="w-4 h-4 flex-shrink-0 mt-0.5" />
                  <span>
                    El motor de base de datos tiene activo el disparador <code>trg_prevent_audit_tampering</code>: ningún usuario, ni siquiera un director, puede alterar o eliminar registros de auditoría.
                  </span>
                </div>
              </div>

              <div className="mt-6 pt-4 border-t border-gray-100 grid grid-cols-2 gap-4 text-center">
                <div className="bg-gray-50 p-3 rounded-lg">
                  <span className="block text-2xl font-bold text-carbon">{data.areas.length}</span>
                  <span className="text-[11px] text-gray-500">{t('dashboard.total_areas')}</span>
                </div>
                <div className="bg-gray-50 p-3 rounded-lg">
                  <span className="block text-2xl font-bold text-turquesa-dark">{ROLE_NAMES.length}</span>
                  <span className="text-[11px] text-gray-500">{t('dashboard.total_roles')}</span>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Tab 3: Áreas del Albergue */}
        {activeTab === 'areas' && (
          <div className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden">
            <div className="px-6 py-4 border-b border-gray-200">
              <h2 className="text-base font-bold text-carbon">{t('dashboard.areas_title')}</h2>
            </div>
            <div className="divide-y divide-gray-100">
              {data.areas.map((area) => (
                <div key={area.id} className="p-4 sm:px-6 flex items-center justify-between hover:bg-gray-50 transition-colors">
                  <div className="flex items-center space-x-3">
                    <div className="w-8 h-8 rounded-full bg-claro text-turquesa-dark flex items-center justify-center font-bold text-xs">
                      {area.code.substring(0, 2).toUpperCase()}
                    </div>
                    <div>
                      <h3 className="text-sm font-semibold text-carbon">{area.name}</h3>
                      <p className="text-xs text-gray-400 font-mono">code: {area.code}</p>
                    </div>
                  </div>
                  <span className="bg-green-100 text-green-800 text-xs px-2.5 py-0.5 rounded-full font-medium">
                    {t('dashboard.active_badge')}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Tab 4: Registro de Auditoría Inmutable (Protegido por Ethos C4 y BV-1.3) */}
        {activeTab === 'audit' && (
          <div>
            {isDirector ? (
              <div className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden">
                <div className="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
                  <div>
                    <h2 className="text-base font-bold text-carbon">{t('dashboard.audit_title')}</h2>
                    <p className="text-xs text-gray-500">Gobernanza C4: Append-only estricto por trigger en PostgreSQL · Solo Dirección</p>
                  </div>
                  <span className="text-xs font-mono bg-claro text-carbon px-2 py-1 rounded border border-turquesa/30">
                    {data.auditEvents.length} eventos
                  </span>
                </div>
                <div className="overflow-x-auto">
                  <table className="min-w-full divide-y divide-gray-200 text-xs">
                    <thead className="bg-gray-50 text-gray-500 font-medium uppercase">
                      <tr>
                        <th className="px-6 py-3 text-left">{t('dashboard.table_column_action')}</th>
                        <th className="px-6 py-3 text-left">{t('dashboard.table_column_table')}</th>
                        <th className="px-6 py-3 text-left">{t('dashboard.table_column_record')}</th>
                        <th className="px-6 py-3 text-left">{t('dashboard.table_column_timestamp')}</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-gray-100 bg-white">
                      {data.auditEvents.map((event) => (
                        <tr key={event.id} className="hover:bg-gray-50 font-mono">
                          <td className="px-6 py-3 whitespace-nowrap">
                            <span className="px-2 py-0.5 bg-gray-100 text-carbon font-bold rounded text-[11px] border border-gray-300">
                              {event.action}
                            </span>
                          </td>
                          <td className="px-6 py-3 text-carbon font-semibold">{event.table_name}</td>
                          <td className="px-6 py-3 text-gray-500 truncate max-w-xs">{event.record_id}</td>
                          <td className="px-6 py-3 text-gray-400">{event.created_at}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            ) : (
              <div className="bg-white rounded-xl border border-gray-200 p-8 shadow-sm text-center max-w-2xl mx-auto my-8">
                <div className="w-14 h-14 bg-alerta-bg text-alerta rounded-full flex items-center justify-center mx-auto mb-4 border border-alerta/20">
                  <Lock className="w-7 h-7" />
                </div>
                <span className="bg-alerta-bg text-alerta text-xs font-semibold px-2.5 py-1 rounded-full border border-alerta/20 inline-block mb-3">
                  {t('audit.restricted_badge')}
                </span>
                <h3 className="text-lg font-bold text-carbon mb-2">
                  {t('audit.restricted_title')}
                </h3>
                <p className="text-sm text-carbon-muted mb-6 leading-relaxed">
                  {t('audit.restricted_message')}
                </p>
                <div className="bg-gray-50 rounded-lg p-4 text-left border border-gray-200 text-xs space-y-2">
                  <div className="font-semibold text-gray-700">{t('audit.active_policy_label')}</div>
                  <code className="block bg-gray-100 p-2 rounded text-carbon font-mono text-[11px] overflow-x-auto">
                    {t('audit.active_policy_code')}
                  </code>
                  <p className="text-gray-500 text-[11px]">
                    {t('audit.restricted_detail')}
                  </p>
                </div>
              </div>
            )}
          </div>
        )}

        {/* Tab 5: Requerimientos de Autoridad (Ethos E-03) */}
        {activeTab === 'authority_requests' && (
          <div>
            {isDirector ? (
              <div className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden">
                <div className="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
                  <div>
                    <h2 className="text-base font-bold text-carbon">{t('authority_requests.title')}</h2>
                    <p className="text-xs text-gray-500">{t('authority_requests.subtitle')}</p>
                  </div>
                  <span className="text-xs font-mono bg-claro text-carbon px-2 py-1 rounded border border-turquesa/30">
                    {data.authorityRequests.length} oficios registrados
                  </span>
                </div>

                <div className="overflow-x-auto">
                  <table className="min-w-full divide-y divide-gray-200 text-xs">
                    <thead className="bg-gray-50 text-gray-500 font-medium uppercase">
                      <tr>
                        <th className="px-6 py-3 text-left">{t('authority_requests.table_column_authority')}</th>
                        <th className="px-6 py-3 text-left">{t('authority_requests.table_column_ref')}</th>
                        <th className="px-6 py-3 text-left">{t('authority_requests.table_column_type')}</th>
                        <th className="px-6 py-3 text-left">{t('authority_requests.table_column_received')}</th>
                        <th className="px-6 py-3 text-left">{t('authority_requests.table_column_status')}</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-gray-100 bg-white">
                      {data.authorityRequests.map((req) => (
                        <tr key={req.id} className="hover:bg-gray-50">
                          <td className="px-6 py-3 font-semibold text-carbon">{req.authority_name}</td>
                          <td className="px-6 py-3 font-mono text-gray-700">{req.official_letter_ref}</td>
                          <td className="px-6 py-3 text-gray-600">{req.request_type}</td>
                          <td className="px-6 py-3 text-gray-500">{req.received_at.substring(0, 10)}</td>
                          <td className="px-6 py-3">
                            <span className={`px-2 py-0.5 rounded text-[11px] font-medium ${
                              req.extract_delivered 
                                ? 'bg-green-100 text-green-800' 
                                : 'bg-amber-100 text-amber-800'
                            }`}>
                              {req.extract_delivered 
                                ? t('authority_requests.status_delivered') 
                                : t('authority_requests.status_pending')}
                            </span>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>

                <div className="p-4 bg-gray-50 border-t border-gray-200 text-xs text-gray-600 flex items-start gap-2">
                  <FileText className="w-4 h-4 text-turquesa-dark flex-shrink-0 mt-0.5" />
                  <span>{t('authority_requests.governance_note')}</span>
                </div>
              </div>
            ) : (
              <div className="bg-white rounded-xl border border-gray-200 p-8 shadow-sm text-center max-w-2xl mx-auto my-8">
                <div className="w-14 h-14 bg-alerta-bg text-alerta rounded-full flex items-center justify-center mx-auto mb-4 border border-alerta/20">
                  <Scale className="w-7 h-7" />
                </div>
                <span className="bg-alerta-bg text-alerta text-xs font-semibold px-2.5 py-1 rounded-full border border-alerta/20 inline-block mb-3">
                  {t('authority_requests.restricted_badge')}
                </span>
                <h3 className="text-lg font-bold text-carbon mb-2">
                  {t('authority_requests.restricted_title')}
                </h3>
                <p className="text-sm text-carbon-muted mb-4 leading-relaxed">
                  {t('authority_requests.restricted_message')}
                </p>
              </div>
            )}
          </div>
        )}

        {/* Tab 6: 10 Reglas Duras */}
        {activeTab === 'rules' && (
          <div className="bg-white p-6 rounded-xl border border-gray-200 shadow-sm">
            <h2 className="text-base font-bold text-carbon mb-2">Las 10 Reglas Duras de Supabase</h2>
            <p className="text-xs text-gray-500 mb-6">
              Contrato de handoff inmutable. Violarlas constituye un defecto estructural, no una diferencia de criterio.
            </p>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              {Array.from({ length: 10 }).map((_, i) => {
                const key = `r${i + 1}`;
                return (
                  <div key={key} className="flex items-start space-x-3 p-3 rounded-lg bg-gray-50 border border-gray-200">
                    <CheckCircle2 className="w-5 h-5 text-turquesa flex-shrink-0 mt-0.5" />
                    <span className="text-xs text-carbon font-medium">
                      {t(`rules_list.${key}`)}
                    </span>
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </main>

      {/* Footer */}
      <footer className="bg-white border-t border-gray-200 py-4 text-center text-xs text-gray-500">
        <p>Bitácora Viva · Plataforma libre para la dignidad y soberanía informativa de la sociedad civil.</p>
      </footer>

      {/* Modal Director Sharing Digest (BV-4.4 / ADR-0005) */}
      {isDirectorDigestOpen && (
        <DirectorSharingInbox
          isOpen={isDirectorDigestOpen}
          onClose={() => setIsDirectorDigestOpen(false)}
          sharingEvents={sharingEventsList}
          onAcknowledge={handleAcknowledgeSharing}
        />
      )}
    </div>
    </CatalogProvider>
  );
};

const Gate: React.FC = () => {
  const { status, user } = useSession();
  if (status === 'loading') {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center text-sm text-gray-500">
        {t('session.loading')}
      </div>
    );
  }
  if (status === 'anonymous' || !user) return <LoginView />;
  return <Workspace key={user.profile.id} currentUser={user} />;
};

export const App: React.FC = () => (
  <SessionProvider>
    <Gate />
  </SessionProvider>
);

export default App;
