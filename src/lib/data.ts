import { supabase } from './supabase';
import { DbError } from './errors';
import {
  Area,
  CaseDate,
  ArcoRequest,
  AuditEvent,
  AuditChainVerification,
  AuthorityRequest,
  Case,
  CaseCurrentStatusDetail,
  CaseVulnerabilityMarker,
  CaseWithDetails,
  Consent,
  CaseFamilyView,
  DocumentType,
  FamilyMember,
  FamilyType,
  FamilyUnit,
  GeoMunicipality,
  GeoState,
  IntakeOption,
  JournalEntry,
  Organization,
  Person,
  PersonDocument,
  PrivacyNotice,
  ConsentText,
  SharingEvent,
  StatusAxis,
  StatusAxisCode,
  StatusValue,
  UserProfile,
} from '../types/database';

// Regla Dura 1: todo filtrado de acceso lo impone RLS en la base. Este módulo sólo
// lee lo que RLS devuelve y escribe exclusivamente mediante funciones (RPC) que
// validan rol y generan auditoría en la base (Reglas Duras 5 y 7).

const AXIS_CODES: StatusAxisCode[] = [
  'legal_status',
  'engagement_status',
  'shelter_status',
  'record_status',
  'case_stage',
];

export interface OrgData {
  organization: Organization | null;
  areas: Area[];
  statusAxes: StatusAxis[];
  statusValues: Record<StatusAxisCode, StatusValue[]>;
  cases: CaseWithDetails[];
  /** Tipos de documento de la organización (catálogo que administra dirección) */
  documentTypes: DocumentType[];
  /** Estados oficiales (INEGI) y catálogos de ingreso de la organización */
  geoStates: GeoState[];
  intakeChannels: IntakeOption[];
  entryRoutes: IntakeOption[];
  /** Tipos de familia y familias del sistema paralelo (E14 fase 3) */
  familyTypes: FamilyType[];
  familyUnits: FamilyUnit[];
  auditEvents: AuditEvent[];
  authorityRequests: AuthorityRequest[];
  sharingEvents: SharingEvent[];
  /** id de persona usuaria → nombre (sólo las que RLS permite ver) */
  userNames: Record<string, string>;
}

export const EMPTY_ORG_DATA: OrgData = {
  organization: null,
  areas: [],
  statusAxes: [],
  statusValues: {
    legal_status: [],
    engagement_status: [],
    shelter_status: [],
    record_status: [],
    case_stage: [],
  },
  cases: [],
  documentTypes: [],
  geoStates: [],
  intakeChannels: [],
  entryRoutes: [],
  familyTypes: [],
  familyUnits: [],
  auditEvents: [],
  authorityRequests: [],
  sharingEvents: [],
  userNames: {},
};

async function rows<T>(query: PromiseLike<{ data: T[] | null; error: { message: string; code?: string } | null }>): Promise<T[]> {
  const { data, error } = await query;
  if (error) throw new DbError(error.message, error.code);
  return data || [];
}

function fullName(p?: { given_name: string; paternal_family_name: string } | null): string {
  return p ? `${p.given_name} ${p.paternal_family_name}` : '';
}

/**
 * `caseAccess` falso = la persona sólo tiene roles de tareas (ADR-0007): no recibe expediente ni
 * catálogos de casos, así que ni se piden (RLS los devolvería vacíos). Sólo se leen la organización
 * y los nombres del personal, que sirven para rotular a quien tiene cada tarea.
 */
