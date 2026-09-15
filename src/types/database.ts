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
  assigned_at: string;
}

export interface Area {
  id: string;
  organization_id: string;
  code: AreaCode;
  name: string;
  active: boolean;
  created_at: string;
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
