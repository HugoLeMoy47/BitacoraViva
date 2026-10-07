import { supabase } from './supabase';
import {
  Area,
  ArcoRequest,
  AuditEvent,
  AuthorityRequest,
  Case,
  CaseCurrentStatusDetail,
  CaseVulnerabilityMarker,
  CaseWithDetails,
  Consent,
  JournalEntry,
  Organization,
  Person,
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
  auditEvents: AuditEvent[];
  authorityRequests: AuthorityRequest[];
  sharingEvents: SharingEvent[];
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
  auditEvents: [],
  authorityRequests: [],
  sharingEvents: [],
};

async function rows<T>(query: PromiseLike<{ data: T[] | null; error: { message: string } | null }>): Promise<T[]> {
  const { data, error } = await query;
  if (error) throw new Error(error.message);
  return data || [];
}

function fullName(p?: { given_name: string; paternal_family_name: string } | null): string {
  return p ? `${p.given_name} ${p.paternal_family_name}` : '';
}

export async function loadOrgData(): Promise<OrgData> {
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
  ]);

  const areaById = new Map(areas.map((a) => [a.id, a]));
  const axisById = new Map(axes.map((a) => [a.id, a]));
  const valueById = new Map(values.map((v) => [v.id, v]));
  const personById = new Map(persons.map((p) => [p.id, p]));
  const caseById = new Map(cases.map((c) => [c.id, c]));
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
        vulnerabilities: markers.filter((m) => m.case_id === c.id),
        statuses,
        journal_entries: journalEntries.filter((e) => e.case_id === c.id),
        consents: consents
          .filter((k) => k.person_id === c.titular_person_id)
          .map((k) => ({ ...k, granted_by_name: userName(k.granted_by_user_id) })),
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
    auditEvents: audit,
    authorityRequests: authority,
    sharingEvents,
  };
}

// ------------------------------------------------------------------------------
// Escrituras: sólo vía funciones de la base
// ------------------------------------------------------------------------------

async function rpc<T = unknown>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) throw new Error(error.message);
  return data as T;
}

export interface NewCaseInput {
  given_name: string;
  paternal_family_name: string;
  maternal_family_name: string | null;
  preferred_name: string | null;
  birth_date: string;
  birth_date_is_estimated: boolean;
  sex_id: number;
  nationality_country_id: number;
  other_nationality: string | null;
  primary_language_id: number;
  other_language: string | null;
  phone_number: string | null;
  intake_window_type: 'fija' | 'movil' | 'transaccional';
  travels_with_family: boolean;
  intake_state_id: number;
  intake_municipality_id: number;
  intake_channel_id: number;
  entry_route_id: number;
  entry_date_str: string | null;
  assigned_area_id: string | null;
  vulnerability_codes: string[];
}

// Indicadores agregados con supresión de celdas pequeñas (Ethos E-05): `count` llega
// nulo cuando el grupo tiene menos de `min_group_size` personas.
export interface AggregateMetrics {
  min_group_size: number;
  generated_at: string;
  rows: { metric: string; bucket: string; count: number | null; suppressed: boolean }[];
}

export const api = {
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
      p_intake_municipality_id: i.intake_municipality_id,
      p_intake_channel_id: i.intake_channel_id,
      p_entry_route_id: i.entry_route_id,
      p_entry_date_str: i.entry_date_str,
      p_assigned_area_id: i.assigned_area_id,
      p_vulnerability_codes: i.vulnerability_codes,
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

  aggregateMetrics: () => rpc<AggregateMetrics>('fn_aggregate_metrics', {}),

  generateArcoAccessExtract: (personId: string) =>
    rpc<Record<string, unknown>>('fn_generate_arco_access_extract', { p_person_id: personId }),
};

export async function getTitularPersonId(caseId: string): Promise<string> {
  const { data, error } = await supabase.from('case').select('titular_person_id').eq('id', caseId).single();
  if (error) throw new Error(error.message);
  return data.titular_person_id as string;
}
