// E14 fase 4 · Plantillas de bitácora y llamadas de atención.
// Las plantillas solo ayudan a redactar: el resultado es TEXTO de una entrada de bitácora (inmutable, privada del área).
// Una sección sin texto no se escribe; no se inventa nada para rellenar (regla «cero valores supuestos»).

import type { JournalEntryType } from '../types/database';

export type TemplateType = Extract<JournalEntryType, 'diagnosis' | 'case_meeting'>;

/** Claves de las secciones de cada plantilla (sus títulos están en es.json, `journal.templates.<tipo>.<clave>`) */
export const TEMPLATES: Record<TemplateType, string[]> = {
  diagnosis: ['family', 'intake', 'exit_reason', 'in_mexico', 'plan', 'health'],
  case_meeting: ['detected', 'done', 'referred'],
};

export const hasTemplate = (type: string): type is TemplateType => type in TEMPLATES;

export const composeBody = (sections: { title: string; text: string }[]): string =>
  sections
    .map((s) => ({ title: s.title, text: s.text.trim() }))
    .filter((s) => s.text !== '')
    .map((s) => `${s.title}\n${s.text}`)
    .join('\n\n');

interface WarningLike {
  id: string;
  entry_type_key: string;
  occurred_at: string;
  created_at?: string;
}

/** 1.ª, 2.ª, 3.ª llamada de atención del expediente, según cuándo ocurrió (se deriva; no se captura) */
export const warningOrdinals = (entries: WarningLike[]): Map<string, number> => {
  const sorted = entries
    .filter((e) => e.entry_type_key === 'warning')
    .sort((a, b) => a.occurred_at.localeCompare(b.occurred_at) || (a.created_at ?? '').localeCompare(b.created_at ?? ''));
  return new Map(sorted.map((e, i) => [e.id, i + 1]));
};

export const ordinalLabelKey = (n: number): string => (n >= 1 && n <= 3 ? `journal.warning_ordinal_${n}` : 'journal.warning_ordinal_n');