export async function loadOrgData(caseAccess = true): Promise<OrgData> {
  if (!caseAccess) {
    const [organizations, profiles] = await Promise.all([
      rows<Organization>(supabase.from('organization').select('*')),
      rows<UserProfile>(supabase.from('user_profile').select('*')),
    ]);
    return {
      ...EMPTY_ORG_DATA,
      organization: organizations[0] || null,
      userNames: Object.fromEntries(profiles.map((p) => [p.id, p.full_name])),
    };
  }

  const [
    organizations,
    areas,
    axes,
    values,
    cases,
    persons,
    caseStatuses,
    markers,
    journal,
    sharing,
    consents,
    arcos,
    profiles,
    audit,
    authority,
    documentTypes,
    personDocuments,
    geoStates,
    intakeChannels,
    entryRoutes,
    caseDates,
    familyTypes,
    familyUnits,
    familyMembers,
  ] = await Promise.all([
    rows<Organization>(supabase.from('organization').select('*')),
    rows<Area>(supabase.from('area').select('*').order('name')),
    rows<StatusAxis>(supabase.from('status_axis').select('*').order('sort_order')),
    rows<StatusValue>(supabase.from('status_value').select('*').order('sort_order')),
    rows<Case>(supabase.from('case').select('*').order('opened_at', { ascending: false })),
    rows<Person>(supabase.from('person').select('*')),
    rows<{
      case_id: string;
      axis_id: string;
      value_id: string;
      valid_from: string;
      reason: string;
    }>(supabase.from('case_status').select('case_id, axis_id, value_id, valid_from, reason').is('valid_to', null)),
    rows<CaseVulnerabilityMarker>(supabase.from('case_vulnerability_marker').select('*').is('removed_at', null)),
    rows<JournalEntry>(supabase.from('journal_entry').select('*').order('occurred_at', { ascending: false })),
    rows<SharingEvent>(supabase.from('sharing_event').select('*').order('shared_at', { ascending: false })),
    rows<Consent>(supabase.from('consent').select('*').order('granted_at', { ascending: false })),
    rows<ArcoRequest>(supabase.from('arco_request').select('*').order('received_at', { ascending: false })),
    // RLS: cada persona ve su perfil; dirección ve todos. Los nombres ausentes quedan vacíos.
    rows<UserProfile>(supabase.from('user_profile').select('*')),
    // RLS: sólo dirección obtiene filas de auditoría (Ethos C4).
    rows<AuditEvent>(supabase.from('audit_event').select('*').order('created_at', { ascending: false }).limit(500)),
    rows<AuthorityRequest>(supabase.from('authority_request').select('*').order('received_at', { ascending: false })),
    rows<DocumentType>(supabase.from('document_type').select('*').order('sort_order')),
    // RLS: solo roles que operan expedientes; el rol de solo lectura recibe vacío
    rows<PersonDocument>(supabase.from('person_document').select('*').order('created_at')),
    rows<GeoState>(supabase.from('geo_state').select('*').order('cve_ent')),
    rows<IntakeOption>(supabase.from('intake_channel').select('*').order('sort_order')),
    rows<IntakeOption>(supabase.from('entry_route').select('*').order('sort_order')),
    // RLS: solo roles que operan expedientes
    rows<CaseDate>(supabase.from('case_date').select('*').order('created_at')),
    rows<FamilyType>(supabase.from('family_type').select('*').order('sort_order')),
    // RLS: solo roles que operan expedientes
    rows<FamilyUnit>(supabase.from('family_unit').select('*').order('family_number')),
    rows<FamilyMember>(supabase.from('family_member').select('*').is('valid_to', null)),
  ]);

  const areaById = new Map(areas.map((a) => [a.id, a]));
  const axisById = new Map(axes.map((a) => [a.id, a]));
  const valueById = new Map(values.map((v) => [v.id, v]));
  const personById = new Map(persons.map((p) => [p.id, p]));
  const caseById = new Map(cases.map((c) => [c.id, c]));
  const documentTypeById = new Map(documentTypes.map((d) => [d.id, d]));
  // Familias: cada persona (por su expediente) tiene a lo sumo una pertenencia vigente
  const familyTypeById = new Map(familyTypes.map((t) => [t.id, t]));
  const familyUnitById = new Map(familyUnits.map((u) => [u.id, u]));
  const membersByUnit = new Map<string, FamilyMember[]>();
  for (const m of familyMembers) membersByUnit.set(m.family_unit_id, [...(membersByUnit.get(m.family_unit_id) ?? []), m]);
  const memberByCase = new Map(familyMembers.map((m) => [m.case_id, m]));
  const familyOf = (caseId: string): CaseFamilyView | null => {
    const mine = memberByCase.get(caseId);
    const unit = mine ? familyUnitById.get(mine.family_unit_id) : undefined;
    if (!mine || !unit) return null;
    const members = (membersByUnit.get(unit.id) ?? [])
      .map((m) => {
        const c = caseById.get(m.case_id);
        return { caseId: m.case_id, caseNumber: c?.case_number ?? '', personName: fullName(c ? personById.get(c.titular_person_id) : null), order: m.member_order ?? null };
      })
      .sort((a, b) => (a.order ?? 1e9) - (b.order ?? 1e9) || a.caseNumber.localeCompare(b.caseNumber));
    return { unit, typeLabel: unit.family_type_id ? familyTypeById.get(unit.family_type_id)?.label_es ?? null : null, order: mine.member_order ?? null, members };
  };
  const userName = (id?: string | null) => profiles.find((p) => p.id === id)?.full_name;

  const statusValues = { ...EMPTY_ORG_DATA.statusValues };
  for (const code of AXIS_CODES) statusValues[code] = [];
  for (const v of values) {
    const axis = axisById.get(v.axis_id);
    if (axis) statusValues[axis.code].push(v);
  }

  const sharingEvents: SharingEvent[] = sharing.map((s) => ({
    ...s,
    case_number: caseById.get(s.case_id)?.case_number,
    from_area_name: areaById.get(s.from_area_id)?.name,
    to_area_name: areaById.get(s.to_area_id)?.name,
    shared_by_name: userName(s.shared_by_user_id),
    acknowledged_by_name: userName(s.acknowledged_by_user_id),
  }));
  const sharingByEntry = new Map<string, SharingEvent>();
  // sharing ya viene de más reciente a más antigua: conserva el primero por entrada
  for (const s of sharingEvents) if (!sharingByEntry.has(s.journal_entry_id)) sharingByEntry.set(s.journal_entry_id, s);

  const journalEntries: JournalEntry[] = journal.map((e) => ({
    ...e,
    case_number: caseById.get(e.case_id)?.case_number,
    area_code: areaById.get(e.area_id)?.code,
    area_name: areaById.get(e.area_id)?.name,
    author_name: userName(e.author_user_id),
    sharing_event: sharingByEntry.get(e.id) || null,
  }));

  const statusesByCase = new Map<string, Record<string, CaseCurrentStatusDetail>>();
  for (const cs of caseStatuses) {
    const axis = axisById.get(cs.axis_id);
    const value = valueById.get(cs.value_id);
    if (!axis || !value) continue;
    const bucket = statusesByCase.get(cs.case_id) || {};
    bucket[axis.code] = {
      valueCode: value.code,
      label: value.label_es,
      valid_from: cs.valid_from,
      reason: cs.reason,
      isActiveCare: value.is_active_care,
    };
    statusesByCase.set(cs.case_id, bucket);
  }

  const noStatus = (): CaseCurrentStatusDetail => ({
    valueCode: 'undetermined',
    label: '—',
    valid_from: '',
    reason: '',
  });

  const detailed: CaseWithDetails[] = cases
    .filter((c) => personById.has(c.titular_person_id))
    .map((c) => {
      const bucket = statusesByCase.get(c.id) || {};
      const statuses = Object.fromEntries(
        AXIS_CODES.map((code) => [code, bucket[code] || noStatus()])
      ) as CaseWithDetails['statuses'];

      return {
        ...c,
        person: personById.get(c.titular_person_id)!,
        parentCaseNumber: c.parent_case_id ? caseById.get(c.parent_case_id)?.case_number ?? null : null,
        vulnerabilities: markers.filter((m) => m.case_id === c.id).map((m) => ({ ...m, affirmed_by_name: userName(m.affirmed_by) })),
        statuses,
        journal_entries: journalEntries.filter((e) => e.case_id === c.id),
        consents: consents
          .filter((k) => k.person_id === c.titular_person_id)
          .map((k) => ({ ...k, granted_by_name: userName(k.granted_by_user_id) })),
        dates: caseDates.filter((d) => d.case_id === c.id),
        family: familyOf(c.id),
        documents: personDocuments
          .filter((d) => d.person_id === c.titular_person_id)
          .map((d) => ({ ...d, type_label: documentTypeById.get(d.document_type_id)?.label_es ?? '—' })),
        arco_requests: arcos
          .filter((r) => r.person_id === c.titular_person_id)
          .map((r) => ({
            ...r,
            person_name: fullName(personById.get(r.person_id)),
            case_number: r.case_id ? caseById.get(r.case_id)?.case_number : undefined,
            handled_by_name: userName(r.handled_by_user_id),
          })),
      };
    });

  for (const c of detailed) {
    c.subfolios = detailed.filter((s) => s.parent_case_id === c.id);
  }

  return {
    organization: organizations[0] || null,
    areas,
    statusAxes: axes,
    statusValues,
    cases: detailed,
    documentTypes,
    geoStates,
    intakeChannels,
    entryRoutes,
    familyTypes,
    familyUnits,
    auditEvents: audit,
    authorityRequests: authority,
    sharingEvents,
    userNames: Object.fromEntries(profiles.map((p) => [p.id, p.full_name])),
  };
}

