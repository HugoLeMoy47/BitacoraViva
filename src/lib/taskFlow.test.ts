import { describe, expect, it } from 'vitest';
import { makeTask } from './taskTestUtils';
import { availableAdvance, canMove, groupByStatus, isOverdue, nextStatus, progressOf } from './taskFlow';
import { makeCatalogKey } from './tasks';

describe('nextStatus', () => {
  it('sigue el flujo y termina en hecha', () => {
    expect(nextStatus('pending')).toBe('in_progress');
    expect(nextStatus('in_progress')).toBe('done');
    expect(nextStatus('done')).toBeNull();
  });
});

describe('availableAdvance', () => {
  const ctx = { isManagement: false, hasEvidence: false };

  it('ofrece el siguiente estado y nada al final', () => {
    expect(availableAdvance(makeTask({ status: 'pending' }), ctx)).toMatchObject({ to: 'in_progress', needsPhoto: false });
    expect(availableAdvance(makeTask({ status: 'done' }), ctx)).toBeNull();
  });

  it('anuncia la foto antes de pulsar: cerrar una tarea que la exige sin evidencia', () => {
    const t = makeTask({ status: 'in_progress', photo_required: true });
    expect(availableAdvance(t, ctx)).toMatchObject({ to: 'done', needsPhoto: true, labelKey: 'tasks.action_finish_photo' });
    expect(availableAdvance(t, { ...ctx, hasEvidence: true })).toMatchObject({ needsPhoto: false, labelKey: 'tasks.action_finish' });
  });

  it('la coordinación se salta la exigencia de foto (decisión de producto)', () => {
    const t = makeTask({ status: 'in_progress', photo_required: true });
    expect(availableAdvance(t, { isManagement: true, hasEvidence: false })?.needsPhoto).toBe(false);
  });
});

describe('canMove (espejo de TK002)', () => {
  it('quien no gestiona sólo avanza, también saltando un estado', () => {
    const t = makeTask({ status: 'pending' });
    expect(canMove(t, 'in_progress', false)).toBe(true);
    expect(canMove(t, 'done', false)).toBe(true);
    expect(canMove(makeTask({ status: 'in_progress' }), 'pending', false)).toBe(false);
    expect(canMove(makeTask({ status: 'done' }), 'in_progress', false)).toBe(false);
  });
  it('la gestión mueve en cualquier sentido, pero no al mismo estado', () => {
    expect(canMove(makeTask({ status: 'done' }), 'in_progress', true)).toBe(true);
    expect(canMove(makeTask({ status: 'done' }), 'done', true)).toBe(false);
  });
});

describe('isOverdue', () => {
  const now = new Date(2026, 8, 10, 12, 0);
  it('vence una abierta con límite pasado; el límite de hoy todavía no', () => {
    expect(isOverdue(makeTask({ due_at: '2026-09-01' }), now)).toBe(true);
    expect(isOverdue(makeTask({ due_at: '2026-09-10' }), now)).toBe(false);
  });
  it('una hecha nunca está vencida y sin límite no vence', () => {
    expect(isOverdue(makeTask({ status: 'done', due_at: '2026-09-01' }), now)).toBe(false);
    expect(isOverdue(makeTask({ due_at: null }), now)).toBe(false);
  });
});

describe('progressOf y groupByStatus', () => {
  it('calcula el avance de la jornada', () => {
    const p = progressOf([makeTask({ status: 'done' }), makeTask({ status: 'done' }), makeTask({ status: 'in_progress' }), makeTask({ status: 'pending' })]);
    expect(p).toEqual({ total: 4, pending: 1, inProgress: 1, done: 2, percent: 50, allDone: false });
  });
  it('sin tareas no hay avance ni «todo hecho» (un día vacío no es un día cumplido)', () => {
    expect(progressOf([])).toMatchObject({ total: 0, percent: 0, allDone: false });
  });
  it('todo hecho se reconoce', () => {
    expect(progressOf([makeTask({ status: 'done' })]).allDone).toBe(true);
  });
  it('agrupa por estado', () => {
    const g = groupByStatus([makeTask({ status: 'done' }), makeTask({ status: 'pending' }), makeTask({ status: 'pending' })]);
    expect([g.pending.length, g.in_progress.length, g.done.length]).toEqual([2, 0, 1]);
  });
});

describe('makeCatalogKey (formato que exige la base: ^[a-z][a-z0-9_]{1,39}$)', () => {
  const valid = /^[a-z][a-z0-9_]{1,39}$/;

  it('normaliza acentos y símbolos', () => {
    expect(makeCatalogKey('Limpieza e higiene', [])).toBe('limpieza_e_higiene');
    expect(makeCatalogKey('  Cocina — ¡grande!  ', [])).toBe('cocina_grande');
  });
  it('siempre empieza con letra y respeta el largo', () => {
    expect(valid.test(makeCatalogKey('2do piso', []))).toBe(true);
    expect(valid.test(makeCatalogKey('***', []))).toBe(true);
    expect(valid.test(makeCatalogKey('x'.repeat(200), []))).toBe(true);
  });
  it('no reutiliza una clave existente, tampoco la archivada', () => {
    expect(makeCatalogKey('Cocina', ['cocina'])).toBe('cocina_2');
    expect(makeCatalogKey('Cocina', ['cocina', 'cocina_2'])).toBe('cocina_3');
  });
});
