import { Organization, Area, Role, UserProfile, AuditEvent, RoleName } from '../types/database';

export const DEMO_ORGANIZATION: Organization = {
  id: '00000000-0000-0000-0000-000000000001',
  slug: 'albergue-santa-fe',
  legal_name: 'Albergue Santa Fe A.C.',
  display_name: 'Albergue Santa Fe',
  active: true,
  created_at: '2026-09-14T08:00:00Z',
  updated_at: '2026-09-14T08:00:00Z',
};

export const DEMO_ROLES: Role[] = [
  {
    name: 'director',
    description: 'Supervisión global del albergue, gobernanza de roles, digest de alertas y auditoría',
    created_at: '2026-09-14T08:00:00Z',
  },
  {
    name: 'caseworker',
    description: 'Gestión integral del caso, notas de evolución y bitácora en áreas asignadas',
    created_at: '2026-09-14T08:00:00Z',
  },
  {
    name: 'intake_officer',
    description: 'Recepción inicial, levantamiento de ficha básica y apertura de folios',
    created_at: '2026-09-14T08:00:00Z',
  },
  {
    name: 'viewer',
    description: 'Lectura de métricas agregadas y anonimizadas; sin acceso a datos identificables',
    created_at: '2026-09-14T08:00:00Z',
  },
];

export const DEMO_AREAS: Area[] = [
  { id: '10000000-0000-0000-0000-000000000001', organization_id: DEMO_ORGANIZATION.id, code: 'trabajo_social', name: 'Trabajo Social', active: true, created_at: '2026-09-14T08:00:00Z' },
  { id: '10000000-0000-0000-0000-000000000002', organization_id: DEMO_ORGANIZATION.id, code: 'legal', name: 'Atención Jurídica', active: true, created_at: '2026-09-14T08:00:00Z' },
  { id: '10000000-0000-0000-0000-000000000003', organization_id: DEMO_ORGANIZATION.id, code: 'psicologia', name: 'Atención Psicosocial', active: true, created_at: '2026-09-14T08:00:00Z' },
  { id: '10000000-0000-0000-0000-000000000004', organization_id: DEMO_ORGANIZATION.id, code: 'medica', name: 'Salud y Primeros Auxilios', active: true, created_at: '2026-09-14T08:00:00Z' },
  { id: '10000000-0000-0000-0000-000000000005', organization_id: DEMO_ORGANIZATION.id, code: 'coordinacion', name: 'Coordinación General', active: true, created_at: '2026-09-14T08:00:00Z' },
];

export interface DemoUser {
  profile: UserProfile;
  role: RoleName;
}

export const DEMO_USERS: Record<RoleName, DemoUser> = {
  director: {
    profile: {
      id: 'a0000000-0000-0000-0000-000000000001',
      organization_id: DEMO_ORGANIZATION.id,
      email: 'director@alberguesantafe.org',
      full_name: 'Elena Morales',
      active: true,
      created_at: '2026-09-14T08:00:00Z',
      updated_at: '2026-09-14T08:00:00Z',
    },
    role: 'director',
  },
  caseworker: {
    profile: {
      id: 'a0000000-0000-0000-0000-000000000002',
      organization_id: DEMO_ORGANIZATION.id,
      email: 'caseworker@alberguesantafe.org',
      full_name: 'Carlos Méndez',
      active: true,
      created_at: '2026-09-14T08:00:00Z',
      updated_at: '2026-09-14T08:00:00Z',
    },
    role: 'caseworker',
  },
  intake_officer: {
    profile: {
      id: 'a0000000-0000-0000-0000-000000000003',
      organization_id: DEMO_ORGANIZATION.id,
      email: 'intake@alberguesantafe.org',
      full_name: 'Mariana Ríos',
      active: true,
      created_at: '2026-09-14T08:00:00Z',
      updated_at: '2026-09-14T08:00:00Z',
    },
    role: 'intake_officer',
  },
  viewer: {
    profile: {
      id: 'a0000000-0000-0000-0000-000000000004',
      organization_id: DEMO_ORGANIZATION.id,
      email: 'viewer@alberguesantafe.org',
      full_name: 'Dr. Roberto Soto',
      active: true,
      created_at: '2026-09-14T08:00:00Z',
      updated_at: '2026-09-14T08:00:00Z',
    },
    role: 'viewer',
  },
};

export const DEMO_AUDIT_EVENTS: AuditEvent[] = [
  {
    id: 'e0000000-0000-0000-0000-000000000001',
    organization_id: DEMO_ORGANIZATION.id,
    user_id: null,
    action: 'INSERT',
    table_name: 'organization',
    record_id: DEMO_ORGANIZATION.id,
    old_values: null,
    new_values: { slug: 'albergue-santa-fe', display_name: 'Albergue Santa Fe', commitments: 'Ethos C1-C8 activados' },
    created_at: '2026-09-14T08:00:00Z',
  },
  {
    id: 'e0000000-0000-0000-0000-000000000002',
    organization_id: DEMO_ORGANIZATION.id,
    user_id: 'a0000000-0000-0000-0000-000000000001',
    action: 'INSERT',
    table_name: 'user_role',
    record_id: '11111111-0000-0000-0000-000000000001',
    old_values: null,
    new_values: { user_id: 'a0000000-0000-0000-0000-000000000002', role_name: 'caseworker' },
    created_at: '2026-09-14T08:05:00Z',
  },
  {
    id: 'e0000000-0000-0000-0000-000000000003',
    organization_id: DEMO_ORGANIZATION.id,
    user_id: 'a0000000-0000-0000-0000-000000000001',
    action: 'INSERT',
    table_name: 'user_role',
    record_id: '11111111-0000-0000-0000-000000000002',
    old_values: null,
    new_values: { user_id: 'a0000000-0000-0000-0000-000000000003', role_name: 'intake_officer' },
    created_at: '2026-09-14T08:06:00Z',
  },
];
