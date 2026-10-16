// E15 fase 2 · Ficha social: lógica pura del formulario de respuestas (sin React ni base).
// El borrador de cada pregunta nace de la respuesta vigente (o vacío: no se supone nada). Al guardar solo viaja lo que
// cambió; lo que se deja vacío y ya estaba registrado se quita (con motivo). La base valida todo de nuevo.

import { DatePrecision, formatFlexDate, toStoredDate } from './flexDate';

export interface SocialQuestionLike {
  id: string;
  key: string;
  label_es: string;
  section: 'migration' | 'sensitive' | 'origin';
  answer_type: 'yes_no' | 'number' | 'text' | 'date';
  has_detail: boolean;
  is_sensitive: boolean;
  is_active: boolean;
  sort_order: number;
}

export interface SocialAnswerLike {
  question_id: string;
  choice?: 'yes' | 'no' | 'no_response' | null;
  number_value?: number | null;
  text_value?: string | null;
  date_value?: string | null;
  date_precision?: DatePrecision | null;
  detail?: string | null;
}

export interface Draft {
  choice: '' | 'yes' | 'no' | 'no_response';
  detail: string;
  number: string;
  text: string;
  precision: DatePrecision;
  date: string;
}

export type SocialPayloadItem =
  | { question_key: string; clear: true }
  | { question_key: string; choice: string; detail?: string }
  | { question_key: string; number: number }
  | { question_key: string; text: string }
  | { question_key: string; date: string; precision: DatePrecision };

const EMPTY: Draft = { choice: '', detail: '', number: '', text: '', precision: 'day', date: '' };

/** El valor «crudo» que escribe el control de fecha, a partir del inicio del periodo guardado */
const rawDate = (precision: DatePrecision, stored: string): string =>
  precision === 'year' ? stored.slice(0, 4) : precision === 'month' ? stored.slice(0, 7) : stored;

export function draftOf(_q: SocialQuestionLike, a: SocialAnswerLike | undefined): Draft {
  if (!a) return { ...EMPTY };
  const precision = a.date_precision ?? 'day';
  return {
    choice: (a.choice ?? '') as Draft['choice'],
    detail: a.detail ?? '',
    number: a.number_value === null || a.number_value === undefined ? '' : String(a.number_value),
    text: a.text_value ?? '',
    precision,
    date: a.date_value ? rawDate(precision, a.date_value) : '',
  };
}

/** La respuesta que representa un borrador, o null si está vacío; `invalid` si lo escrito no vale */
function valueOf(q: SocialQuestionLike, d: Draft): { item: SocialPayloadItem | null; invalid: boolean } {
  switch (q.answer_type) {
    case 'yes_no': {
      if (!d.choice) return { item: null, invalid: false };
      const detail = d.detail.trim();
      return { item: { question_key: q.key, choice: d.choice, ...(detail && q.has_detail && d.choice !== 'no_response' ? { detail } : {}) }, invalid: false };
    }
    case 'number': {
      const raw = d.number.trim();
      if (raw === '') return { item: null, invalid: false };
      const n = Number(raw);
      return Number.isInteger(n) && n >= 0 && n <= 999 ? { item: { question_key: q.key, number: n }, invalid: false } : { item: null, invalid: true };
    }
    case 'text': {
      const text = d.text.trim();
      return text ? { item: { question_key: q.key, text }, invalid: false } : { item: null, invalid: false };
    }
    default: {
      if (!d.date.trim()) return { item: null, invalid: false };
      const stored = toStoredDate(d.precision, d.date);
      return stored ? { item: { question_key: q.key, date: stored, precision: d.precision }, invalid: false } : { item: null, invalid: true };
    }
  }
}

const sameValue = (_q: SocialQuestionLike, item: SocialPayloadItem, a: SocialAnswerLike): boolean => {
  if ('choice' in item) return a.choice === item.choice && (a.detail ?? '') === (item.detail ?? '');
  if ('number' in item) return a.number_value === item.number;
  if ('text' in item) return a.text_value === item.text;
  if ('date' in item) return a.date_value === item.date && a.date_precision === item.precision;
  return false;
};

export function buildPayload(
  questions: SocialQuestionLike[],
  drafts: Record<string, Draft>,
  current: SocialAnswerLike[]
): { payload: SocialPayloadItem[]; needsReason: boolean; invalid: string[] } {
  const payload: SocialPayloadItem[] = [];
  const invalid: string[] = [];
  let needsReason = false;
  for (const q of questions) {
    const draft = drafts[q.key];
    if (!draft) continue;
    const cur = current.find((c) => c.question_id === q.id);
    const { item, invalid: bad } = valueOf(q, draft);
    if (bad) {
      invalid.push(q.key);
      continue;
    }
    if (!item) {
      if (cur) {
        payload.push({ question_key: q.key, clear: true });
        needsReason = true;
      }
      continue;
    }
    if (cur && sameValue(q, item, cur)) continue;
    payload.push(item);
    if (cur) needsReason = true;
  }
  return { payload, needsReason, invalid };
}

export function formatAnswer(
  q: SocialQuestionLike,
  a: SocialAnswerLike | undefined,
  choiceLabels: { yes: string; no: string; no_response: string }
): string | null {
  if (!a) return null;
  switch (q.answer_type) {
    case 'yes_no': {
      if (!a.choice) return null;
      const base = choiceLabels[a.choice];
      return a.detail ? `${base} · ${a.detail}` : base;
    }
    case 'number':
      return a.number_value === null || a.number_value === undefined ? null : String(a.number_value);
    case 'text':
      return a.text_value ?? null;
    default:
      return a.date_value && a.date_precision ? formatFlexDate(a.date_value, a.date_precision) : null;
  }
}
