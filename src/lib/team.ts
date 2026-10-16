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
