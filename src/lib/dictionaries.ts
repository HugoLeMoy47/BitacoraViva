// Diccionarios editables (E14): ayudas puras de la pantalla «Diccionarios».
// La regla de quién escribe vive en la base (`can_manage_catalogs()`); aquí solo se decide qué mostrar y se revisa lo
// escrito antes de enviarlo para dar un mensaje claro (la base lo vuelve a exigir).

/** Clave estable de un valor nuevo, a partir de su nombre; no pisa la de otro valor */
export function keyFromLabel(label: string, existingKeys: string[]): string {
  const base =
    label
      .normalize('NFD')
      .replace(/[̀-ͯ]/g, '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '_')
      .replace(/^_+|_+$/g, '')
      .slice(0, 40)
      .replace(/_+$/g, '') || 'valor';
  if (!existingKeys.includes(base)) return base;
  let n = 2;
  while (existingKeys.includes(`${base}_${n}`)) n += 1;
  return `${base}_${n}`;
}

export interface BandRow {
  label: string;
  minAge: string;
}

/** Clave de traducción del primer problema de los grupos por edad, o null si están bien */
export function validateBands(rows: BandRow[]): string | null {
  if (rows.length === 0) return 'dictionaries.bands_err_empty';
  if (rows.length > 12) return 'dictionaries.bands_err_max';
  const seen = new Set<string>();
  let prev = -1;
  for (let i = 0; i < rows.length; i += 1) {
    const label = rows[i].label.trim();
    if (!label) return 'dictionaries.bands_err_name';
    if (!/^\d{1,3}$/.test(rows[i].minAge.trim())) return 'dictionaries.bands_err_age';
    const age = Number(rows[i].minAge.trim());
    if (i === 0 && age !== 0) return 'dictionaries.bands_err_first';
    if (age <= prev) return 'dictionaries.bands_err_order';
    if (seen.has(label.toLowerCase())) return 'dictionaries.bands_err_dup';
    seen.add(label.toLowerCase());
    prev = age;
  }
  return null;
}
