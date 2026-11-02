import { describe, expect, it } from 'vitest';
import { defaultJournalAreaId, writableAreas } from './journalAreas';

const a = (id: string, o: Partial<{ is_general: boolean; is_default_intake: boolean }> = {}) => ({ id, name: id, is_general: false, is_default_intake: false, ...o });
const areas = [a('ts', { is_default_intake: true }), a('legal'), a('coord', { is_general: true })];

describe('bitácora: en qué áreas se puede escribir', () => {
  it('la dirección escribe a nombre de cualquier área', () => {
    expect(writableAreas(areas, true, []).map((x) => x.id)).toEqual(['ts', 'legal', 'coord']);
  });
  it('quien tiene área escribe solo en la suya', () => {
    expect(writableAreas(areas, false, ['legal']).map((x) => x.id)).toEqual(['legal']);
    expect(writableAreas(areas, false, ['ts', 'legal']).map((x) => x.id)).toEqual(['ts', 'legal']);
  });
  it('quien no tiene área escribe solo en el área general', () => {
    expect(writableAreas(areas, false, []).map((x) => x.id)).toEqual(['coord']);
  });
  it('si no hay área general, quien no tiene área no puede escribir en ninguna', () => {
    expect(writableAreas([a('ts'), a('legal')], false, [])).toEqual([]);
  });
});

describe('bitácora: el área que se propone', () => {
  it('primero el área asignada al caso si se puede escribir en ella', () => {
    expect(defaultJournalAreaId(areas, 'legal')).toBe('legal');
  });
  it('si no, el área por omisión al abrir un expediente, si se puede', () => {
    expect(defaultJournalAreaId(areas, 'otra')).toBe('ts');
    expect(defaultJournalAreaId(areas, undefined)).toBe('ts');
  });
  it('si no, la primera disponible', () => {
    expect(defaultJournalAreaId([a('legal'), a('coord', { is_general: true })], undefined)).toBe('legal');
  });
  it('sin áreas, vacío (no se inventa una)', () => {
    expect(defaultJournalAreaId([], 'ts')).toBe('');
  });
});
