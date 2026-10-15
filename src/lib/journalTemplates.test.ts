import { describe, expect, it } from 'vitest';
import { TEMPLATES, composeBody, hasTemplate, warningOrdinals, ordinalLabelKey } from './journalTemplates';

describe('plantillas de bitácora', () => {
  it('solo el diagnóstico y la reunión de casos tienen plantilla', () => {
    expect(hasTemplate('diagnosis')).toBe(true);
    expect(hasTemplate('case_meeting')).toBe(true);
    expect(hasTemplate('follow_up')).toBe(false);
    expect(hasTemplate('warning')).toBe(false);
  });

  it('el diagnóstico tiene las seis secciones de la hoja y la reunión de casos tres pasos', () => {
    expect(TEMPLATES.diagnosis).toEqual(['family', 'intake', 'exit_reason', 'in_mexico', 'plan', 'health']);
    expect(TEMPLATES.case_meeting).toEqual(['detected', 'done', 'referred']);
  });

  it('compone el texto con título por sección y deja fuera las secciones vacías (no se inventa nada)', () => {
    const body = composeBody([
      { title: 'Familia', text: '  Viaja con su hija  ' },
      { title: 'Ingreso', text: '' },
      { title: 'Salud', text: 'Control de diabetes' },
    ]);
    expect(body).toBe('Familia\nViaja con su hija\n\nSalud\nControl de diabetes');
  });

  it('sin ninguna sección escrita no hay texto', () => {
    expect(composeBody([{ title: 'Familia', text: '   ' }])).toBe('');
  });
});

describe('llamadas de atención', () => {
  const e = (id: string, type: string, at: string) => ({ id, entry_type_key: type, occurred_at: at, created_at: at });

  it('el ordinal se deriva del orden de ocurrencia, no se captura', () => {
    const m = warningOrdinals([
      e('b', 'warning', '2026-03-02T10:00:00Z'),
      e('x', 'note', '2026-03-03T10:00:00Z'),
      e('a', 'warning', '2026-02-01T10:00:00Z'),
      e('c', 'warning', '2026-04-01T10:00:00Z'),
    ]);
    expect(m.get('a')).toBe(1);
    expect(m.get('b')).toBe(2);
    expect(m.get('c')).toBe(3);
    expect(m.has('x')).toBe(false);
  });

  it('la clave de texto del ordinal llega hasta 3 y de ahí en adelante es «n.ª»', () => {
    expect(ordinalLabelKey(1)).toBe('journal.warning_ordinal_1');
    expect(ordinalLabelKey(3)).toBe('journal.warning_ordinal_3');
    expect(ordinalLabelKey(4)).toBe('journal.warning_ordinal_n');
  });
});
