import { describe, expect, it } from 'vitest';
import { EVIDENCE_MAX_BYTES, evidencePath, evidenceProblem, scaledSize } from './evidence';

describe('evidenceProblem', () => {
  it('acepta JPEG, PNG y WebP dentro del límite', () => {
    for (const type of ['image/jpeg', 'image/png', 'image/webp']) expect(evidenceProblem({ type, size: 1000 })).toBeNull();
    expect(evidenceProblem({ type: 'image/jpeg', size: EVIDENCE_MAX_BYTES })).toBeNull();
  });
  it('rechaza otros tipos, vacíos y pesados', () => {
    expect(evidenceProblem({ type: 'image/gif', size: 1000 })).toBe('type');
    expect(evidenceProblem({ type: 'application/pdf', size: 1000 })).toBe('type');
    expect(evidenceProblem({ type: 'image/png', size: 0 })).toBe('empty');
    expect(evidenceProblem({ type: 'image/png', size: EVIDENCE_MAX_BYTES + 1 })).toBe('size');
  });
});

describe('scaledSize', () => {
  it('reduce el lado mayor conservando la proporción', () => {
    expect(scaledSize(4000, 3000)).toEqual({ width: 1600, height: 1200 });
    expect(scaledSize(3000, 4000)).toEqual({ width: 1200, height: 1600 });
  });
  it('no agranda lo que ya cabe', () => {
    expect(scaledSize(800, 600)).toEqual({ width: 800, height: 600 });
  });
  it('nunca devuelve cero', () => {
    expect(scaledSize(100000, 1).height).toBe(1);
  });
});

describe('evidencePath', () => {
  it('empieza por organización y tarea y no usa el nombre del archivo', () => {
    expect(evidencePath('org-1', 'task-1', 'image/jpeg', 'abc')).toBe('org-1/task-1/abc.jpg');
    expect(evidencePath('org-1', 'task-1', 'image/webp', 'abc')).toBe('org-1/task-1/abc.webp');
  });
});
