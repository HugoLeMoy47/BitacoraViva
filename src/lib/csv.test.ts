import { describe, expect, it } from 'vitest';
import { buildCsv, csvFileName, escapeField, neutralizeFormula } from './csv';

describe('neutralizeFormula', () => {
  it('antepone un apóstrofo a lo que una hoja de cálculo leería como fórmula', () => {
    for (const evil of ['=1+1', '+SUMA(A1)', '-2+3', '@SUMA(1)', '\tcmd', '\rcmd']) {
      expect(neutralizeFormula(evil)).toBe(`'${evil}`);
    }
  });
  it('no toca el texto normal', () => {
    expect(neutralizeFormula('Limpiar baños')).toBe('Limpiar baños');
  });
});

describe('escapeField', () => {
  it('neutraliza la fórmula ANTES de entrecomillar', () => {
    expect(escapeField('=HYPERLINK("http://x";"y")')).toBe('"\'=HYPERLINK(""http://x"";""y"")"');
  });
  it('entrecomilla si hay separador, comillas o saltos de línea, y duplica las comillas', () => {
    expect(escapeField('a;b')).toBe('"a;b"');
    expect(escapeField('dijo "hola"')).toBe('"dijo ""hola"""');
    expect(escapeField('l1\nl2')).toBe('"l1\nl2"');
  });
  it('nulo e indefinido son celdas vacías', () => {
    expect(escapeField(null)).toBe('');
    expect(escapeField(undefined)).toBe('');
  });
});

describe('buildCsv', () => {
  it('usa punto y coma y CRLF (lo que espera Excel en español)', () => {
    const csv = buildCsv(
      [{ key: 'a', title: 'Tarea' }, { key: 'b', title: 'Estado' }],
      [{ a: 'Barrer', b: 'Hecha' }, { a: '=1+1', b: 'Pendiente' }]
    );
    expect(csv).toBe("Tarea;Estado\r\nBarrer;Hecha\r\n'=1+1;Pendiente");
  });
});

describe('csvFileName', () => {
  it('es legible, sin acentos y con marca de tiempo local', () => {
    expect(csvFileName('tareas', 'Por estado', new Date(2026, 8, 5, 9, 7))).toBe('tareas_por-estado_20260905_0907.csv');
  });
});
