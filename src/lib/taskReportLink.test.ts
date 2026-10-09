import { describe, expect, it } from 'vitest';
import { INITIAL_SORT, readLink, sanitizeFilters, writeLink } from './taskReportLink';
import { EMPTY_FILTERS, UNASSIGNED } from './taskReports';

describe('writeLink', () => {
  it('una vista sin tocar no ensucia la URL', () => {
    expect(writeLink({ tab: 'overview', filters: EMPTY_FILTERS, sort: null })).toBe('');
    expect(writeLink({ tab: 'status', filters: EMPTY_FILTERS, sort: INITIAL_SORT.status! })).toBe('vista=status');
  });

  it('escribe sólo lo que se aparta del valor por defecto', () => {
    const q = writeLink({ tab: 'person', filters: { ...EMPTY_FILTERS, period: '30', status: 'done', person: 'u1' }, sort: { field: 'due', direction: 'asc' } });
    const p = new URLSearchParams(q);
    expect(p.get('vista')).toBe('person');
    expect(p.get('periodo')).toBe('30');
    expect(p.get('estado')).toBe('done');
    expect(p.get('persona')).toBe('u1');
    expect(p.get('orden')).toBe('due:asc');
    expect(p.has('area')).toBe(false);
  });

  it('la búsqueda por texto NO viaja en el enlace (puede ser el nombre de una persona atendida)', () => {
    const q = writeLink({ tab: 'overview', filters: { ...EMPTY_FILTERS, search: 'Wendy Ramos' }, sort: null });
    expect(q).toBe('');
    expect(q).not.toContain('Wendy');
  });
});

describe('readLink', () => {
  it('lo que se escribe se lee igual (ida y vuelta)', () => {
    const state = { tab: 'date' as const, filters: { ...EMPTY_FILTERS, period: '90' as const, category: 'c9' }, sort: { field: 'done' as const, direction: 'asc' as const } };
    expect(readLink(writeLink(state))).toEqual(state);
  });

  it('un enlace mal editado abre el reporte normal en vez de romperse', () => {
    const s = readLink('vista=inexistente&periodo=7&estado=cancelada&orden=nada:raro');
    expect(s.tab).toBe('overview');
    expect(s.filters.period).toBe('all');
    expect(s.filters.status).toBe('');
    expect(s.sort).toBeNull();
  });

  it('ignora un `q=` viejo: la búsqueda no se lee de la URL', () => {
    expect(readLink('q=Wendy').filters.search).toBe('');
  });

  it('el resumen no tiene orden: no se inventa uno', () => {
    expect(readLink('orden=due:asc').sort).toBeNull();
    expect(readLink('vista=status&orden=due:asc').sort).toEqual({ field: 'due', direction: 'asc' });
  });

  it('recorta valores enormes que llegan de fuera', () => {
    expect(readLink(`persona=${'x'.repeat(500)}`).filters.person.length).toBe(120);
  });
});

describe('sanitizeFilters', () => {
  const valid = { persons: ['u1'], workAreas: ['a1'], categories: ['c1'] };

  it('descarta personas, áreas y categorías que ya no existen', () => {
    const f = sanitizeFilters({ ...EMPTY_FILTERS, person: 'se-fue', workArea: 'a-vieja', category: 'c1' }, valid);
    expect([f.person, f.workArea, f.category]).toEqual(['', '', 'c1']);
  });

  it('«sin asignar» no sale de los datos: se conserva', () => {
    expect(sanitizeFilters({ ...EMPTY_FILTERS, person: UNASSIGNED }, valid).person).toBe(UNASSIGNED);
  });
});
