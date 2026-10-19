// ==============================================================================
// Bitácora Viva — Tipos TypeScript para Base de Datos y Dominio
// Fuente de verdad: 50_Productos/BitacoraViva/20_arquitectura/modelo-de-datos.md
// Alineación: Ethos v1.2, RNF v1.0, MAP-OIM v3 (Épicas E1, E2 y E3)
// ==============================================================================

// Cuatro roles de casos y dos que sólo operan en tareas (ADR-0007). Una persona puede tener varios.
export type RoleName = 'viewer' | 'caseworker' | 'intake_officer' | 'director' | 'task_manager' | 'volunteer';

export type AuditAction = 
  | 'INSERT' 
  | 'UPDATE' 
  | 'DELETE' 
  | 'LOGIN' 
  | 'EXPORT' 
  | 'STATUS_CHANGE'
  | 'CLARIFICATION'
  | 'SHARE'
  | 'ACKNOWLEDGE'
  | 'RECTIFICATION'
  | 'ANONYMIZATION'
  | 'OPPOSITION'
  | 'CONSENT_GRANTED'
  | 'CONSENT_REVOKED'
  | 'ARCO_ACCESS_EXTRACT_ISSUED'
  | 'EVIDENCE_ACCESS'
  | 'READ_CASE';

// ---- Seguidor de tareas (E7) ----
export type TaskStatus = 'pending' | 'in_progress' | 'done';

export interface Task {
  id: string;
  organization_id: string;
  name: string;
  details: string | null;
  status: TaskStatus;
  photo_required: boolean;
  assigned_to: string | null;
  /** Cuándo la tomó la persona del pool; nulo si la asignó coordinación */
  claimed_at: string | null;
  /** Vencimiento (fecha, sin hora) */
  due_at: string | null;
  started_at: string | null;
  done_at: string | null;
  task_category_id: string | null;
  work_area_id: string | null;
  routine_template_id: string | null;
  /** Vínculo con un caso (BV-7.16): sólo el folio llega al voluntariado, nunca más dato del caso */
  case_id: string | null;
  case_number: string | null;
  case_task_kind_id: string | null;
  created_at: string;
  created_by: string | null;
  updated_at: string;
  archived_at: string | null;
}

export interface TaskCategory {
  id: string;
  organization_id: string;
  key: string;
  label_es: string;
  sort_order: number;
  archived_at: string | null;
}

/** Tipo de tarea ligada a un caso: catálogo neutro, sin texto libre (decisión 6a). */
export type CaseTaskKind = TaskCategory;

/** Plantilla de rutina: tareas recurrentes agrupadas bajo un perfil de jornada. */
export interface RoutineTemplate {
  id: string;
  organization_id: string;
  name: string;
  description: string | null;
  work_area_id: string | null;
  task_category_id: string | null;
  created_at: string;
  archived_at: string | null;
}

export interface RoutineTemplateItem {
  id: string;
  organization_id: string;
  routine_template_id: string;
  name: string;
  details: string | null;
  sort_order: number;
  photo_required: boolean;
  work_area_id: string | null;
  task_category_id: string | null;
  archived_at: string | null;
}

export type ShiftKind = 'morning' | 'afternoon' | 'night' | 'general';

/** Recado de turno: texto libre para el turno siguiente. NO es una entrada de bitácora de caso. */
export interface TaskEvidence {
  id: string;
  organization_id: string;
  task_id: string;
  storage_path: string;
  mime_type: 'image/jpeg' | 'image/png' | 'image/webp';
  size_bytes: number;
  created_at: string;
  created_by: string | null;
  archived_at: string | null;
}

export interface ShiftNote {
  id: string;
  organization_id: string;
  work_area_id: string | null;
  note_date: string;
  shift: ShiftKind;
  body: string;
  created_at: string;
  created_by: string | null;
  archived_at: string | null;
}

export type ShiftNoteScope = 'all' | 'area' | 'own';

/** Ajustes de operación del Seguidor de tareas (una fila por organización). */
export interface TaskSetting {
  id: string;
  organization_id: string;
  shift_note_scope: ShiftNoteScope;
  shift_note_days: number;
  pool_max_unstarted: number;
  pool_release_days: number;
}

