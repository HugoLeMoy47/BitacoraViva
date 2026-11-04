import { useSyncExternalStore } from 'react';
import esTranslations from '../locales/es.json';
import enTranslations from '../locales/en.json';

export type Locale = 'es' | 'en';
export const LOCALES: readonly Locale[] = ['es', 'en'];
export const DEFAULT_LOCALE: Locale = 'es';

/** Etiqueta BCP 47 que usan las fechas, los números y el orden alfabético de cada idioma. */
export const INTL_TAG: Record<Locale, string> = { es: 'es-MX', en: 'en-US' };

// El inglés se ofrece en el selector solo cuando la traducción está completa y revisada por el Product Owner.
// Mientras tanto se enciende en un entorno de prueba con VITE_ENABLE_ENGLISH=1; la base ya acepta ambos valores.
export const ENGLISH_ENABLED = import.meta.env?.VITE_ENABLE_ENGLISH === '1';
export const availableLocales = (): Locale[] => (ENGLISH_ENABLED ? ['es', 'en'] : ['es']);

type Tree = { [key: string]: string | Tree };
const dictionaries: Record<Locale, Tree> = { es: esTranslations as Tree, en: enTranslations as Tree };

// La preferencia vive en el perfil de la persona (user_profile.ui_locale). El navegador solo la recuerda para
// la pantalla de entrada, antes de que haya sesión.
const STORAGE_KEY = 'bv_locale';
const isLocale = (v: unknown): v is Locale => v === 'es' || v === 'en';

function readStored(): Locale {
  try {
    const v = localStorage.getItem(STORAGE_KEY);
    return isLocale(v) && availableLocales().includes(v) ? v : DEFAULT_LOCALE;
  } catch {
    return DEFAULT_LOCALE;
  }
}

let current: Locale = readStored();
const listeners = new Set<() => void>();

export const getLocale = (): Locale => current;

/** Cambia el idioma activo; la interfaz se vuelve a pintar (useLocale). No toca la base: eso lo hace quien la llama. */
export function setLocale(next: Locale): void {
  const value: Locale = isLocale(next) && availableLocales().includes(next) ? next : DEFAULT_LOCALE;
  if (value === current) return;
  current = value;
  try {
    localStorage.setItem(STORAGE_KEY, value);
  } catch {
    /* sin almacenamiento: la preferencia sigue en la sesión */
  }
  if (typeof document !== 'undefined') document.documentElement.lang = value;
  listeners.forEach((l) => l());
}

export function useLocale(): Locale {
  return useSyncExternalStore(
    (cb) => {
      listeners.add(cb);
      return () => listeners.delete(cb);
    },
    getLocale,
    () => DEFAULT_LOCALE,
  );
}

function lookup(tree: Tree, keys: string[]): string | undefined {
  let node: string | Tree | undefined = tree;
  for (const key of keys) {
    if (node && typeof node === 'object' && key in node) node = node[key];
    else return undefined;
  }
  return typeof node === 'string' ? node : undefined;
}

export function t(path: string): string {
  const keys = path.split('.');
  // Si una clave aún no está traducida se muestra en español: nunca una clave cruda ni un hueco.
  return lookup(dictionaries[current], keys) ?? lookup(dictionaries.es, keys) ?? path;
}

// Algunos textos los escribe el sistema en la base (p. ej. el motivo del estatus inicial). Para que sirvan en
// cualquier idioma se guardan como clave, «i18n:status.reason_initial», y se traducen al mostrarlos.
// Un texto escrito por una persona (sin el prefijo) se muestra tal cual.
export function tStored(stored: string): string {
  return stored.startsWith('i18n:') ? t(stored.slice('i18n:'.length)) : stored;
}

/** Etiqueta BCP 47 del idioma activo, para `Intl`, `localeCompare` y `toLocale…String`. */
export const intlTag = (): string => INTL_TAG[current];
