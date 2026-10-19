// E16 fase A · Equipo: lógica pura de la pantalla «Equipo y permisos».
// La regla de quién gestiona el equipo vive en la base (`can_manage_team()`, hoy la dirección); aquí solo se decide qué
// mostrar. Rol y área son independientes: una persona puede tener varios roles, cada uno con su área o sin ella.

export interface TeamProfile {
  id: string;
  full_name: string;
  email: string;
  active: boolean;
}

export interface TeamRole {
  id: string;
  user_id: string;
  role_name: string;
  area_id: string | null;
  granted_by: string | null;
  granted_at: string;
  revoked_by: string | null;
  revoked_at: string | null;
  grant_reason: string | null;
  revoke_reason: string | null;
}

export interface TeamMember {
  profile: TeamProfile;
  /** Roles vigentes, el más reciente primero */
  active: TeamRole[];
  /** Roles revocados (historial), el más reciente primero */
  history: TeamRole[];
}

export function groupTeam(profiles: TeamProfile[], roles: TeamRole[]): TeamMember[] {
  const byRecent = (a: TeamRole, b: TeamRole) => b.granted_at.localeCompare(a.granted_at);
  return [...profiles]
    .sort((a, b) => a.full_name.localeCompare(b.full_name, 'es'))
    .map((profile) => {
      const mine = roles.filter((x) => x.user_id === profile.id);
      return {
        profile,
        active: mine.filter((x) => !x.revoked_at).sort(byRecent),
        history: mine.filter((x) => x.revoked_at).sort(byRecent),
      };
    });
}

// ---------------------------------------------------------------- E17 fase 1 · tabla de «Equipo»

/** Lo que dice `fn_team_access()`: si la persona ya aceptó su invitación (Auth no se lee desde la interfaz). */
export interface TeamAccess {
  user_id: string;
  accepted: boolean;
  last_sign_in_at: string | null;
}

export type MemberStatus = 'inactive' | 'pending' | 'no_role' | 'active';

/** Una sola columna de estado: desactivada, invitación pendiente, sin rol o activa. */
export function memberStatus(member: TeamMember, access: TeamAccess | undefined): MemberStatus {
  if (!member.profile.active) return 'inactive';
  if (access && !access.accepted) return 'pending';
  if (member.active.length === 0) return 'no_role';
  return 'active';
}

export interface TeamFilter {
  text: string;
  role: string;
  /** id de área */
  area: string;
  status: '' | MemberStatus;
}

const plain = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

export function filterTeam(members: TeamMember[], access: Map<string, TeamAccess>, f: TeamFilter): TeamMember[] {
  const term = plain(f.text.trim());
  return members.filter((m) => {
    if (term && !plain(m.profile.full_name).includes(term) && !plain(m.profile.email).includes(term)) return false;
    // Rol y área se comparan sobre el MISMO rol vigente: «Atención en Jurídico» no es «Atención» más «Ingreso en Jurídico»
    if (f.role || f.area) {
      const ok = m.active.some((r) => (!f.role || r.role_name === f.role) && (!f.area || r.area_id === f.area));
      if (!ok) return false;
    }
    if (f.status && memberStatus(m, access.get(m.profile.id)) !== f.status) return false;
    return true;
  });
}

/** Roles que trabajan con expedientes y por eso se pregunta su área (compartimenta la bitácora, Ethos C2). */
const AREA_ROLES = ['intake_officer', 'caseworker'];
export const roleUsesArea = (role: string): boolean => AREA_ROLES.includes(role);

export interface TeamCapability {
  code: string;
  description_es: string;
  sort_order: number;
}
export interface TeamGrantLite {
  capability_code: string;
  role_name: string | null;
  area_id: string | null;
  revoked_at: string | null;
}

/** Lo que podrá hacer quien reciba este rol (y, si el rol trabaja con área, lo que llega por esa área). */
export function grantPreview(role: string, areaId: string | null, grants: TeamGrantLite[], caps: TeamCapability[]): string[] {
  const live = grants.filter((g) => !g.revoked_at);
  const codes = new Set<string>();
  for (const g of live) {
    if (g.role_name === role) codes.add(g.capability_code);
    if (areaId && roleUsesArea(role) && g.area_id === areaId) codes.add(g.capability_code);
  }
  return caps.filter((c) => codes.has(c.code)).sort((a, b) => a.sort_order - b.sort_order).map((c) => c.description_es);
}