// ------------------------------------------------------------------------------
// Escrituras: sólo vía funciones de la base
// ------------------------------------------------------------------------------

async function rpc<T = unknown>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) throw new DbError(error.message, error.code);
  return data as T;
}

// Consentimiento que la persona otorga en el paso cero del alta. La base exige el general,
// y el expreso para datos sensibles antes de aceptar marcadores de vulnerabilidad (P-06).
export interface ConsentInput {
  consent_type: 'general_care' | 'sensitive_data' | 'internal_sharing' | 'secondary_use_research';
  status: 'granted';
  is_minor_assent: boolean;
  legal_guardian_name?: string | null;
  legal_guardian_role?: string | null;
  authority_letter_ref?: string | null;
  notes?: string | null;
}

export interface SubfolioInput {
  parent_case_id: string;
  given_name: string;
  paternal_family_name: string;
  maternal_family_name: string | null;
  preferred_name: string | null;
  birth_date: string;
  birth_date_is_estimated: boolean;
  // Datos sensibles (D-14): vacíos si no hay consentimiento sensible
  sex_id: number | null;
  nationality_country_id: number | null;
  other_nationality: string | null;
  primary_language_id: number | null;
  other_language: string | null;
  guardian_role: string;
  justification: string;
  vulnerability_codes: string[];
  consents: { consent_type: ConsentInput['consent_type']; status: 'granted'; is_minor_assent: boolean }[];
}

