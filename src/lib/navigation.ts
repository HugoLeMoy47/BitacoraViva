import { RoleName } from '../types/database';
import { RouteId } from './router';

// Qué pantallas ve cada rol. Es la ÚNICA fuente: la barra de navegación, la protección de rutas
// y la sección «Qué ve cada rol» de «Acerca de» salen de aquí. Ocultar una pantalla no es
// seguridad (la regla de acceso vive en la base de datos, RLS); esto sólo evita mostrar
// destinos que la persona no puede usar.
const ROLE_ROUTES: Record<RoleName, RouteId[]> = {
  director: ['operations', 'cases', 'indicators', 'areas', 'audit', 'authority', 'configuration'],
  intake_officer: ['cases', 'indicators'],
  caseworker: ['cases', 'indicators'],
  viewer: ['indicators'],
};

export const PRIMARY_ROUTES: RouteId[] = ['operations', 'cases', 'indicators'];
export const ADMIN_ROUTES: RouteId[] = ['areas', 'audit', 'authority', 'configuration'];

/** Pantallas permitidas. «Acerca de» sólo existe en entorno demo. */
export function allowedRoutes(role: RoleName, isDemo: boolean): RouteId[] {
  const base = ROLE_ROUTES[role] ?? [];
  return isDemo ? [...base, 'about'] : base;
}

export function defaultRoute(role: RoleName): RouteId {
  return ROLE_ROUTES[role]?.[0] ?? 'indicators';
}

export const ROLE_NAMES: RoleName[] = ['director', 'intake_officer', 'caseworker', 'viewer'];

export function routesOfRole(role: RoleName): RouteId[] {
  return ROLE_ROUTES[role] ?? [];
}

/** Clave de traducción de la etiqueta de cada pantalla */
export const ROUTE_LABEL_KEY: Record<RouteId, string> = {
  operations: 'navigation.operations',
  cases: 'navigation.cases',
  indicators: 'navigation.indicators',
  areas: 'navigation.areas',
  audit: 'navigation.audit_trail',
  authority: 'navigation.authority_requests',
  configuration: 'navigation.configuration',
  about: 'navigation.about',
};
