import { describe, expect, it } from 'vitest';
import { keyFromLabel, validateBands } from './dictionaries';

describe('clave de un valor nuevo', () => {
  it('sale del nombre: sin acentos, en minúsculas y con guiones bajos', () => {
    expect(keyFromLabel('Cuidador de niñas y niños', [])).toBe('cuidador_de_ninas_y_ninos');
    expect(keyFromLabel('  Salud mental (adultos) ', [])).toBe('salud_mental_adultos');
  });
  it('si ya existe agrega un número, sin pisar la clave de otro valor', () => {
    expect(keyFromLabel('Escuela', ['escuela'])).toBe('escuela_2');
    expect(keyFromLabel('Escuela', ['escuela', 'escuela_2'])).toBe('escuela_3');
  });
  it('un nombre sin letras ni números recibe una clave genérica', () => {
    expect(keyFromLabel('???', [])).toBe('valor');
  });
});

describe('grupos por edad: validación previa al envío', () => {
  const ok = [
    { label: 'Niñez', minAge: '0' },
    { label: 'Adultez', minAge: '18' },
  ];
  it('una lista bien formada no tiene error', () => {
    expect(validateBands(ok)).toBeNull();
  });
  it('sin grupos, no', () => {
    expect(validateBands([])).toBe('dictionaries.bands_err_empty');
  });
  it('el primero empieza en 0', () => {
    expect(validateBands([{ label: 'A', minAge: '3' }])).toBe('dictionaries.bands_err_first');
  });
  it('las edades van de menor a mayor y sin repetirse', () => {
    expect(validateBands([...ok, { label: 'C', minAge: '12' }])).toBe('dictionaries.bands_err_order');
    expect(validateBands([ok[0], { label: 'B', minAge: '0' }])).toBe('dictionaries.bands_err_order');
  });
  it('cada grupo lleva nombre y una edad numérica', () => {
    expect(validateBands([{ label: ' ', minAge: '0' }])).toBe('dictionaries.bands_err_name');
    expect(validateBands([ok[0], { label: 'B', minAge: '' }])).toBe('dictionaries.bands_err_age');
    expect(validateBands([ok[0], { label: 'B', minAge: '1.5' }])).toBe('dictionaries.bands_err_age');
  });
  it('los nombres no se repiten (sin distinguir mayúsculas)', () => {
    expect(validateBands([ok[0], { label: 'niñez', minAge: '18' }])).toBe('dictionaries.bands_err_dup');
  });
  it('máximo 12 grupos', () => {
    const many = Array.from({ length: 13 }, (_, i) => ({ label: `G${i}`, minAge: String(i * 5) }));
    expect(validateBands(many)).toBe('dictionaries.bands_err_max');
  });
});