export interface NewCaseInput {
  given_name: string;
  paternal_family_name: string;
  maternal_family_name: string | null;
  preferred_name: string | null;
  birth_date: string;
  birth_date_is_estimated: boolean;
  // Datos sensibles (D-14): solo con consentimiento sensible; sin él van vacíos, nunca un valor supuesto
  sex_id: number | null;
  nationality_country_id: number | null;
  other_nationality: string | null;
  primary_language_id: number | null;
  other_language: string | null;
  phone_number: string | null;
  /** Obligatorio: quien captura lo elige, no hay valor por defecto */
  intake_window_type: 'fija' | 'movil' | 'transaccional';
  // Contexto de ingreso: opcional; vacío = «No registrado»
  travels_with_family: boolean | null;
  intake_state_id: number | null;
  /** Clave del INEGI (5 dígitos) */
  intake_municipality_key: string | null;
  intake_channel_id: number | null;
  entry_route_id: number | null;
  entry_date_str: string | null;
  /** Fechas del caso con su precisión (E14 fase 2); se registran junto con el alta */
  dates: { kind: 'nation_entry' | 'nation_exit' | 'shelter_entry' | 'shelter_exit'; value: string; precision: 'day' | 'month' | 'year' }[];
  assigned_area_id: string | null;
  vulnerability_codes: string[];
  consents: ConsentInput[];
}

// Indicadores agregados con supresión de celdas pequeñas (Ethos E-05): `count` llega
// nulo cuando el grupo tiene menos de `min_group_size` personas. `prev_*` son las cifras del
// periodo inmediato anterior de igual duración (con su propia supresión), sólo si se dio un periodo.
export interface AggregateMetricRow {
  metric: string;
  bucket: string;
  count: number | null;
  value: number | null;
  suppressed: boolean;
  /** Por qué se oculta: «small» (menos de 5) o «complement» (se oculta junto a una celda pequeña para que no se deduzca por resta, R-19) */
  hidden_reason: 'small' | 'complement' | null;
  prev_count: number | null;
  prev_value: number | null;
}

export interface AggregateMetrics {
  min_group_size: number;
  /** Dirección ve cifras exactas; el resto, redondeadas a múltiplos de `rounded_to` (R-19) */
  exact: boolean;
  rounded_to: number | null;
  generated_at: string;
  period: { from: string | null; to: string | null; prev_from: string | null; prev_to: string | null };
  rows: AggregateMetricRow[];
}

