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
