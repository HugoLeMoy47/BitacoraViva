// E17 fase 3 · Áreas: lógica pura de la pantalla «Áreas». La regla (permiso, nombre, marcas, motivo) vive en la base.

/** Personas distintas con un rol vigente en cada área (quien no tiene área no cuenta en ninguna). */
export function peoplePerArea(roles: { user_id: string; area_id: string | null; revoked_at: string | null }[]): Map<string, number> {
  const sets = new Map<string, Set<string>>();
  for (const r of roles) {
    if (r.revoked_at || !r.area_id) continue;
    if (!sets.has(r.area_id)) sets.set(r.area_id, new Set());
    sets.get(r.area_id)!.add(r.user_id);
  }
  return new Map([...sets].map(([area, users]) => [area, users.size]));
}

/** Primero las activas, luego las desactivadas; cada grupo por nombre. */
export function sortAreas<T extends { name: string; active: boolean }>(areas: T[]): T[] {
  return [...areas].sort((x, y) => Number(y.active) - Number(x.active) || x.name.localeCompare(y.name, 'es'));
}
