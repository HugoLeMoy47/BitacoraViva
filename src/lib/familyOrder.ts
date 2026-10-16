// E15 fase 4 · Orden sugerido dentro de la familia, según la regla de la matriz de Trabajo Social:
// 1.º madre, 2.º padre o pareja, 3.º hijas e hijos de mayor a menor, 4.º otros.
// Es una SUGERENCIA: aplicarla es manual, un expediente a la vez. Si a alguien le falta el papel no se sugiere nada
// (no se supone el papel de nadie). Un papel que la organización agregó al diccionario cuenta como «otro».

export interface FamilyMemberInput {
  caseId: string;
  caseNumber: string;
  /** `key` del papel en la familia (diccionario `family_role`); null = no registrado */
  roleKey: string | null;
  birthDate: string | null;
}

export type OrderSuggestion = { ok: true; order: { caseId: string; order: number }[] } | { ok: false; missing: string[] };

const GROUP: Record<string, number> = { mother: 1, father_partner: 2, child: 3 };
const groupOf = (roleKey: string): number => GROUP[roleKey] ?? 4;

export function suggestFamilyOrder(members: FamilyMemberInput[]): OrderSuggestion {
  const missing = members.filter((m) => !m.roleKey).map((m) => m.caseId);
  if (missing.length > 0) return { ok: false, missing };
  const sorted = [...members].sort((a, b) => {
    const g = groupOf(a.roleKey!) - groupOf(b.roleKey!);
    if (g !== 0) return g;
    // Dentro de un grupo, de mayor a menor edad (fecha de nacimiento más antigua primero); sin fecha, al final
    if (a.birthDate !== b.birthDate) {
      if (!a.birthDate) return 1;
      if (!b.birthDate) return -1;
      return a.birthDate.localeCompare(b.birthDate);
    }
    return a.caseNumber.localeCompare(b.caseNumber);
  });
  return { ok: true, order: sorted.map((m, i) => ({ caseId: m.caseId, order: i + 1 })) };
}
