import { useMemo, useSyncExternalStore } from 'react';

// Enrutamiento mínimo por hash (#/expedientes/ASF-2026-0001): sin dependencias, funciona con el
// hospedaje estático, y da lo que importa: recargar conserva el lugar, «atrás» funciona y
// los enlaces se pueden compartir.
export type RouteId = 'operations' | 'cases' | 'indicators' | 'areas' | 'audit' | 'authority' | 'about';

export const ROUTE_SLUG: Record<RouteId, string> = {
  operations: 'operacion',
  cases: 'expedientes',
  indicators: 'indicadores',
  areas: 'areas',
  audit: 'auditoria',
  authority: 'autoridad',
  about: 'acerca',
};

export interface Route {
  id: RouteId | null;
  param: string | null;
}

export function parseHash(hash: string): Route {
  const parts = hash
    .replace(/^#\/?/, '')
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
  return { id, param: id && parts[1] ? parts[1] : null };
}

export function hrefFor(id: RouteId, param?: string | null): string {
  return `#/${ROUTE_SLUG[id]}${param ? `/${encodeURIComponent(param)}` : ''}`;
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