// Historial de un eje de estatus (cada fila es un intervalo con su inicio y cierre).
export interface StageHistoryRow {
  case_id: string;
  value_id: string;
  valid_from: string;
  valid_to: string | null;
}

export interface CaseStatusHistoryRow {
  axis_id: string;
  value_id: string;
  valid_from: string;
  valid_to: string | null;
  reason: string;
  created_by: string | null;
}

export const api = {
  loadCaseStatusHistory: (caseId: string) =>
    rows<CaseStatusHistoryRow>(
      supabase
        .from('case_status')
        .select('axis_id, value_id, valid_from, valid_to, reason, created_by')
        .eq('case_id', caseId)
        .order('valid_from', { ascending: false })
    ),
  loadStageHistory: (axisId: string) =>
    rows<StageHistoryRow>(
      supabase.from('case_status').select('case_id, value_id, valid_from, valid_to').eq('axis_id', axisId)
    ),

  createCaseWithPerson: (i: NewCaseInput) =>
    rpc<string>('fn_create_case_with_person', {
      p_given_name: i.given_name,
      p_paternal_family_name: i.paternal_family_name,
      p_maternal_family_name: i.maternal_family_name,
      p_preferred_name: i.preferred_name,
      p_birth_date: i.birth_date,
      p_birth_date_is_estimated: i.birth_date_is_estimated,
      p_sex_id: i.sex_id,
      p_nationality_country_id: i.nationality_country_id,
      p_other_nationality: i.other_nationality,
      p_primary_language_id: i.primary_language_id,
      p_other_language: i.other_language,
      p_phone_number: i.phone_number,
      p_intake_window_type: i.intake_window_type,
      p_travels_with_family: i.travels_with_family,
      p_intake_state_id: i.intake_state_id,
      p_intake_municipality_key: i.intake_municipality_key,
      p_intake_channel_id: i.intake_channel_id,
      p_entry_route_id: i.entry_route_id,
      p_entry_date_str: i.entry_date_str,
      p_assigned_area_id: i.assigned_area_id,
      p_vulnerability_codes: i.vulnerability_codes,
      p_consents: i.consents,
      p_dates: i.dates,
    }),

  createSubfolio: (i: SubfolioInput) =>
    rpc<string>('fn_create_subfolio', {
      p_parent_case_id: i.parent_case_id,
      p_given_name: i.given_name,
      p_paternal_family_name: i.paternal_family_name,
      p_maternal_family_name: i.maternal_family_name,
      p_preferred_name: i.preferred_name,
      p_birth_date: i.birth_date,
      p_birth_date_is_estimated: i.birth_date_is_estimated,
      p_sex_id: i.sex_id,
      p_nationality_country_id: i.nationality_country_id,
      p_other_nationality: i.other_nationality,
      p_primary_language_id: i.primary_language_id,
      p_other_language: i.other_language,
      p_guardian_role: i.guardian_role,
      p_justification: i.justification,
      p_vulnerability_codes: i.vulnerability_codes,
      p_consents: i.consents,
    }),

  changeCaseStatus: (caseId: string, axisCode: string, newValueCode: string, reason: string) =>
    rpc('fn_change_case_status', {
      p_case_id: caseId,
      p_axis_code: axisCode,
      p_new_value_code: newValueCode,
      p_reason: reason,
    }),

  createJournalEntry: (e: {
    case_id: string;
    entry_type_key: string;
    body: string;
    occurred_at: string;
    is_work_note: boolean;
    area_id: string | null;
  }) =>
    rpc<string>('fn_create_journal_entry', {
      p_case_id: e.case_id,
      p_entry_type_key: e.entry_type_key,
      p_body: e.body,
      p_occurred_at: e.occurred_at,
      p_is_work_note: e.is_work_note,
      p_area_id: e.area_id,
    }),

  createClarificationNote: (supersededId: string, body: string, occurredAt: string, isWorkNote: boolean) =>
    rpc<string>('fn_create_clarification_note', {
      p_superseded_entry_id: supersededId,
      p_body: body,
      p_occurred_at: occurredAt,
      p_is_work_note: isWorkNote,
    }),

  shareJournalEntry: (entryId: string, toAreaId: string, reason: string) =>
    rpc<string>('fn_share_journal_entry', {
      p_journal_entry_id: entryId,
      p_to_area_id: toAreaId,
      p_reason: reason,
    }),

  acknowledgeSharing: (sharingEventId: string) =>
    rpc('fn_acknowledge_sharing', { p_sharing_event_id: sharingEventId }),

  registerConsent: (c: {
    person_id: string;
    case_id: string | null;
    consent_type: string;
    status: string;
    is_minor_assent: boolean;
    legal_guardian_name?: string | null;
    legal_guardian_role?: string | null;
    authority_letter_ref?: string | null;
    notes?: string | null;
  }) =>
    rpc<string>('fn_register_consent', {
      p_person_id: c.person_id,
      p_consent_type: c.consent_type,
      p_status: c.status,
      p_case_id: c.case_id,
      p_is_minor_assent: c.is_minor_assent,
      p_legal_guardian_name: c.legal_guardian_name ?? null,
      p_legal_guardian_role: c.legal_guardian_role ?? null,
      p_authority_letter_ref: c.authority_letter_ref ?? null,
      p_notes: c.notes ?? null,
    }),

  rectifyPerson: (p: Person, reason: string) =>
    rpc('fn_rectify_person', {
      p_person_id: p.id,
      p_given_name: p.given_name,
      p_paternal_family_name: p.paternal_family_name,
      p_maternal_family_name: p.maternal_family_name ?? null,
      p_preferred_name: p.preferred_name ?? null,
      p_birth_date: p.birth_date,
      p_birth_date_is_estimated: p.birth_date_is_estimated,
      p_sex_id: p.sex_id,
      p_nationality_country_id: p.nationality_country_id,
      p_phone_number: p.phone_number ?? null,
      p_email: p.email ?? null,
      p_reason: reason,
    }),

  anonymizePerson: (personId: string, reason: string) =>
    rpc('fn_anonymize_person', { p_person_id: personId, p_reason: reason }),

  applyOpposition: (personId: string, reason: string) =>
    rpc('fn_apply_opposition', { p_person_id: personId, p_reason: reason }),

  aggregateMetrics: (from: string | null = null, to: string | null = null) =>
    rpc<AggregateMetrics>('fn_aggregate_metrics', { p_from: from, p_to: to }),

  generateArcoAccessExtract: (personId: string) =>
    rpc<Record<string, unknown>>('fn_generate_arco_access_extract', { p_person_id: personId }),

  // Familia del sistema paralelo (E14 fase 3): asignar, mover, quitar o crear en el mismo paso
  setCaseFamily: (caseId: string, familyUnitId: string | null, order: number | null, reason?: string, newNumber?: string, newTypeId?: string | null) =>
    rpc<string | null>('fn_set_case_family', {
      p_case_id: caseId,
      p_family_unit_id: familyUnitId,
      p_member_order: order,
      p_reason: reason?.trim() || null,
      p_new_family_number: newNumber?.trim() || null,
      p_new_family_type_id: newTypeId ?? null,
    }),

  setFamilyType: (familyUnitId: string, typeId: string | null, reason?: string) =>
    rpc('fn_set_family_type', { p_family_unit_id: familyUnitId, p_family_type_id: typeId, p_reason: reason?.trim() || null }),

  // Ingreso o egreso del albergue: el estatus de alojamiento y la fecha del movimiento, en una sola operación (E14 fase 2b)
  changeShelterStatus: (caseId: string, newValueCode: string, reason: string, date: string, precision: string) =>
    rpc<string>('fn_change_shelter_status', {
      p_case_id: caseId,
      p_new_value_code: newValueCode,
      p_reason: reason,
      p_date: date,
      p_precision: precision,
    }),

  // Una fecha del caso: se corrige o se quita con motivo (E14 fase 2). Con valor vacío la quita.
  setCaseDate: (caseId: string, kind: string, value: string | null, precision: string | null, reason?: string) =>
    rpc<string | null>('fn_set_case_date', {
      p_case_id: caseId,
      p_kind: kind,
      p_value: value,
      p_precision: precision,
      p_reason: reason?.trim() || null,
    }),

  // Municipios de un estado (catálogo oficial del INEGI): se piden al elegir el estado, no todos de golpe
  listMunicipalities: (stateKey: string) =>
    rows<GeoMunicipality>(supabase.from('geo_municipality').select('*').eq('cve_ent', stateKey).order('name')),

  // E14 fase 1: documentos, religión, detalle de marcadores y referencia heredada
  setPersonDocument: (personId: string, documentTypeId: string, documentNumber: string, reason?: string) =>
    rpc<string>('fn_set_person_document', {
      p_person_id: personId,
      p_document_type_id: documentTypeId,
      p_document_number: documentNumber,
      p_reason: reason?.trim() || null,
    }),

  removePersonDocument: (documentId: string, reason: string) =>
    rpc('fn_remove_person_document', { p_document_id: documentId, p_reason: reason }),

  setPersonReligion: (personId: string, religion: string, reason?: string) =>
    rpc('fn_set_person_religion', { p_person_id: personId, p_religion: religion, p_reason: reason?.trim() || null }),

  setMarkerDetail: (caseId: string, markerCode: string, detail: string) =>
    rpc('fn_set_marker_detail', { p_case_id: caseId, p_marker_code: markerCode, p_detail: detail }),

  setCaseLegacyReference: (caseId: string, reference: string, reason?: string) =>
    rpc('fn_set_case_legacy_reference', { p_case_id: caseId, p_reference: reference, p_reason: reason?.trim() || null }),

  readCaseDetail: (caseId: string) =>
    rpc<boolean>('fn_read_case_detail', { p_case_id: caseId }),

  verifyAuditChain: (orgId?: string) =>
    rpc<AuditChainVerification[]>('fn_verify_audit_chain', { p_org_id: orgId ?? null }),
};

