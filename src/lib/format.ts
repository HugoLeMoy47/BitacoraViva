// Formato de fechas y horas con Intl (nada de cortes de cadena ni marcas ISO a la vista).
// Fechas «de calendario» (YYYY-MM-DD, p. ej. nacimiento) se interpretan en hora local
// para que no se corran un día por la zona horaria.

import { getLocale, INTL_TAG } from './i18n';

// Los formateadores se arman una vez por idioma y se reutilizan.
const cache = new Map<string, Intl.DateTimeFormat>();
function fmt(kind: string, opts: Intl.DateTimeFormatOptions): Intl.DateTimeFormat {
  const tag = INTL_TAG[getLocale()];
  const key = `${tag}|${kind}`;
  let f = cache.get(key);
  if (!f) {
    f = new Intl.DateTimeFormat(tag, opts);
    cache.set(key, f);
  }
  return f;
}
const dateFmt = () => fmt('date', { day: 'numeric', month: 'short', year: 'numeric' });
const dateTimeFmt = () =>
  fmt('datetime', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
const timeFmt = () => fmt('time', { hour: '2-digit', minute: '2-digit' });

function toDate(value: string): Date | null {
  if (!value) return null;
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  const d = m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

const clean = (s: string) => s.replace(/\./g, '').replace(/\s+/g, ' ');

/** «7 oct 2026» */
export function formatDate(value?: string | null): string {
  const d = value ? toDate(value) : null;
  return d ? clean(dateFmt().format(d)) : '—';
}

/** «7 oct 2026, 04:33» */
export function formatDateTime(value?: string | null): string {
  const d = value ? toDate(value) : null;
  return d ? clean(dateTimeFmt().format(d)) : '—';
}

/** «04:33» */
export function formatTime(value?: string | null): string {
  const d = value ? toDate(value) : null;
  return d ? timeFmt().format(d) : '—';
}

/** «oct 2026» a partir de «YYYY-MM» */
export function formatMonth(yearMonth: string): string {
  const [y, m] = yearMonth.split('-').map(Number);
  return clean(fmt('month-year', { month: 'short', year: 'numeric' }).format(new Date(y, m - 1, 1)));
}

/** «may» (o «may 26» si se pide el año de dos dígitos) a partir de «YYYY-MM» */
export function formatMonthShort(yearMonth: string, withYear = false): string {
  const [y, m] = yearMonth.split('-').map(Number);
  const mon = clean(fmt('month', { month: 'short' }).format(new Date(y, m - 1, 1)));
  return withYear ? `${mon} ${String(y).slice(2)}` : mon;
}
