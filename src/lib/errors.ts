import { t } from './i18n';

// Error de la base con su código (SQLSTATE): BVnnn de la plataforma, TKnnn de tareas, o los estándar de Postgres.
// La interfaz traduce por CÓDIGO (errors.db.bvnnn en es.json), no buscando palabras en el mensaje: el mensaje de la
// base queda como respaldo y para el registro técnico, y así el mismo error servirá en cualquier idioma (E13).
export class DbError extends Error {
  constructor(message: string, readonly code?: string) {
    super(message);
    this.name = 'DbError';
  }
}

// Traduce un error (de la base, de la red o un texto suelto) a un mensaje con el siguiente paso.
export function friendlyError(input: unknown): string {
  const code = input instanceof DbError ? input.code : undefined;
  if (code && /^BV\d{3}$/.test(code)) {
    const key = `errors.db.${code.toLowerCase()}`;
    const text = t(key);
    if (text !== key) return text;
  }
  // Códigos propios de la función de invitaciones (INVITE_*, ORIGIN_NOT_ALLOWED, NO_SESSION): errors.invite.<código>
  if (code && /^[A-Z_]+$/.test(code)) {
    const key = `errors.invite.${code.toLowerCase()}`;
    const text = t(key);
    if (text !== key) return text;
  }
  const raw = input instanceof Error ? input.message : String(input);
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
