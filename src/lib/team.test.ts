import { describe, expect, it } from 'vitest';
import { groupTeam, TeamProfile, TeamRole } from './team';

const p = (id: string, full_name: string, active = true): TeamProfile => ({ id, full_name, email: `${id}@x.org`, active });
const r = (id: string, user_id: string, role_name: string, area_id: string | null, granted_at: string, revoked_at: string | null = null): TeamRole => ({
  id, user_id, role_name, area_id, granted_at, revoked_at, grant_reason: null, revoke_reason: null, granted_by: null, revoked_by: null,
});

describe('equipo: personas con sus roles', () => {
  const profiles = [p('u2', 'Zoe Zapata'), p('u1', 'Ana Aguirre'), p('u3', 'Beto Baeza', false)];
  const roles = [
    r('r1', 'u1', 'director', null, '2026-01-01T00:00:00Z'),
    r('r2', 'u2', 'caseworker', 'ts', '2026-02-01T00:00:00Z'),
    r('r3', 'u2', 'caseworker', 'legal', '2026-03-01T00:00:00Z'),
    r('r4', 'u2', 'viewer', null, '2026-01-15T00:00:00Z', '2026-02-15T00:00:00Z'),
  ];
  const team = groupTeam(profiles, roles);

  it('ordena a las personas por nombre', () => {
    expect(team.map((t) => t.profile.id)).toEqual(['u1', 'u3', 'u2']); // Ana, Beto, Zoe
  });

  it('separa los roles vigentes de los revocados (historial)', () => {
    const zoe = team.find((t) => t.profile.id === 'u2')!;
    expect(zoe.active.map((x) => x.id)).toEqual(['r3', 'r2']); // más reciente primero
    expect(zoe.history.map((x) => x.id)).toEqual(['r4']);
  });

  it('una persona puede tener varios roles y áreas a la vez (muchas gorras)', () => {
    expect(team.find((t) => t.profile.id === 'u2')!.active).toHaveLength(2);
  });

  it('una persona sin roles aparece, con la lista vacía', () => {
    const beto = team.find((t) => t.profile.id === 'u3')!;
    expect(beto.active).toEqual([]);
    expect(beto.history).toEqual([]);
  });
});
