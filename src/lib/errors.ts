import { t } from './i18n';

// Traduce el mensaje técnico de la base o de la red a un texto con el siguiente paso.
// Los mensajes de dominio de la base ya vienen en español y se conservan como detalle.
export function friendlyError(raw: string): string {
  const m = raw.toLowerCase();
  if (m.includes('failed to fetch') || m.includes('networkerror') || m.includes('load failed')) return t('errors.network');
  if (m.includes('jwt') || m.includes('not authenticated')) return t('errors.session');
  if (m.includes('duplicate key')) return t('errors.duplicate');
  if (
    m.includes('acceso denegado') ||
    m.includes('permiso denegado') ||
    m.includes('permission denied') ||
    m.includes('row-level security')
  ) {
    return t('errors.permission').replace('{detail}', raw);
  }
  if (m.includes('no encontrado') || m.includes('not found')) return t('errors.not_found');
  return t('errors.generic').replace('{detail}', raw);
}
