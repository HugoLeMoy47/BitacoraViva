import { useMemo, useSyncExternalStore } from 'react';

// Enrutamiento mínimo por hash (#/expedientes/ASF-2026-0001): sin dependencias, funciona con el
// hospedaje estático, y da lo que importa: recargar conserva el lugar, «atrás» funciona y
// los enlaces se pueden compartir.
export type RouteId = 'operations' | 'cases' | 'tasks' | 'indicators' | 'areas' | 'audit' | 'authority' | 'configuration' | 'about';

export const ROUTE_SLUG: Record<RouteId, string> = {
  operations: 'operacion',
  cases: 'expedientes',
  tasks: 'tareas',
  indicators: 'indicadores',
  areas: 'areas',
  audit: 'auditoria',
  authority: 'autoridad',
  configuration: 'configuracion',
  about: 'acerca',
};

export interface Route {
  id: RouteId | null;
  param: string | null;
  /** Cadena de consulta tras «?» (sin el signo), p. ej. los filtros de un reporte */
  query: string;
}

export function parseHash(hash: string): Route {
  const raw = hash.replace(/^#\/?/, '');
  const queryAt = raw.indexOf('?');
  const path = queryAt === -1 ? raw : raw.slice(0, queryAt);
  const query = queryAt === -1 ? '' : raw.slice(queryAt + 1);
  const parts = path
    .split('/')
    .filter(Boolean)
    .map((p) => {
      try {
        return decodeURIComponent(p);
      } catch {
        return p;
      }
    });
  const id = (Object.keys(ROUTE_SLUG) as RouteId[]).find((k) => ROUTE_SLUG[k] === parts[0]) ?? null;
  return { id, param: id && parts[1] ? parts[1] : null, query: id ? query : '' };
}

export function hrefFor(id: RouteId, param?: string | null, query?: string): string {
  return `#/${ROUTE_SLUG[id]}${param ? `/${encodeURIComponent(param)}` : ''}${query ? `?${query}` : ''}`;
}

/**
 * Cambia sólo la consulta de la ruta actual SIN agregar una entrada al historial y sin disparar
 * `hashchange`: el buscador de un reporte cambia el estado por tecla, y con historial «atrás» exigiría
 * una pulsación por letra tecleada.
 */
export function replaceQuery(id: RouteId, param: string | null, query: string): void {
  window.history.replaceState(null, '', hrefFor(id, param, query));
}

export function navigate(id: RouteId, param?: string | null, opts?: { replace?: boolean }): void {
  const href = hrefFor(id, param);
  if (opts?.replace) {
    window.location.replace(href);
  } else if (window.location.hash !== href) {
    window.location.hash = href;
  }
}

function subscribe(callback: () => void): () => void {
  window.addEventListener('hashchange', callback);
  return () => window.removeEventListener('hashchange', callback);
}

export function useRoute(): Route {
  const hash = useSyncExternalStore(subscribe, () => window.location.hash, () => '');
  return useMemo(() => parseHash(hash), [hash]);
}
