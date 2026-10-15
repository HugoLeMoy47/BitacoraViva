import { describe, expect, it } from 'vitest';
import { ageYears, bandFor, birthdayMonth, stayDays } from './derived';

const bands = [
  { id: '1', label_es: 'NNA 0-3', min_age: 0, sort_order: 1 },
  { id: '2', label_es: 'NNA 4-6', min_age: 4, sort_order: 2 },
  { id: '3', label_es: 'Personas adultas 18-59', min_age: 18, sort_order: 3 },
  { id: '4', label_es: 'Personas adultas mayores 60+', min_age: 60, sort_order: 4 },
];
const today = new Date(2026, 9, 15); // 15 oct 2026

describe('edad', () => {
  it('cuenta los años cumplidos', () => {
    expect(ageYears('2000-10-15', today)).toBe(26);
    expect(ageYears('2000-10-16', today)).toBe(25);
    expect(ageYears('2026-01-01', today)).toBe(0);
  });
  it('sin fecha de nacimiento o con una fecha inválida o futura no hay edad', () => {
    expect(ageYears(null, today)).toBeNull();
    expect(ageYears('', today)).toBeNull();
    expect(ageYears('no-es-fecha', today)).toBeNull();
    expect(ageYears('2027-01-01', today)).toBeNull();
  });
});

describe('grupo por edad (solo por edad, sin sexo)', () => {
  it('cae en el grupo cuyo inicio es el mayor que no pasa de la edad', () => {
    expect(bandFor(bands, 0)?.label_es).toBe('NNA 0-3');
    expect(bandFor(bands, 3)?.label_es).toBe('NNA 0-3');
    expect(bandFor(bands, 4)?.label_es).toBe('NNA 4-6');
    expect(bandFor(bands, 17)?.label_es).toBe('NNA 4-6');
    expect(bandFor(bands, 18)?.label_es).toBe('Personas adultas 18-59');
    expect(bandFor(bands, 99)?.label_es).toBe('Personas adultas mayores 60+');
  });
  it('sin edad o sin grupos configurados no se supone ninguno', () => {
    expect(bandFor(bands, null)).toBeNull();
    expect(bandFor([], 30)).toBeNull();
  });
  it('no depende del orden en que lleguen los grupos', () => {
    expect(bandFor([...bands].reverse(), 20)?.label_es).toBe('Personas adultas 18-59');
  });
});

describe('mes de cumpleaños', () => {
  it('sale de la fecha de nacimiento', () => {
    expect(birthdayMonth('2000-03-09', false)).toBe(3);
  });
  it('si la fecha de nacimiento es estimada no se afirma un mes', () => {
    expect(birthdayMonth('2000-01-01', true)).toBeNull();
  });
  it('sin fecha no hay mes', () => {
    expect(birthdayMonth(null, false)).toBeNull();
  });
});

describe('días de estancia', () => {
  const d = (value: string, precision: 'day' | 'month' | 'year' = 'day') => ({ value, precision });
  it('con ingreso y salida exactos son los días entre ambas', () => {
    expect(stayDays(d('2026-10-01'), d('2026-10-11'), false, today)).toBe(10);
  });
  it('si sigue en el albergue cuenta hasta hoy', () => {
    expect(stayDays(d('2026-10-05'), undefined, true, today)).toBe(10);
  });
  it('si ya no está en el albergue y no hay fecha de salida no se calcula', () => {
    expect(stayDays(d('2026-10-05'), undefined, false, today)).toBeNull();
  });
  it('sin fecha de ingreso, o con fechas sin el día exacto, no se calcula', () => {
    expect(stayDays(undefined, d('2026-10-11'), false, today)).toBeNull();
    expect(stayDays(d('2026-10-01', 'month'), d('2026-10-11'), false, today)).toBeNull();
    expect(stayDays(d('2026-10-01'), d('2026-10-11', 'year'), false, today)).toBeNull();
  });
  it('una salida anterior al ingreso no se calcula', () => {
    expect(stayDays(d('2026-10-11'), d('2026-10-01'), false, today)).toBeNull();
  });
});
