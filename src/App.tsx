import React, { useCallback, useEffect, useState } from 'react';
import { t } from './lib/i18n';
import {
  StatusAxisCode,
  JournalEntry,
  ConsentType,
  ConsentStatus,
  Person
} from './types/database';
import { api, configApi, EMPTY_ORG_DATA, loadOrgData, NewCaseInput, OrgData } from './lib/data';
import { SessionProvider, SessionUser, useSession } from './lib/session';
import { CatalogProvider } from './lib/catalog';
import { EnvironmentProvider, useEnvironment } from './lib/environment';
import { RouteId, navigate, useRoute } from './lib/router';
import { allowedRoutes, defaultRoute, hasCaseAccess } from './lib/navigation';
import { AppShell } from './components/AppShell';
import { CasesView } from './components/CasesView';
import { DirectorSharingInbox } from './components/DirectorSharingInbox';
import { LoginView } from './components/LoginView';
import { IndicatorsView } from './components/IndicatorsView';
import { OperationsDashboard } from './components/OperationsDashboard';
import { AreasView, AuditView, AuthorityView } from './components/AdminViews';
import { ConfigurationView } from './components/ConfigurationView';
import { TasksView } from './components/TasksView';
import { AboutView } from './components/AboutView';
import { DemoBanner } from './components/DemoBanner';
import { ToastProvider, useToast } from './lib/toast';
import { friendlyError } from './lib/errors';

const errorMessage = (e: unknown): string => (e instanceof Error ? e.message : String(e));