/** Espacio físico del inmueble (cocina, dormitorios). No es `Area`, que es funcional. */
export interface WorkArea {
  id: string;
  organization_id: string;
  key: string;
  label_es: string;
  sort_order: number;
  archived_at: string | null;
}

export interface Organization {
  id: string;
  slug: string;
  legal_name: string;
  display_name: string;
  active: boolean;
  folio_prefix?: string | null;
  about_text?: string | null;
  responsible_name?: string | null;
  responsible_address?: string | null;
  responsible_contact?: string | null;
  arco_contact?: string | null;
  enforce_absolute_session_timeout?: boolean;
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
  /** Código interno estable (no cambia al renombrar) */
  code: string;
  name: string;
  active: boolean;
  /** Área general: donde escribe en la bitácora quien no tiene área (una por organización) */
  is_general: boolean;
  /** La que se propone al abrir un expediente (una por organización) */
  is_default_intake: boolean;
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
  case_id?: string | null;
  old_values: Record<string, unknown> | null;
  new_values: Record<string, unknown> | null;
  ip_address?: string | null;
  user_agent?: string | null;
  seq?: number;
  prev_hash?: string | null;
  event_hash?: string | null;
  created_at: string;
}

export interface AuditChainVerification {
  organization_id: string;
  total_events: number;
  is_valid: boolean;
  broken_at_seq: number | null;
  reason: string;
}

// ------------------------------------------------------------------------------
// Tipos de Dominio MAP-OIM v3 (Épica E3: Persona y Caso)
// ------------------------------------------------------------------------------

export interface Person {
  id: string;
  organization_id: string;
  given_name: string;
  paternal_family_name: string;
  maternal_family_name?: string | null;
  preferred_name?: string | null;
  birth_date: string;
  birth_date_is_estimated: boolean;
  // Sin valor por defecto (E14 fase 1b): vacío = «No registrado»
  sex_id?: number | null;
  other_sex?: string | null;
  nationality_country_id?: number | null;
  other_nationality?: string | null;
  origin_department_id?: number | null;
  is_self_identified_migrant?: boolean | null;
  migration_profile_id?: number | null;
  other_profile?: string | null;
  primary_language_id?: number | null;
  other_language?: string | null;
  /** Columnas numéricas antiguas de MAP-OIM v3: sin uso desde E15 (ver `*_item_id`) */
  education_level_id?: number | null;
  marital_status_id?: number | null;
  occupations: string[];
  /** Ficha completa (E15 fase 1): valores de diccionarios editables; vacío = «No registrado» */
  education_level_item_id?: string | null;
  marital_status_item_id?: string | null;
  origin_department_item_id?: string | null;
  phone_number?: string | null;
  email?: string | null;
  address_line?: string | null;
  neighborhood?: string | null;
  postal_code?: string | null;
  /** Datos sensibles (D-14): valor del diccionario + detalle; solo con consentimiento sensible vigente */
  religion_item_id?: string | null;
  religion_detail?: string | null;
  primary_language_item_id?: string | null;
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
  // Contexto de ingreso: sin valor por defecto; vacío = «No registrado»
  intake_state_id?: number | null;
  /** Clave del INEGI (5 dígitos) */
  intake_municipality_key?: string | null;
  intake_channel_id?: number | null;
  intake_window_type: 'fija' | 'movil' | 'transaccional';
  intake_date: string;
  entry_route_id?: number | null;
  entry_date_str?: string | null;
  travels_with_family?: boolean | null;
  opened_at: string;
  opened_by: string;
  closed_at?: string | null;
  closed_by?: string | null;
  closure_reason?: string | null;
  assigned_area_id?: string | null;
  assigned_user_id?: string | null;
  /** EXPEDIENTE de la hoja de casos anterior (E14); el folio de caso del sistema no cambia */
  legacy_reference?: string | null;
  /** Número de referencia: folio manual, texto corto (E15 fase 1) */
  reference_number?: string | null;
  /** Plan al ingreso: valor del eje jurídico (E14 fase 4b); vacío = «No registrado» */
  intake_plan_value_id?: string | null;
  created_at: string;
  updated_at: string;
}

