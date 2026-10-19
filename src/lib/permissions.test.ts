import { describe, expect, it } from 'vitest';
import { areaGrants, groupCapabilities, historyEntries, roleGrant, PermissionCapability, PermissionGrant } from './permissions';

const cap = (code: string, sort_order: number): PermissionCapability => ({ code, description_es: `desc ${code}`, sort_order });
const grant = (id: string, capability_code: string, role_name: string | null, area_id: string | null, revoked_at: string | null = null, granted_at = '2026-01-01T00:00:00Z'): PermissionGrant => ({
  id, capability_code, role_name, area_id, granted_at, grant_reason: null, revoked_at, revoke_reason: revoked_at ? 'motivo' : null,
});

describe('permisos: agrupar las capacidades por tema', () => {
  const caps = [
    cap('manage_team', 2), cap('open_cases', 10), cap('manage_areas', 6), cap('view_audit', 3), cap('rectify_person_data', 11),
    cap('manage_catalogs', 1), cap('change_legal_status', 12),
  ];
  const groups = groupCapabilities(caps);

  it('separa Expedientes, Estructura y Equipo y seguridad, en ese orden', () => {
    expect(groups.map((g) => g.id)).toEqual(['cases', 'structure', 'team']);
  });
  it('dentro de cada tema respeta el orden del catálogo', () => {
    expect(groups.find((g) => g.id === 'cases')!.caps.map((c) => c.code)).toEqual(['open_cases', 'rectify_person_data', 'change_legal_status']);
    expect(groups.find((g) => g.id === 'structure')!.caps.map((c) => c.code)).toEqual(['manage_catalogs', 'manage_areas']);
  });
  it('un tema sin capacidades no aparece', () => {
    expect(groupCapabilities([cap('open_cases', 1)]).map((g) => g.id)).toEqual(['cases']);
  });
  it('una capacidad nueva que no está en ningún tema no desaparece: va a «Otros»', () => {
    const g = groupCapabilities([cap('open_cases', 1), cap('algo_nuevo', 99)]);
    expect(g.map((x) => x.id)).toEqual(['cases', 'other']);
    expect(g[1].caps.map((c) => c.code)).toEqual(['algo_nuevo']);
  });
});

describe('permisos: concesiones vigentes', () => {
  const grants = [
    grant('g1', 'open_cases', 'director', null),
    grant('g2', 'open_cases', 'intake_officer', null),
    grant('g3', 'open_cases', 'caseworker', null, '2026-02-01T00:00:00Z'),
    grant('g4', 'open_cases', null, 'legal'),
    grant('g5', 'open_cases', null, 'ts', '2026-02-01T00:00:00Z'),
    grant('g6', 'view_audit', 'viewer', null),
  ];
  it('encuentra la concesión vigente de un rol', () => {
    expect(roleGrant(grants, 'open_cases', 'intake_officer')?.id).toBe('g2');
  });
  it('una concesión revocada ya no cuenta como concedida', () => {
    expect(roleGrant(grants, 'open_cases', 'caseworker')).toBeUndefined();
  });
  it('no mezcla capacidades', () => {
    expect(roleGrant(grants, 'view_audit', 'intake_officer')).toBeUndefined();
    expect(roleGrant(grants, 'view_audit', 'viewer')?.id).toBe('g6');
  });
  it('lista las excepciones por área vigentes de una capacidad', () => {
    expect(areaGrants(grants, 'open_cases').map((g) => g.id)).toEqual(['g4']);
    expect(areaGrants(grants, 'view_audit')).toEqual([]);
  });
});

describe('permisos: historial de cambios', () => {
  it('solo lo revocado, lo más reciente primero', () => {
    const grants = [
      grant('a', 'open_cases', 'director', null),
      grant('b', 'open_cases', 'viewer', null, '2026-03-01T00:00:00Z'),
      grant('c', 'view_audit', 'viewer', null, '2026-04-01T00:00:00Z'),
    ];
    expect(historyEntries(grants).map((g) => g.id)).toEqual(['c', 'b']);
  });
  it('se puede acotar a las últimas N', () => {
    const grants = ['a', 'b', 'c'].map((id, i) => grant(id, 'open_cases', 'viewer', null, `2026-0${i + 1}-01T00:00:00Z`));
    expect(historyEntries(grants, 2).map((g) => g.id)).toEqual(['c', 'b']);
  });
});
