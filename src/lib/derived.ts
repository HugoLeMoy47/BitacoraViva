// E14 fase 5 · Datos derivados: se calculan al mostrarlos y no se guardan.
// Regla «cero valores supuestos»: si falta un dato o no es exacto, el resultado es null («No registrado» / «No calculable»).

export interface AgeBandLike {
  id: string;
  label_es: string;
  min_age: number;
  sort_order: number;
}

const toUtcDay = (iso: string): number | null => {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
  if (!m) return null;
  const t = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return Number.isNaN(t) ? null : t;
};

/** Años cumplidos a `today`; null si no hay fecha de nacimiento válida o es futura */
export function ageYears(birthDate: string | null | undefined, today: Date): number | null {
  if (!birthDate) return null;
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(birthDate);
  if (!m || toUtcDay(birthDate) === null) return null;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  let age = today.getFullYear() - y;
  if (today.getMonth() + 1 < mo || (today.getMonth() + 1 === mo && today.getDate() < d)) age -= 1;
  return age < 0 ? null : age;
}

/** Grupo por edad: SOLO por edad (el sexo es un dato sensible y no condiciona este cálculo) */
export function bandFor<T extends AgeBandLike>(bands: T[], age: number | null): T | null {
  if (age === null) return null;
  let best: T | null = null;
  for (const b of bands) if (b.min_age <= age && (best === null || b.min_age > best.min_age)) best = b;
  return best;
}

/** Mes (1-12) del cumpleaños; si la fecha de nacimiento es estimada no se afirma ninguno */
export function birthdayMonth(birthDate: string | null | undefined, isEstimated: boolean): number | null {
  if (!birthDate || isEstimated || toUtcDay(birthDate) === null) return null;
  return Number(birthDate.slice(5, 7));
}

interface FlexDateLike {
  value: string;
  precision: 'day' | 'month' | 'year';
}

/** Días transcurridos entre el ingreso al albergue y la salida (o hoy si sigue ahí); solo con fechas de día exacto */
export function stayDays(
  entry: FlexDateLike | undefined,
  exit: FlexDateLike | undefined,
  isSheltered: boolean,
  today: Date
): number | null {
  if (!entry || entry.precision !== 'day') return null;
  const start = toUtcDay(entry.value);
  if (start === null) return null;
  let end: number | null;
  if (exit) {
    if (exit.precision !== 'day') return null;
    end = toUtcDay(exit.value);
  } else if (isSheltered) {
    end = Date.UTC(today.getFullYear(), today.getMonth(), today.getDate());
  } else {
    return null;
  }
  if (end === null || end < start) return null;
  return Math.round((end - start) / 86400000);
}