/** Valor de un diccionario editable (idioma, religión…); `no_response` = «La persona no quiso responder» (del sistema) */
export interface CatalogItem {
  id: string;
  organization_id: string;
  catalog: 'language' | 'religion' | 'specific_need' | 'service_line' | 'education_level' | 'marital_status' | 'occupation' | 'department' | 'family_role';
  /** Solo el departamento: país (de la lista de nacionalidades) al que pertenece; null en los demás y en «no quiso responder» */
  country_id?: number | null;
  key: string;
  label_es: string;
  legacy_code?: string | null;
  is_active: boolean;
  is_system: boolean;
  sort_order: number;
}

/** Pregunta de la ficha social (E15 fase 2): la administran dirección y Trabajo Social */
export interface SocialQuestion {
  id: string;
  organization_id: string;
  key: string;
  label_es: string;
  section: 'migration' | 'sensitive' | 'origin';
  answer_type: 'yes_no' | 'number' | 'text' | 'date';
  has_detail: boolean;
  is_sensitive: boolean;
  is_active: boolean;
  sort_order: number;
}

/** Respuesta vigente de un expediente a una pregunta de la ficha social */
export interface SocialAnswer {
  id: string;
  case_id: string;
  question_id: string;
  choice?: 'yes' | 'no' | 'no_response' | null;
  number_value?: number | null;
  text_value?: string | null;
  date_value?: string | null;
  date_precision?: 'day' | 'month' | 'year' | null;
  detail?: string | null;
}

/** Grupo por edad configurable (E14 fase 5): empieza en `min_age` y termina donde empieza el siguiente; solo por edad, sin sexo */
export interface AgeBand {
  id: string;
  organization_id: string;
  label_es: string;
  min_age: number;
  sort_order: number;
}

/** Tipo de familia (catálogo de la organización que editan dirección y Trabajo Social; solo informativo) */
export interface FamilyType {
  id: string;
  organization_id: string;
  key: string;
  label_es: string;
  legacy_code?: string | null;
  is_active: boolean;
  sort_order: number;
}

/** Familia del sistema de seguimiento paralelo: su folio se captura (no se genera) */
export interface FamilyUnit {
  id: string;
  organization_id: string;
  family_number: string;
  family_type_id?: string | null;
  created_at: string;
}

export interface FamilyMember {
  id: string;
  organization_id: string;
  family_unit_id: string;
  case_id: string;
  member_order?: number | null;
  /** Papel de la persona en la familia (diccionario `family_role`, E15 fase 4); vacío = «No registrado» */
  family_role_item_id?: string | null;
  created_at: string;
  valid_to?: string | null;
  change_reason?: string | null;
}

/** La familia vigente de una persona, con quienes la integran (resuelto al cargar) */
export interface CaseFamilyView {
  unit: FamilyUnit;
  typeLabel: string | null;
  order: number | null;
  /** Papel de esta persona en la familia (valor del diccionario `family_role`) */
  roleItemId: string | null;
  members: { caseId: string; caseNumber: string; personName: string; order: number | null; roleItemId: string | null; birthDate: string | null }[];
}

export type CaseDateKind = 'nation_entry' | 'nation_exit' | 'shelter_entry' | 'shelter_exit';

/** Fecha del caso con la precisión que se conoce; `valid_to` lleno = cerrada (corregida o quitada, con su motivo) */
export interface CaseDate {
  id: string;
  organization_id: string;
  case_id: string;
  kind: CaseDateKind;
  /** Inicio del periodo: con precisión de mes el día 1, con precisión de año el 1 de enero */
  value: string;
  precision: 'day' | 'month' | 'year';
  created_at: string;
  valid_to?: string | null;
  change_reason?: string | null;
}

/** Estado oficial (INEGI): clave de 2 dígitos */
export interface GeoState {
  cve_ent: string;
  name: string;
  abbreviation?: string | null;
}

/** Municipio oficial (INEGI): clave de 5 dígitos (estado + municipio) */
export interface GeoMunicipality {
  cvegeo: string;
  cve_ent: string;
  cve_mun: string;
  name: string;
}