const Workspace: React.FC<{ currentUser: SessionUser }> = ({ currentUser }) => {
  const { signOut } = useSession();
  // El rol principal rotula y rige las pantallas de casos; las pantallas visibles salen de TODOS los roles
  const activeRole = currentUser.role;
  const roles = currentUser.roles;
  const caseAccess = hasCaseAccess(roles);
  const isDirector = roles.includes('director');

  const route = useRoute();
  const { isDemo } = useEnvironment();
  const allowed = allowedRoutes(roles, isDemo);
  const current: RouteId = route.id && allowed.includes(route.id) ? route.id : defaultRoute(roles);
  const [isDirectorDigestOpen, setIsDirectorDigestOpen] = useState<boolean>(false);
  const [data, setData] = useState<OrgData>(EMPTY_ORG_DATA);
  const [loadState, setLoadState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [loadError, setLoadError] = useState<string>('');
  const toast = useToast();
  const [pending, setPending] = useState(0);

  const casesList = data.cases;
  const sharingEventsList = data.sharingEvents;
  const organization = data.organization;

  const reload = useCallback(async (): Promise<OrgData | null> => {
    try {
      const fresh = await loadOrgData(caseAccess);
      setData(fresh);
      setLoadState('ready');
      return fresh;
    } catch (e) {
      setLoadError(errorMessage(e));
      setLoadState((prev) => (prev === 'ready' ? 'ready' : 'error'));
      toast.error(friendlyError(errorMessage(e)));
      return null;
    }
  }, [toast, caseAccess]);

  useEffect(() => {
    reload();
  }, [reload]);

  useEffect(() => {
    if (!route.id || !allowed.includes(route.id)) navigate(defaultRoute(roles), null, { replace: true });
  }, [route.id, allowed.join(','), roles.join(',')]);

  // Toda escritura es una función de la base (valida rol, audita y es transaccional).
  // La interfaz sólo informa el resultado y vuelve a leer lo que RLS permite ver.
  // Cada acción muestra «Guardando…», confirma o explica el error con el siguiente paso, y vuelve
  // a leer lo que RLS permite ver. Devuelve el resultado para quien necesite encadenar (p. ej. abrir lo creado).
  const run = async <T,>(action: () => Promise<T>, successKey?: string) => {
    setPending((n) => n + 1);
    let ok = false;
    let value: T | undefined;
    try {
      value = await action();
      ok = true;
      if (successKey) toast.success(t(successKey));
    } catch (e) {
      toast.error(friendlyError(errorMessage(e)));
    }
    const fresh = await reload();
    setPending((n) => n - 1);
    return { ok, value, data: fresh };
  };

  const personIdOfCase = (caseId: string) => casesList.find((c) => c.id === caseId)?.titular_person_id;

  // El alta es atómica en la base: persona, caso, marcadores y consentimientos en una transacción.
  const handleCaseCreated = async (input: NewCaseInput) => {
    const r = await run(() => api.createCaseWithPerson(input), 'toast.case_created');
    // Lleva a quien capturó directamente al expediente recién abierto
    const created = r.ok && r.data ? r.data.cases.find((c) => c.id === r.value) : undefined;
    if (created) navigate('cases', created.case_number);
  };

  const handleTransitionStatus = (
    caseId: string,
    axisCode: StatusAxisCode,
    newValueCode: string,
    reason: string
  ) => run(() => api.changeCaseStatus(caseId, axisCode, newValueCode, reason), 'toast.status_changed');

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
      }),
      'toast.journal_created'
    );

  const handleAddClarification = (originalEntryId: string, clarification: JournalEntry) =>
    run(() =>
      api.createClarificationNote(
        originalEntryId,
        clarification.body,
        clarification.occurred_at,
        clarification.is_work_note
      ),
      'toast.clarification_created'
    );

  const handleShareJournalEntry = (
    entryId: string,
    toAreaId: string,
    _toAreaName: string,
    reason: string
  ) => run(() => api.shareJournalEntry(entryId, toAreaId, reason), 'toast.shared');

  const handleAcknowledgeSharing = (sharingEventId: string) =>
    run(() => api.acknowledgeSharing(sharingEventId), 'toast.acknowledged');

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
    }, 'toast.consent_saved');

  const handleRectifyPerson = (personId: string, updates: Partial<Person>, reason: string) =>
    run(async () => {
      const current = casesList.find((c) => c.titular_person_id === personId)?.person;
      if (!current) throw new Error('Persona no encontrada.');
      await api.rectifyPerson({ ...current, ...updates }, reason);
    }, 'toast.rectified');

  const handleAnonymizePerson = (personId: string, reason: string) =>
    run(() => api.anonymizePerson(personId, reason), 'toast.anonymized');

  const handleOpposeSecondary = (personId: string, reason: string) =>
    run(() => api.applyOpposition(personId, reason), 'toast.opposition');

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

  const caseNumberOf = (id: string) => casesList.find((c) => c.id === id)?.case_number ?? null;

  return (
    <CatalogProvider value={{ areas: data.areas, statusAxes: data.statusAxes, statusValues: data.statusValues, organizationName: organization?.legal_name ?? '', organizationInfo: { responsibleName: organization?.responsible_name ?? '', responsibleAddress: organization?.responsible_address ?? '', arcoContact: organization?.arco_contact ?? '' }, userNames: data.userNames }}>
      {pending > 0 && (
        <div role="status" className="fixed left-1/2 top-16 z-[55] -translate-x-1/2 rounded-full bg-carbon px-4 py-1.5 text-sm font-semibold text-white shadow-lg">
          {t('toast.saving')}
        </div>
      )}
      <AppShell
        user={currentUser}
        organizationName={organization?.display_name ?? ''}
        route={current}
        allowed={allowed}
        caseCount={casesList.length}
        digestPending={isDirector ? sharingEventsList.filter((e) => !e.acknowledged_at).length : null}
        onOpenDigest={() => setIsDirectorDigestOpen(true)}
        onSignOut={signOut}
      >
        {current === 'operations' && (
          <OperationsDashboard
            cases={casesList}
            sharingEvents={sharingEventsList}
            onOpenCase={(id) => navigate('cases', caseNumberOf(id))}
            onOpenDigest={() => setIsDirectorDigestOpen(true)}
          />
        )}

        {current === 'indicators' && <IndicatorsView />}

        {current === 'cases' && (
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
            selectedCaseNumber={route.id === 'cases' ? route.param : null}
            onSelectCase={(number) => navigate('cases', number)}
          />
        )}

        {current === 'tasks' && <TasksView user={currentUser} />}

        {current === 'areas' && <AreasView areas={data.areas} />}
        {current === 'audit' && <AuditView events={data.auditEvents} userNames={data.userNames} />}
        {current === 'authority' && <AuthorityView requests={data.authorityRequests} />}
        {current === 'configuration' && (
          <ConfigurationView
            organization={organization}
            busy={pending > 0}
            onSaveIdentity={(i) => run(() => configApi.updateIdentity(i), 'toast.config_identity')}
            onPublishNotice={(ti, su, fu) => run(() => configApi.publishPrivacyNotice(ti, su, fu), 'toast.config_notice')}
            onPublishConsentText={(ty, ti, de, re) => run(() => configApi.publishConsentText(ty, ti, de, re), 'toast.config_consent_text')}
          />
        )}
        {current === 'about' && <AboutView organization={organization} areasCount={data.areas.length} />}
      </AppShell>

      {isDirectorDigestOpen && (
        <DirectorSharingInbox
          isOpen={isDirectorDigestOpen}
          onClose={() => setIsDirectorDigestOpen(false)}
          sharingEvents={sharingEventsList}
          onAcknowledge={handleAcknowledgeSharing}
          busy={pending > 0}
        />
      )}
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
  <EnvironmentProvider>
    <SessionProvider>
      <ToastProvider>
        <DemoBanner />
        <Gate />
      </ToastProvider>
    </SessionProvider>
  </EnvironmentProvider>
);

export default App;
