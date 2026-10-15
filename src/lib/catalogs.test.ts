import { describe, expect, it } from 'vitest';
import { t } from './i18n';
import { countryLabel, itemLabel, freeTextOrNull } from './catalogs';

// Resumen del expediente: el dato que falta NO se rellena con un valor inventado; devuelve null
// para que la pantalla muestre `cases.not_specified`.

describe('countryLabel', () => {
  it('traduce el identificador del catálogo', () => {
    expect(countryLabel(93, null)).toBe(t('catalogs.country.93'));
    expect(countryLabel(86, 'Guatemala')).toBe(t('catalogs.country.86'));
  });
  it('usa el texto libre cuando el país es «otro» (id 1)', () => {
    expect(countryLabel(1, 'Nicaragua')).toBe('Nicaragua');
  });
  it('devuelve null si no hay dato', () => {
    expect(countryLabel(1, null)).toBeNull();
    expect(countryLabel(1, '  ')).toBeNull();
    expect(countryLabel(undefined, undefined)).toBeNull();
  });
});

describe('itemLabel: un valor del diccionario con su detalle', () => {
  const items = [
    { id: 'a', label_es: 'Lengua indígena' },
    { id: 'b', label_es: 'Español' },
  ];
  it('muestra el valor y, si lo hay, su detalle', () => {
    expect(itemLabel(items, 'a', 'Tzotzil')).toBe('Lengua indígena (Tzotzil)');
    expect(itemLabel(items, 'b', null)).toBe('Español');
  });
  it('sin valor ni detalle es null: la pantalla dice «No registrado» y no inventa un idioma', () => {
    expect(itemLabel(items, null, null)).toBeNull();
    expect(itemLabel(items, undefined, '')).toBeNull();
  });
  it('un valor que ya no está en el diccionario no se inventa; queda solo el detalle si lo hay', () => {
    expect(itemLabel(items, 'zzz', null)).toBeNull();
    expect(itemLabel(items, 'zzz', 'Tzotzil')).toBe('Tzotzil');
  });
});

describe('freeTextOrNull', () => {
  it('recorta y devuelve null si está vacío', () => {
    expect(freeTextOrNull(' Mayo 2026 ')).toBe('Mayo 2026');
    expect(freeTextOrNull(null)).toBeNull();
    expect(freeTextOrNull('   ')).toBeNull();
  });
});
