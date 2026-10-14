import { describe, expect, it } from 'vitest';
import { t } from './i18n';
import { countryLabel, languageLabel, freeTextOrNull } from './catalogs';

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

describe('languageLabel', () => {
  it('muestra el texto escrito', () => {
    expect(languageLabel(1, 'Criollo')).toBe('Criollo');
  });
  it('no inventa «Español» cuando falta', () => {
    expect(languageLabel(1, null)).toBeNull();
    expect(languageLabel(1, '')).toBeNull();
  });
});

describe('freeTextOrNull', () => {
  it('recorta y devuelve null si está vacío', () => {
    expect(freeTextOrNull(' Mayo 2026 ')).toBe('Mayo 2026');
    expect(freeTextOrNull(null)).toBeNull();
    expect(freeTextOrNull('   ')).toBeNull();
  });
});
