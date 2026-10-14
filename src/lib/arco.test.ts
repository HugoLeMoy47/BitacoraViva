import { describe, expect, it } from 'vitest';
import { computeBusinessDaysDeadline, computeArcoDocket } from './arco';

describe('computeBusinessDaysDeadline', () => {
  it('suma 20 días hábiles omitiendo sábados y domingos', () => {
    // Lunes 5 de octubre de 2026 a las 10:00 UTC
    const monday = '2026-10-05T10:00:00.000Z';
    const deadlineIso = computeBusinessDaysDeadline(monday, 20);
    const deadline = new Date(deadlineIso);

    // 20 días hábiles a partir de un lunes son exactamente 4 semanas completas:
    // Semana 1: 5 días (6, 7, 8, 9, 12)
    // Semana 2: 5 días (13, 14, 15, 16, 19)
    // Semana 3: 5 días (20, 21, 22, 23, 26)
    // Semana 4: 5 días (27, 28, 29, 30, 2 de nov)
    // El día 20 hábil es el 2 de noviembre de 2026
    expect(deadline.getUTCFullYear()).toBe(2026);
    expect(deadline.getUTCMonth()).toBe(10); // Noviembre (0-indexed: 10)
    expect(deadline.getUTCDate()).toBe(2);
    // Verificar que nunca caiga en fin de semana
    expect(deadline.getUTCDay()).not.toBe(0); // Domingo
    expect(deadline.getUTCDay()).not.toBe(6); // Sábado
  });

  it('omite el fin de semana inmediato si la fecha base es viernes', () => {
    // Viernes 9 de octubre de 2026
    const friday = '2026-10-09T12:00:00.000Z';
    // 1 día hábil -> Lunes 12 de octubre de 2026
    const deadlineIso = computeBusinessDaysDeadline(friday, 1);
    const deadline = new Date(deadlineIso);
    expect(deadline.getUTCDate()).toBe(12);
    expect(deadline.getUTCDay()).toBe(1); // Lunes
  });

  it('calcula plazos arbitrarios correctamente (ej. 5 días hábiles)', () => {
    // Lunes 5 de octubre de 2026 -> 5 días hábiles es el siguiente Lunes 12
    const monday = '2026-10-05T10:00:00.000Z';
    const deadlineIso = computeBusinessDaysDeadline(monday, 5);
    const deadline = new Date(deadlineIso);
    expect(deadline.getUTCDate()).toBe(12);
  });
});

describe('computeArcoDocket', () => {
  it('genera un folio con prefijo por defecto BV y año correspondiente', () => {
    const docket = computeArcoDocket({
      id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
      received_at: '2026-05-15T14:30:00.000Z',
    });
    expect(docket).toBe('ARCO-BV-2026-A1B2');
  });

  it('respeta el prefijo institucional de la organización', () => {
    const docket = computeArcoDocket(
      {
        id: 'f9e8d7c6-b5a4-3210-fedc-ba0987654321',
        received_at: '2026-10-14T08:00:00.000Z',
      },
      'cjm'
    );
    expect(docket).toBe('ARCO-CJM-2026-F9E8');
  });

  it('maneja id vacío usando fallback 0001', () => {
    const docket = computeArcoDocket({
      id: '',
      received_at: '2026-01-01T00:00:00.000Z',
    });
    expect(docket).toBe('ARCO-BV-2026-0001');
  });
});
