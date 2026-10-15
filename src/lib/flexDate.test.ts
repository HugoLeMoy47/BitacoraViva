import { describe, expect, it } from 'vitest';
import { formatFlexDate, startsInFuture, toStoredDate, todayLocalIso } from './flexDate';

// E14 fase 2: fechas que pueden venir completas, solo con mes o solo con año.

describe('formatFlexDate: se muestra solo lo que se sabe', () => {
  it('con día exacto muestra día, mes y año', () => {
    const s = formatFlexDate('2026-03-15', 'day');
    expect(s).toContain('15');
    expect(s).toContain('2026');
  });

  it('con mes no inventa un día', () => {
    const s = formatFlexDate('2026-09-01', 'month');
    expect(s.toLowerCase()).toContain('septiembre');
    expect(s).toContain('2026');
    expect(s).not.toMatch(/\b1\b/);
  });

  it('con solo el año muestra únicamente el año', () => {
    expect(formatFlexDate('2024-01-01', 'year')).toBe('2024');
  });

  it('no se desplaza un día por la zona horaria', () => {
    expect(formatFlexDate('2026-03-01', 'day')).toContain('1');
    expect(formatFlexDate('2026-12-31', 'day')).toContain('31');
  });
});

describe('toStoredDate: lo escrito se guarda como inicio del periodo', () => {
  it('día: queda igual', () => {
    expect(toStoredDate('day', '2026-03-15')).toBe('2026-03-15');
  });
  it('mes: del campo de mes al primer día', () => {
    expect(toStoredDate('month', '2026-09')).toBe('2026-09-01');
  });
  it('año: al primero de enero', () => {
    expect(toStoredDate('year', '2024')).toBe('2024-01-01');
  });
  it('lo vacío o inválido no se guarda', () => {
    expect(toStoredDate('day', '')).toBeNull();
    expect(toStoredDate('month', '2026-13')).toBeNull();
    expect(toStoredDate('year', 'abcd')).toBeNull();
    expect(toStoredDate('year', '99')).toBeNull();
  });
});

describe('startsInFuture: lo futuro no se registra', () => {
  const hoy = new Date('2026-10-15T12:00:00Z');
  it('el mes en curso no es futuro', () => {
    expect(startsInFuture('2026-10-01', hoy)).toBe(false);
  });
  it('el mes siguiente sí', () => {
    expect(startsInFuture('2026-11-01', hoy)).toBe(true);
  });
  it('hoy mismo no es futuro; mañana sí', () => {
    expect(startsInFuture('2026-10-15', hoy)).toBe(false);
    expect(startsInFuture('2026-10-16', hoy)).toBe(true);
  });
});

describe('todayLocalIso: el día del movimiento es el de quien captura, no el de UTC', () => {
  it('usa los componentes locales de la fecha', () => {
    expect(todayLocalIso(new Date(2026, 9, 15, 23, 30))).toBe('2026-10-15');
    expect(todayLocalIso(new Date(2026, 0, 2, 0, 5))).toBe('2026-01-02');
  });
  it('tiene el formato de un campo de fecha', () => {
    expect(todayLocalIso()).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });
});