/** Opción de un catálogo de ingreso de la organización (canal de procedencia, vía de ingreso) */
export interface IntakeOption {
  id: string;
  organization_id: string;
  code: number;
  label_es: string;
  is_active: boolean;
  sort_order: number;
}

/** Tipo de documento de la persona (catálogo de la organización, lo administra dirección) */
export interface DocumentType {
  id: string;
  organization_id: string;
  key: string;
  label_es: string;
  is_active: boolean;
  sort_order: number;
}

/** Documento de la persona; `valid_to` lleno = cerrado (cambiado o quitado, con su motivo) */
export interface PersonDocument {
  id: string;
  organization_id: string;
  person_id: string;
  document_type_id: string;
  /** Etiqueta del tipo, resuelta al cargar (nunca se muestra el identificador) */
  type_label?: string;
  document_number: string;
  created_at: string;
  valid_to?: string | null;
  change_reason?: string | null;
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
  organization_id: string;
  case_id: string;
  marker_code: VulnerabilityMarkerCode;
  notes?: string | null;
  affirmed_by: string;
  /** Nombre de quien afirmó el marcador (se resuelve al cargar; nunca se muestra el identificador) */
  affirmed_by_name?: string;
  affirmed_at: string;
  removed_by?: string | null;
  removed_at?: string | null;
  created_at: string;
}

// ------------------------------------------------------------------------------
// Tipos de Estatus Multidimensional (Épica E2: 5 Ejes)
// ------------------------------------------------------------------------------

export type StatusAxisCode = 
  | 'legal_status' 
  | 'engagement_status' 
  | 'shelter_status' 
  | 'record_status' 
  | 'case_stage';

export interface StatusAxis {
  id: string;
  organization_id: string;
  code: StatusAxisCode;
  label_es: string;
  is_primary: boolean;
  is_system: boolean;
  sort_order: number;
  created_at: string;
}

export interface StatusValue {
  id: string;
  organization_id: string;
  axis_id: string;
  code: string;
  label_es: string;
  sort_order: number;
  is_active_care: boolean;
  is_system: boolean;
  is_terminal: boolean;
  created_at: string;
}

export interface CaseStatus {
  id: string;
  organization_id: string;
  case_id: string;
  axis_id: string;
  value_id: string;
  valid_from: string;
  valid_to: string | null;
  reason: string;
  created_by: string | null;
  created_at: string;
}

export interface CaseCurrentStatusDetail {
  valueCode: string;
  label: string;
  valid_from: string;
  reason: string;
  isActiveCare?: boolean;
}

export interface CaseWithDetails extends Case {
  person: Person;
  parentCaseNumber?: string | null;
  subfolios?: CaseWithDetails[];
  vulnerabilities: CaseVulnerabilityMarker[];
  statuses: {
    legal_status: CaseCurrentStatusDetail;
    engagement_status: CaseCurrentStatusDetail;
    shelter_status: CaseCurrentStatusDetail;
    record_status: CaseCurrentStatusDetail;
    case_stage: CaseCurrentStatusDetail;
  };
  journal_entries?: JournalEntry[];
  consents?: Consent[];
  arco_requests?: ArcoRequest[];
  documents?: PersonDocument[];
  dates?: CaseDate[];
  /** Familia del sistema paralelo (E14 fase 3); vacío = «No registrado» */
  family?: CaseFamilyView | null;
  /** Necesidades específicas marcadas (valores vigentes del diccionario, E14 fase 4b) */
  needs?: string[];
  /** Ocupaciones en su lugar de origen (valores vigentes del diccionario, E15 fase 1) */
  occupations?: string[];
  /** Respuestas vigentes de la ficha social (E15 fase 2) */
  social_answers?: SocialAnswer[];
}

// ------------------------------------------------------------------------------
// Tipos de Bitácora de Área, Compartición y Adjuntos (Épica E4)
// ------------------------------------------------------------------------------

