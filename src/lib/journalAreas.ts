// Bitácora: en qué áreas puede escribir una cuenta y cuál se propone. Escribir a nombre de un área exige ser de esa área (o dirección);
// quien no tiene área escribe solo en el área general (Ethos C2 y C3). La base lo exige igual: aquí solo se ofrece lo que se puede hacer.
export interface JournalAreaOption {
  id: string;
  name: string;
  is_general: boolean;
  is_default_intake: boolean;
}

export function writableAreas<T extends JournalAreaOption>(allAreas: T[], isDirector: boolean, userAreaIds: string[]): T[] {
  if (isDirector) return allAreas;
  if (userAreaIds.length > 0) return allAreas.filter((a) => userAreaIds.includes(a.id));
  return allAreas.filter((a) => a.is_general);
}

/** El área del caso si se puede escribir en ella; si no, la de apertura por omisión; si no, la primera; sin áreas, vacío. */
export function defaultJournalAreaId(options: JournalAreaOption[], assignedAreaId?: string): string {
  if (assignedAreaId && options.some((a) => a.id === assignedAreaId)) return assignedAreaId;
  return options.find((a) => a.is_default_intake)?.id ?? options[0]?.id ?? '';
}
