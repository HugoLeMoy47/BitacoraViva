import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// El motor lee VITE_ENABLE_ENGLISH al cargarse: se enciende antes de importarlo.
async function cargar(inglesActivo: boolean) {
  vi.resetModules();
  vi.stubEnv('VITE_ENABLE_ENGLISH', inglesActivo ? '1' : '0');
  return import('./i18n');
}

describe('idioma de la interfaz', () => {
  beforeEach(() => {
    // Las pruebas corren en Node: un almacenamiento en memoria hace las veces del del navegador
    const datos = new Map<string, string>();
    vi.stubGlobal('localStorage', {
      getItem: (k: string) => datos.get(k) ?? null,
      setItem: (k: string, v: string) => void datos.set(k, v),
      clear: () => datos.clear(),
    });
  });
  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  it('el español es el idioma por defecto', async () => {
    const i = await cargar(true);
    expect(i.getLocale()).toBe('es');
    expect(i.t('session.sign_out')).toBe('Cerrar sesión');
  });

  it('con el inglés apagado el selector solo ofrece español y no deja activarlo', async () => {
    const i = await cargar(false);
    expect(i.availableLocales()).toEqual(['es']);
    i.setLocale('en');
    expect(i.getLocale()).toBe('es');
  });

  it('una clave sin traducir al inglés se muestra en español, nunca como clave cruda', async () => {
    const i = await cargar(true);
    i.setLocale('en');
    expect(i.getLocale()).toBe('en');
    expect(i.t('session.sign_out')).not.toBe('session.sign_out');
    const falsa = ['clave', 'que', 'no', 'existe'].join('.');
    expect(i.t(falsa)).toBe(falsa);
  });

  it('recuerda el idioma en el navegador para la pantalla de entrada', async () => {
    const i = await cargar(true);
    i.setLocale('en');
    expect(localStorage.getItem('bv_locale')).toBe('en');
    const j = await cargar(true);
    expect(j.getLocale()).toBe('en');
  });

  it('el idioma activo gobierna fechas, orden y nombres de países', async () => {
    const i = await cargar(true);
    const f = await import('./format');
    const c = await import('./countries');
    expect(f.formatDate('2026-10-07')).toBe('7 oct 2026');
    expect(c.countryName('DE')).toBe('Alemania');
    i.setLocale('en');
    expect(f.formatDate('2026-10-07')).toBe('Oct 7, 2026');
    expect(c.countryName('DE')).toBe('Germany');
    // Lo que se guarda en la base sigue siendo el nombre en español, sea cual sea el idioma
    expect(c.countryNameEs('DE')).toBe('Alemania');
  });

  it('el nombre de un continente se traduce por clave', async () => {
    const c = await import('./countries');
    expect(c.continentKey('Europa')).toBe('countries.continents.c3');
  });
});
