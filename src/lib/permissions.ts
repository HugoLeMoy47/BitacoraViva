// E17 fase 2 · Permisos: lógica pura de la cuadrícula «permisos × roles».
// La regla vive en la base (`has_capability`, `fn_grant_capability`, `fn_revoke_capability`, solo la dirección cambia permisos);
// aquí solo se decide cómo agrupar y qué concesiones están vigentes.

export interface PermissionCapability {
  code: string;
  description_es: string;
  sort_order: number;
}

export interface PermissionGrant {
  id: string;
  capability_code: string;
  role_name: string | null;
  area_id: string | null;
  granted_at: string;
  grant_reason: string | null;
  revoked_at: string | null;
  revoke_reason: string | null;
}

// Temas de la cuadrícula. Una capacidad que no esté aquí va a «Otros»: nunca desaparece de la pantalla.
const GROUPS: { id: string; codes: string[] }[] = [
  { id: 'cases', codes: ['open_cases', 'rectify_person_data', 'change_legal_status'] },
  { id: 'structure', codes: ['manage_catalogs', 'manage_areas', 'manage_status_catalog', 'manage_task_catalogs', 'manage_task_settings'] },
  { id: 'team', codes: ['manage_team', 'view_audit', 'manage_authority_requests', 'manage_org_settings'] },
];

export interface CapabilityGroup {
  id: string;
  caps: PermissionCapability[];
}

export function groupCapabilities(caps: PermissionCapability[]): CapabilityGroup[] {
  const byOrder = (a: PermissionCapability, b: PermissionCapability) => a.sort_order - b.sort_order;
  const known = new Set(GROUPS.flatMap((g) => g.codes));
  const out: CapabilityGroup[] = GROUPS.map((g) => ({ id: g.id, caps: caps.filter((c) => g.codes.includes(c.code)).sort(byOrder) }));
  out.push({ id: 'other', caps: caps.filter((c) => !known.has(c.code)).sort(byOrder) });
  return out.filter((g) => g.caps.length > 0);
}

/** La concesión vigente de una capacidad a un rol, si la hay. */
export const roleGrant = (grants: PermissionGrant[], code: string, role: string): PermissionGrant | undefined =>
  grants.find((g) => !g.revoked_at && g.capability_code === code && g.role_name === role);

/** Las excepciones por área vigentes de una capacidad. */
export const areaGrants = (grants: PermissionGrant[], code: string): PermissionGrant[] =>
  grants.filter((g) => !g.revoked_at && g.capability_code === code && g.area_id !== null);

/** Lo revocado, lo más reciente primero. */
export function historyEntries(grants: PermissionGrant[], limit?: number): PermissionGrant[] {
  const list = grants.filter((g) => g.revoked_at).sort((a, b) => (b.revoked_at as string).localeCompare(a.revoked_at as string));
  return limit ? list.slice(0, limit) : list;
}