export type JournalEntryType = 
  | 'intake_interview' 
  | 'follow_up' 
  | 'referral' 
  | 'home_visit' 
  | 'incident' 
  | 'note'
  // E14 fase 4: bitácora por área
  | 'diagnosis'
  | 'integral_route'
  | 'case_meeting'
  | 'warning';

export type JournalVisibility = 'area_private' | 'shared';

export interface JournalEntry {
  id: string;
  organization_id: string;
  case_id: string;
  case_number?: string;
  area_id: string;
  area_code?: string;
  area_name?: string;
  author_user_id: string;
  author_name?: string;
  entry_type_key: JournalEntryType;
  body: string;
  is_work_note: boolean;
  occurred_at: string;
  created_at: string;
  visibility: JournalVisibility;
  superseded_by_id?: string | null;
  /** Línea de servicio (la «columna» de la hoja de casos); opcional (E14 fase 4) */
  service_line_item_id?: string | null;
  /** Procedencia: 'app' escrita aquí, 'import' traída de la hoja de casos con su autoría original */
  source?: 'app' | 'import';
  source_author_label?: string | null;
  sharing_event?: SharingEvent | null;
}

export interface SharingEvent {
  id: string;
  organization_id: string;
  journal_entry_id: string;
  case_id: string;
  case_number?: string;
  from_area_id: string;
  from_area_name?: string;
  to_area_id: string;
  to_area_name?: string;
  from_visibility: JournalVisibility;
  to_visibility: JournalVisibility;
  reason: string;
  shared_by_user_id: string;
  shared_by_name?: string;
  shared_at: string;
  acknowledged_by_user_id?: string | null;
  acknowledged_by_name?: string | null;
  acknowledged_at?: string | null;
}

export interface Attachment {
  id: string;
  organization_id: string;
  case_id: string;
  journal_entry_id?: string | null;
  storage_path: string;
  file_name: string;
  mime_type: string;
  size_bytes: number;
  uploaded_by: string;
  uploaded_at: string;
  visibility: JournalVisibility;
}

// ------------------------------------------------------------------------------
// Tipos de Consentimiento y Derechos ARCO (Épica E5)
// ------------------------------------------------------------------------------

export interface PrivacyNotice {
  id: string;
  organization_id: string;
  version: string;
  title: string;
  summary: string;
  full_text: string;
  effective_date: string;
  active: boolean;
  created_at: string;
}

export type ConsentType = 
  | 'general_care' 
  | 'sensitive_data' 
  | 'internal_sharing' 
  | 'secondary_use_research';

export interface ConsentText {
  id: string;
  organization_id: string;
  consent_type: ConsentType;
  version: number;
  title: string;
  description: string;
  required: boolean;
  active: boolean;
  created_at: string;
}

export type ConsentStatus = 'granted' | 'revoked' | 'opposed';

export interface Consent {
  id: string;
  organization_id: string;
  person_id: string;
  case_id?: string | null;
  privacy_notice_id?: string | null;
  consent_text_id?: string | null;
  consent_type: ConsentType;
  status: ConsentStatus;
  is_minor_assent: boolean;
  legal_guardian_name?: string | null;
  legal_guardian_role?: string | null;
  authority_letter_ref?: string | null;
  granted_at: string;
  granted_by_user_id: string;
  granted_by_name?: string;
  revoked_at?: string | null;
  revoked_by_user_id?: string | null;
  revocation_reason?: string | null;
  notes?: string | null;
  created_at: string;
}

export type ArcoRequestType = 'access' | 'rectification' | 'cancellation' | 'opposition';

export type ArcoRequestStatus = 'pending' | 'approved_executed' | 'rejected';

export interface ArcoRequest {
  id: string;
  organization_id: string;
  person_id: string;
  person_name?: string;
  case_id?: string | null;
  case_number?: string | null;
  request_type: ArcoRequestType;
  status: ArcoRequestStatus;
  details: string;
  reason: string;
  requested_by_name: string;
  is_legal_representative: boolean;
  representative_relationship?: string | null;
  received_at: string;
  handled_by_user_id?: string | null;
  handled_by_name?: string | null;
  resolved_at?: string | null;
  resolution_notes?: string | null;
  created_at: string;
}


