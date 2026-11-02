import { describe, expect, it } from 'vitest';
import { CONTINENTS, COUNTRIES, countryName, groupByContinent, legacyCountryId, searchCountries } from './countries';

describe('países ISO 3166-1', () => {
  it('trae los 249 códigos asignados, sin repetidos y con forma alfa-2', () => {
    expect(COUNTRIES).toHaveLength(249);
    const isos = COUNTRIES.map((c) => c.iso);
    expect(new Set(isos).size).toBe(249);
    for (const iso of isos) expect(iso).toMatch(/^[A-Z]{2}$/);
  });

  it('cada país tiene nombre en español y un continente conocido', () => {
    for (const c of COUNTRIES) {
      expect(c.name_es.length).toBeGreaterThan(1);
      expect(CONTINENTS).toContain(c.continent);
    }
  });

  it('los países de la operación aparecen con su nombre', () => {
    expect(countryName('HN')).toBe('Honduras');
    expect(countryName('GT')).toBe('Guatemala');
    expect(countryName('SV')).toBe('El Salvador');
    expect(countryName('VE')).toBe('Venezuela');
    expect(countryName('MX')).toBe('México');
  });

  it('los países de otros continentes están, sin texto libre', () => {
    expect(COUNTRIES.find((c) => c.iso === 'CN')?.continent).toBe('Asia');
    expect(COUNTRIES.find((c) => c.iso === 'NG')?.continent).toBe('África');
    expect(COUNTRIES.find((c) => c.iso === 'UA')?.continent).toBe('Europa');
    expect(COUNTRIES.find((c) => c.iso === 'AU')?.continent).toBe('Oceanía');
    expect(COUNTRIES.find((c) => c.iso === 'BR')?.continent).toBe('América del Sur');
  });

  it('un código desconocido no inventa un nombre', () => {
    expect(countryName('ZZ')).toBeNull();
    expect(countryName(null)).toBeNull();
    expect(countryName('')).toBeNull();
  });
});

describe('búsqueda predictiva', () => {
  it('encuentra sin importar mayúsculas ni acentos', () => {
    expect(searchCountries('mexico').map((c) => c.iso)).toContain('MX');
    expect(searchCountries('MÉXICO').map((c) => c.iso)).toContain('MX');
    expect(searchCountries('hondu').map((c) => c.iso)).toEqual(['HN']);
  });
  it('también por código ISO', () => {
    expect(searchCountries('gt').map((c) => c.iso)).toContain('GT');
  });
  it('sin texto devuelve todos, ordenados por nombre', () => {
    const all = searchCountries('');
    expect(all).toHaveLength(249);
    const names = all.map((c) => c.name_es);
    expect(names).toEqual([...names].sort((a, b) => a.localeCompare(b, 'es')));
  });
  it('sin coincidencias devuelve vacío', () => {
    expect(searchCountries('xyzxyz')).toEqual([]);
  });
});

describe('agrupar por continente', () => {
  it('respeta el orden de los continentes y omite los vacíos', () => {
    const groups = groupByContinent(searchCountries('hondu'));
    expect(groups.map((g) => g.continent)).toEqual(['América del Norte y Central']);
  });
  it('con todos, los continentes salen en el orden definido', () => {
    expect(groupByContinent(COUNTRIES).map((g) => g.continent)).toEqual([...CONTINENTS]);
  });
});

describe('compatibilidad con el identificador del estándar', () => {
  it('Honduras y Guatemala conservan su id; cualquier otro país es «otro» (1)', () => {
    expect(legacyCountryId('HN')).toBe(93);
    expect(legacyCountryId('GT')).toBe(86);
    expect(legacyCountryId('SV')).toBe(1);
    expect(legacyCountryId('CN')).toBe(1);
  });
  it('sin país no hay id (no se supone «otro»)', () => {
    expect(legacyCountryId('')).toBeNull();
    expect(legacyCountryId(null)).toBeNull();
  });
});
