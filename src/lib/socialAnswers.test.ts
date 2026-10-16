import { describe, expect, it } from 'vitest';
import { buildPayload, draftOf, formatAnswer, SocialAnswerLike, SocialQuestionLike } from './socialAnswers';

const q = (key: string, answer_type: SocialQuestionLike['answer_type'], over: Partial<SocialQuestionLike> = {}): SocialQuestionLike => ({
  id: key, key, label_es: key, section: 'migration', answer_type, has_detail: false, is_sensitive: false, is_active: true, sort_order: 1, ...over,
});
const a = (question_id: string, over: Partial<SocialAnswerLike> = {}): SocialAnswerLike => ({ question_id, ...over });

const yn = q('wants_return', 'yes_no', { has_detail: true });
const num = q('times', 'number');
const txt = q('entry_point', 'text');
const dt = q('release', 'date');

describe('borrador de una respuesta', () => {
  it('sin respuesta registrada el borrador está vacío (no se supone nada)', () => {
    expect(draftOf(yn, undefined)).toEqual({ choice: '', detail: '', number: '', text: '', precision: 'day', date: '' });
  });
  it('con respuesta registrada, el borrador la refleja', () => {
    expect(draftOf(yn, a('wants_return', { choice: 'yes', detail: 'pronto' })).choice).toBe('yes');
    expect(draftOf(num, a('times', { number_value: 3 })).number).toBe('3');
    expect(draftOf(txt, a('entry_point', { text_value: 'Tapachula' })).text).toBe('Tapachula');
  });
  it('la fecha se muestra como la captura el control según su precisión', () => {
    expect(draftOf(dt, a('release', { date_value: '2026-03-01', date_precision: 'month' }))).toMatchObject({ precision: 'month', date: '2026-03' });
    expect(draftOf(dt, a('release', { date_value: '2026-01-01', date_precision: 'year' }))).toMatchObject({ precision: 'year', date: '2026' });
    expect(draftOf(dt, a('release', { date_value: '2026-03-15', date_precision: 'day' }))).toMatchObject({ precision: 'day', date: '2026-03-15' });
  });
});

describe('qué se envía', () => {
  const empty = (qq: SocialQuestionLike) => draftOf(qq, undefined);

  it('solo lo que cambió; lo que no se tocó no viaja', () => {
    const cur = [a('wants_return', { choice: 'no' })];
    const drafts = { wants_return: draftOf(yn, cur[0]), times: { ...empty(num), number: '2' } };
    const r = buildPayload([yn, num], drafts, cur);
    expect(r.payload).toEqual([{ question_key: 'times', number: 2 }]);
    expect(r.needsReason).toBe(false);
  });

  it('cambiar una respuesta ya registrada pide motivo', () => {
    const cur = [a('wants_return', { choice: 'no' })];
    const r = buildPayload([yn], { wants_return: { ...draftOf(yn, cur[0]), choice: 'yes' } }, cur);
    expect(r.payload).toEqual([{ question_key: 'wants_return', choice: 'yes' }]);
    expect(r.needsReason).toBe(true);
  });

  it('dejar vacío algo ya registrado lo quita (y pide motivo)', () => {
    const cur = [a('entry_point', { text_value: 'Tapachula' })];
    const r = buildPayload([txt], { entry_point: { ...draftOf(txt, cur[0]), text: '  ' } }, cur);
    expect(r.payload).toEqual([{ question_key: 'entry_point', clear: true }]);
    expect(r.needsReason).toBe(true);
  });

  it('dejar vacío algo que no estaba no manda nada', () => {
    const r = buildPayload([txt], { entry_point: empty(txt) }, []);
    expect(r.payload).toEqual([]);
    expect(r.needsReason).toBe(false);
  });

  it('el detalle viaja solo con sí o no, y se recorta', () => {
    const r = buildPayload([yn], { wants_return: { ...empty(yn), choice: 'yes', detail: '  Quiere volver  ' } }, []);
    expect(r.payload).toEqual([{ question_key: 'wants_return', choice: 'yes', detail: 'Quiere volver' }]);
    const nr = buildPayload([yn], { wants_return: { ...empty(yn), choice: 'no_response', detail: 'x' } }, []);
    expect(nr.payload).toEqual([{ question_key: 'wants_return', choice: 'no_response' }]);
  });

  it('la fecha viaja con su precisión y como inicio del periodo', () => {
    const r = buildPayload([dt], { release: { ...empty(dt), precision: 'month', date: '2026-03' } }, []);
    expect(r.payload).toEqual([{ question_key: 'release', date: '2026-03-01', precision: 'month' }]);
    const y = buildPayload([dt], { release: { ...empty(dt), precision: 'year', date: '2026' } }, []);
    expect(y.payload).toEqual([{ question_key: 'release', date: '2026-01-01', precision: 'year' }]);
  });

  it('un número no entero o fuera de rango no se envía y se avisa', () => {
    const r = buildPayload([num], { times: { ...empty(num), number: '1.5' } }, []);
    expect(r.payload).toEqual([]);
    expect(r.invalid).toEqual(['times']);
    expect(buildPayload([num], { times: { ...empty(num), number: '1000' } }, []).invalid).toEqual(['times']);
  });
});

describe('cómo se muestra una respuesta', () => {
  it('cada tipo con su texto', () => {
    const labels = { yes: 'Sí', no: 'No', no_response: 'La persona no quiso responder' };
    expect(formatAnswer(yn, a('wants_return', { choice: 'yes', detail: 'pronto' }), labels)).toBe('Sí · pronto');
    expect(formatAnswer(yn, a('wants_return', { choice: 'no_response' }), labels)).toBe('La persona no quiso responder');
    expect(formatAnswer(num, a('times', { number_value: 0 }), labels)).toBe('0');
    expect(formatAnswer(txt, a('entry_point', { text_value: 'Tapachula' }), labels)).toBe('Tapachula');
    expect(formatAnswer(dt, a('release', { date_value: '2026-03-01', date_precision: 'month' }), labels)).toContain('2026');
  });
  it('sin respuesta no hay texto (la pantalla dice «No registrado»)', () => {
    expect(formatAnswer(yn, undefined, { yes: 'Sí', no: 'No', no_response: 'x' })).toBeNull();
  });
});
