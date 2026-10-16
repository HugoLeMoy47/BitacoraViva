import { describe, expect, it } from 'vitest';
import { allowedRoutes } from './navigation';

const ALL = ['manage_catalogs', 'manage_team', 'view_audit', 'manage_authority_requests', 'manage_org_settings', 'manage_areas'];

describe('pantallas permitidas: los roles dan las básicas y las capacidades dan las de administración', () => {
  it('la dirección, con todas las capacidades, ve todo lo de administración', () => {
    const r = allowedRoutes(['director'], false, ALL);
    for (const id of ['dictionaries', 'team', 'audit', 'authority', 'configuration', 'areas'] as const) expect(r).toContain(id);
  });

  it('las pantallas básicas no dependen de capacidades', () => {
    const r = allowedRoutes(['director'], false, []);
    for (const id of ['operations', 'cases', 'tasks', 'indicators'] as const) expect(r).toContain(id);
  });

  it('sin la capacidad, ni la dirección ve la pantalla de administración correspondiente', () => {
    const r = allowedRoutes(['director'], false, ['manage_catalogs']);
    expect(r).toContain('dictionaries');
    for (const id of ['team', 'audit', 'authority', 'configuration', 'areas'] as const) expect(r).not.toContain(id);
  });

  it('Trabajo Social con la capacidad de diccionarios ve «Diccionarios» y nada más de administración', () => {
    const r = allowedRoutes(['caseworker'], false, ['manage_catalogs']);
    expect(r).toContain('dictionaries');
    for (const id of ['team', 'audit', 'authority', 'configuration'] as const) expect(r).not.toContain(id);
  });

  it('delegar la gestión del equipo muestra «Equipo y permisos» a quien la recibe', () => {
    expect(allowedRoutes(['caseworker'], false, ['manage_team'])).toContain('team');
    expect(allowedRoutes(['caseworker'], false, [])).not.toContain('team');
  });

  it('cada capacidad abre solo su pantalla, a cualquier rol que la tenga', () => {
    expect(allowedRoutes(['viewer'], false, ['view_audit'])).toContain('audit');
    const intake = allowedRoutes(['intake_officer'], false, ['manage_authority_requests', 'manage_org_settings']);
    expect(intake).toContain('authority');
    expect(intake).toContain('configuration');
    expect(intake).not.toContain('audit');
  });

  it('delegar la administración de áreas muestra «Áreas» a quien la recibe, y sin ella ni la dirección la ve', () => {
    expect(allowedRoutes(['intake_officer'], false, ['manage_areas'])).toContain('areas');
    expect(allowedRoutes(['director'], false, [])).not.toContain('areas');
  });

  it('«Acerca de» sigue siendo solo de la demo', () => {
    expect(allowedRoutes(['viewer'], true, [])).toContain('about');
    expect(allowedRoutes(['viewer'], false, [])).not.toContain('about');
  });
});
