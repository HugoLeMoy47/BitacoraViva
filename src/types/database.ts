// ==============================================================================
// Bitácora Viva — Tipos TypeScript para Base de Datos y Dominio
// Fuente de verdad: 50_Productos/BitacoraViva/20_arquitectura/modelo-de-datos.md
// Alineación: Ethos v1.2, RNF v1.0, MAP-OIM v3
// ==============================================================================

export type RoleName = 'viewer' | 'caseworker' | 'intake_officer' | 'director';

export type AreaCode = 'legal' | 'psicologia' | 'trabajo_social' | 'medica' | 'coordinacion';

export type AuditAction = 'INSERT' | 'UPDATE' | 'DELETE' | 'LOGIN' | 'EXPORT' | 'STATUS_CHANGE';

export interface Organization {
  id: string;
  slug: string;
  legal_name: string;
  display_name: string;
  active: boolean;
  created_at: string;
  updated_at: string;
}

export interface Role {
  name: RoleName;
  description: string;
  created_at: string;
}

export interface UserProfile {
  id: string;
  organization_id: string;
  email: string;
  full_name: string;
  active: boolean;
  created_at: string;
  updated_at: string;
}

export interface UserRole {
  id: string;
  user_id: string;
  role_name: RoleName;
  area_id: string | null;
  granted_by: string | null;
  granted_at: string;
  revoked_by?: string | null;
  revoked_at?: string | null;
}

export interface Area {
  id: string;
  organization_id: string;
  code: AreaCode;
  name: string;
  active: boolean;
  created_at: string;
}

export interface AuthorityRequest {
  id: string;
  organization_id: string;
  case_id?: string | null;
  authority_name: string;
  request_type: string;
  official_letter_ref: string;
  received_at: string;
  handled_by_user_id?: string | null;
  response_summary?: string | null;
  extract_delivered: boolean;
  created_at: string;
  updated_at?: string;
}

export interface AuditEvent {
  id: string;
  organization_id: string;
  user_id: string | null;
  action: AuditAction;
  table_name: string;
  record_id: string | null;
  old_values: Record<string, unknown> | null;
  new_values: Record<string, unknown> | null;
  ip_address?: string | null;
  user_agent?: string | null;
  created_at: string;
}

// ------------------------------------------------------------------------------
// Tipos de Dominio MAP-OIM v3 (Épica E3: Persona y Caso)
// ------------------------------------------------------------------------------

export interface Person {
  id: string;
  organization_id: string;
  given_name: string;
  paternal_family_name: string;
  maternal_family_name: string;
  preferred_name?: string | null;
  birth_date: string;
  birth_date_is_estimated: boolean;
  sex_id: number;
  other_sex?: string | null;
  nationality_country_id: number;
  other_nationality?: string | null;
  origin_department_id?: number | null;
  is_self_identified_migrant: boolean;
  migration_profile_id?: number | null;
  other_profile?: string | null;
  primary_language_id: number;
  other_language?: string | null;
  education_level_id?: number | null;
  marital_status_id?: number | null;
  occupations: string[];
  phone_number?: string | null;
  email?: string | null;
  address_line?: string | null;
  neighborhood?: string | null;
  postal_code?: string | null;
  is_anonymized: boolean;
  anonymized_at?: string | null;
  anonymized_by?: string | null;
  created_at: string;
  updated_at: string;
}

export interface Case {
  id: string;
  organization_id: string;
  case_number: string;
  parent_case_id?: string | null;
  previous_case_id?: string | null;
  titular_person_id: string;
  intake_state_id: number;
  intake_municipality_id: number;
  intake_channel_id: number;
  intake_window_type: 'fija' | 'movil' | 'transaccional';
  intake_date: string;
  entry_route_id: number;
  entry_date_str?: string | null;
  travels_with_family: boolean;
  opened_at: string;
  opened_by: string;
  closed_at?: string | null;
  closed_by?: string | null;
  closure_reason?: string | null;
  assigned_area_id?: string | null;
  assigned_user_id?: string | null;
}

export type VulnerabilityMarkerCode =
  | 'pregnant_or_lactating'
  | 'unaccompanied_child'
  | 'separated_child'
  | 'victim_of_violence'
  | 'medical_condition'
  | 'disability'
  | 'lgbtiq'
  | 'indigenous_language_speaker'
  | 'stateless_or_at_risk'
  | 'survivor_torture_trauma'
  | 'international_protection_need'
  | 'older_person_at_risk'
  | 'other_vulnerability';

export interface CaseVulnerabilityMarker {
  id: string;
  case_id: string;
  marker_code: VulnerabilityMarkerCode;
  notes?: string | null;
  affirmed_by: string;
  affirmed_at: string;
  removed_by?: string | null;
  removed_at?: string | null;
}
