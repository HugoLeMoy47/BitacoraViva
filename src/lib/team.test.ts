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

import { filterTeam, grantPreview, memberStatus, roleUsesArea, TeamAccess, TeamFilter, TeamGrantLite } from './team';

describe('equipo: estado de cada persona', () => {
  const team = groupTeam(
    [p('a', 'Ana Aguirre'), p('b', 'Beto Baeza', false), p('c', 'Carla Cano'), p('d', 'Dani Díaz')],
    [r('r1', 'a', 'director', null, '2026-01-01T00:00:00Z'), r('r2', 'b', 'viewer', null, '2026-01-01T00:00:00Z'), r('r3', 'd', 'caseworker', 'ts', '2026-01-01T00:00:00Z')],
  );
  const access = (id: string, accepted: boolean): TeamAccess => ({ user_id: id, accepted, last_sign_in_at: null });
  const m = (id: string) => team.find((x) => x.profile.id === id)!;

  it('una cuenta desactivada se muestra desactivada, tenga o no roles', () => {
    expect(memberStatus(m('b'), access('b', true))).toBe('inactive');
  });
  it('quien aún no aceptó la invitación está pendiente, aunque no tenga rol', () => {
    expect(memberStatus(m('c'), access('c', false))).toBe('pending');
  });
  it('quien aceptó y no tiene rol aparece «sin rol»', () => {
    expect(memberStatus(m('c'), access('c', true))).toBe('no_role');
  });
  it('quien aceptó y tiene rol está activa', () => {
    expect(memberStatus(m('a'), access('a', true))).toBe('active');
  });
  it('sin dato de acceso (aún cargando) no se inventa «pendiente»', () => {
    expect(memberStatus(m('c'), undefined)).toBe('no_role');
    expect(memberStatus(m('a'), undefined)).toBe('active');
  });
});

describe('equipo: filtros de la tabla', () => {
  const team = groupTeam(
    [p('a', 'Ana Aguirre'), p('b', 'Beto Baeza', false), p('c', 'Carla Cano'), p('d', 'Dani Díaz')],
    [
      r('r1', 'a', 'director', null, '2026-01-01T00:00:00Z'),
      r('r2', 'b', 'viewer', null, '2026-01-01T00:00:00Z'),
      r('r3', 'd', 'caseworker', 'ts', '2026-01-01T00:00:00Z'),
      r('r4', 'd', 'intake_officer', 'legal', '2026-01-02T00:00:00Z'),
    ],
  );
  const access = new Map<string, TeamAccess>([['c', { user_id: 'c', accepted: false, last_sign_in_at: null }]]);
  const none: TeamFilter = { text: '', role: '', area: '', status: '' };
  const ids = (f: Partial<TeamFilter>) => filterTeam(team, access, { ...none, ...f }).map((x) => x.profile.id);

  it('sin filtros devuelve a todas las personas', () => expect(ids({})).toEqual(['a', 'b', 'c', 'd']));
  it('busca por nombre sin importar mayúsculas ni acentos', () => {
    expect(ids({ text: 'dani diaz' })).toEqual(['d']);
    expect(ids({ text: 'AGUIRRE' })).toEqual(['a']);
  });
  it('busca por correo', () => expect(ids({ text: 'c@x.org' })).toEqual(['c']));
  it('filtra por rol vigente', () => {
    expect(ids({ role: 'caseworker' })).toEqual(['d']);
    expect(ids({ role: 'director' })).toEqual(['a']);
  });
  it('filtra por área de un rol vigente', () => {
    expect(ids({ area: 'legal' })).toEqual(['d']);
    expect(ids({ area: 'ts' })).toEqual(['d']);
  });
  it('rol y área se combinan sobre el MISMO rol: Atención en Jurídico no aparece si su Jurídico es de Ingreso', () => {
    expect(ids({ role: 'caseworker', area: 'legal' })).toEqual([]);
    expect(ids({ role: 'intake_officer', area: 'legal' })).toEqual(['d']);
  });
  it('filtra por estado', () => {
    expect(ids({ status: 'inactive' })).toEqual(['b']);
    expect(ids({ status: 'pending' })).toEqual(['c']);
    expect(ids({ status: 'active' })).toEqual(['a', 'd']);
  });
  it('los filtros se combinan', () => expect(ids({ text: 'c', status: 'pending' })).toEqual(['c']));
});

describe('dar un rol: qué pregunta y qué podrá hacer', () => {
  it('el área solo se pregunta a ingreso y atención', () => {
    expect(roleUsesArea('intake_officer')).toBe(true);
    expect(roleUsesArea('caseworker')).toBe(true);
    for (const rn of ['director', 'viewer', 'task_manager', 'volunteer']) expect(roleUsesArea(rn)).toBe(false);
  });

  const caps = [
    { code: 'open_cases', description_es: 'Abrir expedientes', sort_order: 1 },
    { code: 'manage_catalogs', description_es: 'Administrar diccionarios', sort_order: 2 },
    { code: 'view_audit', description_es: 'Ver la auditoría', sort_order: 3 },
  ];
  const grants: TeamGrantLite[] = [
    { capability_code: 'open_cases', role_name: 'intake_officer', area_id: null, revoked_at: null },
    { capability_code: 'manage_catalogs', role_name: null, area_id: 'ts', revoked_at: null },
    { capability_code: 'view_audit', role_name: 'intake_officer', area_id: null, revoked_at: '2026-01-01T00:00:00Z' },
  ];

  it('lista lo que el rol permite, por las concesiones vigentes', () => {
    expect(grantPreview('intake_officer', null, grants, caps)).toEqual(['Abrir expedientes']);
  });
  it('no cuenta concesiones revocadas', () => {
    expect(grantPreview('intake_officer', null, grants, caps)).not.toContain('Ver la auditoría');
  });
  it('suma lo que llega por el área elegida', () => {
    expect(grantPreview('intake_officer', 'ts', grants, caps)).toEqual(['Abrir expedientes', 'Administrar diccionarios']);
  });
  it('el área solo suma si el rol trabaja con área', () => {
    expect(grantPreview('viewer', 'ts', grants, caps)).toEqual([]);
  });
  it('un rol sin concesiones no promete nada', () => {
    expect(grantPreview('volunteer', null, grants, caps)).toEqual([]);
  });
});
