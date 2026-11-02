// Documentos con que se identifica la persona (ciclo «Ingreso y expediente»). «No cuenta con documentos» (`none`) es una respuesta
// explícita y excluyente; sin selección queda «No registrado». La base lo vuelve a exigir (BV367 y una restricción de la tabla).
export const NONE_KEY = 'none';

/** Marca o desmarca un documento: «ninguno» desmarca todo lo demás y, mientras esté marcado, las demás opciones no se tocan. */
export function toggleIdentityDocument(selected: string[], key: string): string[] {
  if (key === NONE_KEY) return selected.includes(NONE_KEY) ? [] : [NONE_KEY];
  if (selected.includes(NONE_KEY)) return selected;
  return selected.includes(key) ? selected.filter((k) => k !== key) : [...selected, key];
}

/** Con «ninguno» marcado, las demás opciones se deshabilitan. */
export const isDisabledByNone = (selected: string[], key: string): boolean => key !== NONE_KEY && selected.includes(NONE_KEY);

/** Lo que se envía: «ninguno» solo, los elegidos, o nada (null = No registrado). */
export function toSubmit(selected: string[]): string[] | null {
  if (selected.includes(NONE_KEY)) return [NONE_KEY];
  return selected.length > 0 ? selected : null;
}