export const dataApi = api;

// Aviso de privacidad vigente de la organización (P-13). Hoy es el texto de la semilla;
// el objetivo es que cada asociación cargue el suyo (p. ej. un PDF) desde su configuración.
export async function getActivePrivacyNotice(): Promise<PrivacyNotice | null> {
  const { data, error } = await supabase
    .from('privacy_notice')
    .select('*')
    .eq('active', true)
    .order('effective_date', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw new DbError(error.message, error.code);
  return (data as PrivacyNotice) || null;
}

// Versiones del aviso de privacidad de la organización, de la más reciente a la más antigua.
export async function listPrivacyNotices(): Promise<PrivacyNotice[]> {
  return rows<PrivacyNotice>(supabase.from('privacy_notice').select('*').order('created_at', { ascending: false }));
}

// Textos de consentimiento: todas las versiones (historial) o solo las vigentes (alta de expedientes).
export async function listConsentTexts(onlyActive = false): Promise<ConsentText[]> {
  let q = supabase.from('consent_text').select('*');
  if (onlyActive) q = q.eq('active', true);
  return rows<ConsentText>(q.order('consent_type').order('version', { ascending: false }));
}

// Configuración de la organización (E9): solo dirección; la base lo vuelve a exigir.
export interface OrganizationIdentityInput {
  display_name: string;
  legal_name: string;
  folio_prefix: string;
  about_text: string;
  responsible_name: string;
  responsible_address: string;
  responsible_contact: string;
  arco_contact: string;
}

export const configApi = {
  updateIdentity: (i: OrganizationIdentityInput) =>
    rpc<string>('fn_update_organization_identity', {
      p_display_name: i.display_name,
      p_legal_name: i.legal_name,
      p_folio_prefix: i.folio_prefix,
      p_about_text: i.about_text,
      p_responsible_name: i.responsible_name,
      p_responsible_address: i.responsible_address,
      p_responsible_contact: i.responsible_contact,
      p_arco_contact: i.arco_contact,
    }),
  publishPrivacyNotice: (title: string, summary: string, fullText: string) =>
    rpc<string>('fn_publish_privacy_notice', { p_title: title, p_summary: summary, p_full_text: fullText }),
  publishConsentText: (type: string, title: string, description: string, required: boolean) =>
    rpc<string>('fn_publish_consent_text', { p_consent_type: type, p_title: title, p_description: description, p_required: required }),
  updateSecuritySettings: (enforceAbsoluteSessionTimeout: boolean) =>
    rpc<string>('fn_update_organization_security_settings', {
      p_enforce_absolute_session_timeout: enforceAbsoluteSessionTimeout,
    }),
};
