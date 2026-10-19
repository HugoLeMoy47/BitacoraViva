import { describe, expect, it } from 'vitest';
import { peoplePerArea, sortAreas } from './areas';

describe('áreas: personas por área', () => {
  const roles = [
    { user_id: 'a', area_id: 'ts', revoked_at: null },
    { user_id: 'a', area_id: 'ts', revoked_at: null }, // la misma persona con dos roles en el área cuenta una vez
    { user_id: 'b', area_id: 'ts', revoked_at: null },
    { user_id: 'c', area_id: 'ts', revoked_at: '2026-01-01T00:00:00Z' }, // revocado: no cuenta
    { user_id: 'd', area_id: null, revoked_at: null }, // sin área: no cuenta en ninguna
    { user_id: 'e', area_id: 'legal', revoked_at: null },
  ];
  it('cuenta personas distintas con un rol vigente en cada área', () => {
    const m = peoplePerArea(roles);
    expect(m.get('ts')).toBe(2);
    expect(m.get('legal')).toBe(1);
  });
  it('un área sin personas no aparece (se lee como 0)', () => {
    expect(peoplePerArea(roles).get('medica')).toBeUndefined();
  });
});

describe('áreas: orden de la lista', () => {
  const a = (id: string, name: string, active: boolean) => ({ id, name, active });
  it('primero las activas, luego las desactivadas; cada grupo por nombre sin importar acentos', () => {
    const list = sortAreas([a('1', 'Médica', true), a('2', 'Legal', false), a('3', 'Ámbito social', true), a('4', 'Zeta', false)]);
    expect(list.map((x) => x.id)).toEqual(['3', '1', '2', '4']);
  });
});
