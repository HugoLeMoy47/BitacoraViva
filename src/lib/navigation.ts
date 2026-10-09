import { RoleName } from '../types/database';
import { RouteId } from './router';

// Qué pantallas ve cada rol. Es la ÚNICA fuente: la barra de navegación, la protección de rutas
// y la sección «Qué ve cada rol» de «Acerca de» salen de aquí. Ocultar una pantalla no es
// seguridad (la regla de acceso vive en la base de datos, RLS); esto sólo evita mostrar
// destinos que la persona no puede usar.
//
// Los roles se ACUMULAN (ADR-0007): una persona con varios roles ve la unión de sus pantallas.
const ROLE_ROUTES: Record<RoleName, RouteId[]> = {
  director: ['operations', 'cases', 'tasks', 'indicators', 'areas', 'audit', 'authority', 'configuration'],
  intake_officer: ['cases', 'tasks', 'indicators'],
  caseworker: ['cases', 'tasks', 'indicators'],
  viewer: ['indicators'],
  task_manager: ['tasks'],
  volunteer: ['tasks'],
};

// Orden canónico: define el orden de la barra y cuál es la pantalla de inicio
const ROUTE_ORDER: RouteId[] = ['operations', 'cases', 'tasks', 'indicators', 'areas', 'audit', 'authority', 'configuration', 'about'];

export const PRIMARY_ROUTES: RouteId[] = ['operations', 'cases', 'tasks', 'indicators'];
export const ADMIN_ROUTES: RouteId[] = ['areas', 'audit', 'authority', 'configuration'];

/** Roles con acceso al expediente (o a sus indicadores). Los de tareas no cuentan. */
const CASE_ROLES: RoleName[] = ['director', 'intake_officer', 'caseworker', 'viewer'];

export const hasCaseAccess = (roles: RoleName[]): boolean => roles.some((r) => CASE_ROLES.includes(r));

/** Gestión de tareas: crear, editar, reabrir, cerrar sin foto y archivar. */
export const canManageTasks = (roles: RoleName[]): boolean => roles.includes('director') || roles.includes('task_manager');

/** Pantallas permitidas (unión de las de todos los roles). «Acerca de» sólo existe en entorno demo. */
export function allowedRoutes(roles: RoleName[], isDemo: boolean): RouteId[] {
  const union = new Set<RouteId>(roles.flatMap((r) => ROLE_ROUTES[r] ?? []));
  if (isDemo) union.add('about');
  return ROUTE_ORDER.filter((r) => union.has(r));
}

export function defaultRoute(roles: RoleName[]): RouteId {
  return allowedRoutes(roles, false)[0] ?? 'indicators';
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
  about: 'navigation.about',
};
