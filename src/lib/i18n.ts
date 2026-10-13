import esTranslations from '../locales/es.json';

export function t(path: string): string {
  const keys = path.split('.');
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let current: any = esTranslations;
  for (const key of keys) {
    if (current && typeof current === 'object' && key in current) {
      current = current[key];
    } else {
      return path;
    }
  }
  return typeof current === 'string' ? current : path;
}

// Algunos textos los escribe el sistema en la base (p. ej. el motivo del estatus inicial). Para que sirvan en
// cualquier idioma se guardan como clave, «i18n:status.reason_initial», y se traducen al mostrarlos.
// Un texto escrito por una persona (sin el prefijo) se muestra tal cual.
export function tStored(stored: string): string {
  return stored.startsWith('i18n:') ? t(stored.slice('i18n:'.length)) : stored;
}
