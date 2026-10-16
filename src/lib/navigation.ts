import { RoleName } from '../types/database';
import { RouteId } from './router';

// Qué pantallas ve cada rol. Es la ÚNICA fuente: la barra de navegación, la protección de rutas
// y la sección «Qué ve cada rol» de «Acerca de» salen de aquí. Ocultar una pantalla no es
// seguridad (la regla de acceso vive en la base de datos, RLS); esto sólo evita mostrar
// destinos que la persona no puede usar.
//
// Los roles se ACUMULAN (ADR-0007): una persona con varios roles ve la unión de sus pantallas.
const ROLE_ROUTES: Record<RoleName, RouteId[]> = {
  director: ['operations', 'cases', 'tasks', 'indicators', 'areas', 'audit', 'authority', 'configuration', 'dictionaries', 'team'],
  intake_officer: ['cases', 'tasks', 'indicators'],
  caseworker: ['cases', 'tasks', 'indicators'],
  viewer: ['indicators'],
  task_manager: ['tasks'],
  volunteer: ['tasks'],
};

// Orden canónico: define el orden de la barra y cuál es la pantalla de inicio
const ROUTE_ORDER: RouteId[] = ['operations', 'cases', 'tasks', 'indicators', 'areas', 'audit', 'authority', 'configuration', 'dictionaries', 'team', 'about'];

export const PRIMARY_ROUTES: RouteId[] = ['operations', 'cases', 'tasks', 'indicators'];
export const ADMIN_ROUTES: RouteId[] = ['areas', 'audit', 'authority', 'configuration', 'dictionaries', 'team'];

/** Roles con acceso al expediente (o a sus indicadores). Los de tareas no cuentan. */
const CASE_ROLES: RoleName[] = ['director', 'intake_officer', 'caseworker', 'viewer'];

export const hasCaseAccess = (roles: RoleName[]): boolean => roles.some((r) => CASE_ROLES.includes(r));

/** Gestión de tareas: crear, editar, reabrir, cerrar sin foto y archivar. */
export const canManageTasks = (roles: RoleName[]): boolean => roles.includes('director') || roles.includes('task_manager');

/**
 * Pantallas de administración: ya no las da el rol sino una CAPACIDAD (E16 fase B), que la dirección concede a un rol o a
 * un área. Por omisión la dirección tiene todas (y Trabajo Social la de diccionarios). La base vuelve a exigirlas.
 */
export const ROUTE_CAPABILITY: Partial<Record<RouteId, string>> = {
  areas: 'manage_areas',
  dictionaries: 'manage_catalogs',
  team: 'manage_team',
  audit: 'view_audit',
  authority: 'manage_authority_requests',
  configuration: 'manage_org_settings',
};

/**
 * Pantallas permitidas: las básicas salen de la unión de los roles; las de administración, de las capacidades de la cuenta
 * (`fn_my_capabilities`). «Acerca de» sólo existe en entorno demo.
 */
export function allowedRoutes(roles: RoleName[], isDemo: boolean, capabilities: string[]): RouteId[] {
  const union = new Set<RouteId>(roles.flatMap((r) => ROLE_ROUTES[r] ?? []).filter((id) => !ROUTE_CAPABILITY[id]));
  for (const [id, cap] of Object.entries(ROUTE_CAPABILITY) as [RouteId, string][]) if (capabilities.includes(cap)) union.add(id);
  if (isDemo) union.add('about');
  return ROUTE_ORDER.filter((r) => union.has(r));
}

export function defaultRoute(roles: RoleName[], capabilities: string[]): RouteId {
  return allowedRoutes(roles, false, capabilities)[0] ?? 'indicators';
}

export const ROLE_NAMES: RoleName[] = ['director', 'intake_officer', 'caseworker', 'viewer', 'task_manager', 'volunteer'];

export function routesOfRole(role: RoleName): RouteId[] {
  return ROLE_ROUTES[role] ?? [];
}

/** Clave de traducción de la etiqueta de cada pantalla */
export const ROUTE_LABEL_KEY: Record<RouteId, string> = {
  operations: 'navigation.operations',
  cases: 'navigation.cases',
  tasks: 'navigation.tasks',
  indicators: 'navigation.indicators',
  areas: 'navigation.areas',
  audit: 'navigation.audit_trail',
  authority: 'navigation.authority_requests',
  configuration: 'navigation.configuration',
  dictionaries: 'navigation.dictionaries',
  team: 'navigation.team',
  about: 'navigation.about',
};
