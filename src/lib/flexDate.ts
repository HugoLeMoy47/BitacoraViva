// Fechas con precisión flexible (E14 fase 2): la hoja de casos trae fechas completas, solo con mes o solo con año.
// En la base se guarda el INICIO del periodo y la precisión dice cuánto se sabe: nunca se inventa un día.

export type DatePrecision = 'day' | 'month' | 'year';

const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

// «YYYY-MM-DD» como fecha UTC: sin desplazamientos por zona horaria
function parts(value: string): { y: number; m: number; d: number } | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  return m ? { y: Number(m[1]), m: Number(m[2]), d: Number(m[3]) } : null;
}

/** Cómo se lee una fecha según su precisión: «15 de marzo de 2026», «septiembre de 2026» o «2024». */
export function formatFlexDate(value: string, precision: DatePrecision): string {
  const p = parts(value);
  if (!p) return value;
  if (precision === 'year') return String(p.y);
  if (precision === 'month') return `${MESES[p.m - 1]} de ${p.y}`;
  return `${p.d} de ${MESES[p.m - 1]} de ${p.y}`;
}

/** Lo escrito en el campo (día «2026-03-15», mes «2026-09», año «2024») como fecha guardable; null si no sirve. */
export function toStoredDate(precision: DatePrecision, raw: string): string | null {
  const v = raw.trim();
  if (precision === 'day') {
    const p = parts(v);
    return p && p.m >= 1 && p.m <= 12 && p.d >= 1 && p.d <= 31 ? v : null;
  }
  if (precision === 'month') {
    const m = /^(\d{4})-(\d{2})$/.exec(v);
    return m && Number(m[2]) >= 1 && Number(m[2]) <= 12 ? `${v}-01` : null;
  }
  return /^\d{4}$/.test(v) && Number(v) >= 1900 ? `${v}-01-01` : null;
}

/** ¿El periodo empieza después de hoy? Lo futuro no se registra (el mes en curso sí cabe). */
export function startsInFuture(storedValue: string, today: Date = new Date()): boolean {
  const p = parts(storedValue);
  if (!p) return false;
  const t = `${today.getUTCFullYear()}-${String(today.getUTCMonth() + 1).padStart(2, '0')}-${String(today.getUTCDate()).padStart(2, '0')}`;
  return storedValue > t;
}
