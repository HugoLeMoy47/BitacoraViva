import { describe, expect, it } from 'vitest';
import { makeTask } from './taskTestUtils';
import {
  EMPTY_FILTERS,
  UNASSIGNED,
  applyFilters,
  daysBetween,
  globalMetrics,
  groupCounts,
  hasActiveFilters,
  normalize,
  personKey,
  personMetrics,
  recurringTasks,
  sortTasks,
  statusSummary,
  weekStart,
  weeklySeries,
  Lookups,
} from './taskReports';

const NOW = new Date(2026, 8, 10, 12, 0); // jueves 10 sep 2026
const iso = (s: string) => new Date(s).toISOString();

describe('statusSummary', () => {
  it('cuenta cada estado y conserva los tres aunque haya ceros', () => {
    const r = statusSummary([makeTask({ status: 'pending' }), makeTask({ status: 'done' }), makeTask({ status: 'done' })]);
    expect(r).toEqual([
      { status: 'pending', count: 1 },
      { status: 'in_progress', count: 0 },
      { status: 'done', count: 2 },
    ]);
    expect(statusSummary([]).every((s) => s.count === 0)).toBe(true);
  });
});

describe('groupCounts', () => {
  const name = (k: string) => (k === UNASSIGNED ? 'Sin asignar' : k);

  it('desglosa por estado y agrupa lo sin persona', () => {
    const rows = groupCounts(
      [makeTask({ assigned_to: 'Ana', status: 'pending' }), makeTask({ assigned_to: 'Ana', status: 'done' }), makeTask({ assigned_to: null })],
      personKey,
      name
    );
    expect(rows.find((r) => r.key === 'Ana')?.counts).toEqual({ pending: 1, in_progress: 0, done: 1, total: 2 });
    expect(rows.find((r) => r.key === UNASSIGNED)?.name).toBe('Sin asignar');
  });

  it('ordena por total descendente y, a igualdad, alfabético (estable entre recargas)', () => {
    const rows = groupCounts(
      [makeTask({ assigned_to: 'Zoe' }), makeTask({ assigned_to: 'Ana' }), makeTask({ assigned_to: 'Beto' }), makeTask({ assigned_to: 'Beto' })],
      personKey,
      name
    );
    expect(rows.map((r) => r.name)).toEqual(['Beto', 'Ana', 'Zoe']);
  });
});

describe('weekStart', () => {
  it('un miércoles retrocede al lunes a las 00:00', () => {
    const l = weekStart(new Date(2026, 8, 2, 15, 30))!;
    expect([l.getDay(), l.getDate(), l.getHours()]).toEqual([1, 31, 0]);
  });
  it('un lunes se queda; un domingo pertenece a la semana que empezó el lunes anterior', () => {
    expect(weekStart(new Date(2026, 7, 31, 23, 59))!.getDate()).toBe(31);
    expect(weekStart(new Date(2026, 8, 6, 12, 0))!.getDate()).toBe(31);
  });
  it('devuelve nulo ante una fecha inválida', () => {
    expect(weekStart('no-es-fecha')).toBeNull();
  });
});

describe('weeklySeries', () => {
  const REF = new Date(2026, 8, 2, 12, 0);

  it('emite las semanas pedidas, también las vacías, de la más antigua a la más reciente', () => {
    const s = weeklySeries([], 3, REF);
    expect(s).toHaveLength(3);
    expect(s.every((b) => b.created === 0 && b.closed === 0)).toBe(true);
    expect(s[0].start.getTime()).toBeLessThan(s[2].start.getTime());
    expect(s[2].start.getDate()).toBe(31);
  });

  it('cuenta creadas y cerradas en su semana, aunque caigan en semanas distintas', () => {
    const s = weeklySeries(
      [
        makeTask({ created_at: new Date(2026, 7, 25).toISOString(), done_at: new Date(2026, 8, 2).toISOString() }),
        makeTask({ created_at: new Date(2026, 8, 1).toISOString() }),
      ],
      3,
      REF
    );
    expect([s[1].created, s[1].closed]).toEqual([1, 0]);
    expect([s[2].created, s[2].closed]).toEqual([1, 1]);
  });

  it('ignora lo que cae fuera del rango en vez de apilarlo en el borde', () => {
    const s = weeklySeries([makeTask({ created_at: new Date(2025, 0, 1).toISOString() })], 3, REF);
    expect(s.reduce((n, b) => n + b.created, 0)).toBe(0);
  });
});

describe('daysBetween', () => {
  it('mide la diferencia en días y devuelve nulo si falta un extremo', () => {
    expect(daysBetween(iso('2026-09-01T00:00:00Z'), iso('2026-09-03T00:00:00Z'))).toBe(2);
    expect(daysBetween(iso('2026-09-01T00:00:00Z'), iso('2026-09-01T12:00:00Z'))).toBe(0.5);
    expect(daysBetween(null, iso('2026-09-01T00:00:00Z'))).toBeNull();
    expect(daysBetween('no-es-fecha', iso('2026-09-01T00:00:00Z'))).toBeNull();
  });
});

describe('globalMetrics', () => {
  const done = makeTask({ status: 'done', created_at: iso('2026-09-01T00:00:00Z'), started_at: iso('2026-09-02T00:00:00Z'), done_at: iso('2026-09-04T00:00:00Z') });

  it('mide espera, trabajo y total sobre las poblaciones correctas', () => {
    const m = globalMetrics([done, makeTask({ status: 'in_progress', created_at: iso('2026-09-01T00:00:00Z'), started_at: iso('2026-09-03T00:00:00Z') })], NOW);
    expect(m.waitMean).toBe(1.5); // sobre las dos que ya empezaron: 1 d y 2 d
    expect(m.workMean).toBe(2); // sólo la cerrada con inicio
    expect(m.totalMean).toBe(3); // sólo la cerrada
    expect(m.percentDone).toBe(50);
  });

  it('las cerradas sin marca de inicio quedan fuera de los promedios y se cuentan aparte', () => {
    const legacy = makeTask({ status: 'done', created_at: iso('2026-08-01T00:00:00Z'), done_at: iso('2026-08-05T00:00:00Z') });
    const m = globalMetrics([done, legacy], NOW);
    expect(m.unmeasured).toBe(1);
    expect(m.workMean).toBe(2);
  });

  it('con lista vacía no inventa promedios', () => {
    const m = globalMetrics([], NOW);
    expect([m.waitMean, m.workMean, m.totalMean, m.percentDone]).toEqual([null, null, null, 0]);
  });

  it('cuenta las vencidas: abiertas con límite pasado', () => {
    const m = globalMetrics(
      [makeTask({ due_at: '2026-09-01' }), makeTask({ due_at: '2026-09-10' }), makeTask({ status: 'done', due_at: '2026-09-01' })],
      NOW
    );
    expect(m.overdue).toBe(1);
  });
});

describe('personMetrics', () => {
  it('espera y trabajo se miden sobre LA MISMA población (cerradas con inicio): su suma es el ciclo', () => {
    const rows = personMetrics(
      [
        makeTask({ assigned_to: 'Ana', status: 'done', created_at: iso('2026-09-01T00:00:00Z'), started_at: iso('2026-09-02T00:00:00Z'), done_at: iso('2026-09-04T00:00:00Z') }),
        // iniciada pero abierta: NO entra en la espera, o las dos cifras serían de universos distintos
        makeTask({ assigned_to: 'Ana', status: 'in_progress', created_at: iso('2026-09-01T00:00:00Z'), started_at: iso('2026-09-09T00:00:00Z') }),
      ],
      (k) => k
    );
    expect(rows[0]).toMatchObject({ name: 'Ana', wait: 1, work: 2, cycle: 3, done: 1, open: 1, measured: 1 });
  });

  it('una persona sin cerradas medibles queda sin ciclo y al final', () => {
    const rows = personMetrics(
      [
        makeTask({ assigned_to: 'Beto', status: 'pending' }),
        makeTask({ assigned_to: 'Ana', status: 'done', created_at: iso('2026-09-01T00:00:00Z'), started_at: iso('2026-09-01T00:00:00Z'), done_at: iso('2026-09-02T00:00:00Z') }),
      ],
      (k) => k
    );
    expect(rows.map((r) => r.name)).toEqual(['Ana', 'Beto']);
    expect(rows[1].cycle).toBeNull();
  });
});

describe('recurringTasks', () => {
  it('agrupa por nombre exacto y exige un mínimo de repeticiones', () => {
    const r = recurringTasks([makeTask({ name: 'Barrer' }), makeTask({ name: 'Barrer' }), makeTask({ name: 'Trapear' })]);
    expect(r).toHaveLength(1);
    expect(r[0]).toMatchObject({ name: 'Barrer', times: 2 });
  });
});

describe('normalize y applyFilters', () => {
  const tasks = [
    makeTask({ name: 'Limpiar los Baños', assigned_to: 'ana', status: 'pending', work_area_id: 'a1', task_category_id: 'c1' }),
    makeTask({ name: 'Cocinar', assigned_to: null, status: 'done', work_area_id: 'a2', task_category_id: 'c2', created_at: '2026-01-01T00:00:00.000Z' }),
  ];

  it('normalize quita acentos y mayúsculas: «bano» encuentra «Baños»', () => {
    expect(normalize('Baños')).toBe('banos');
    expect(applyFilters(tasks, { ...EMPTY_FILTERS, search: 'bano' }, NOW)).toHaveLength(1);
  });

  it('sin filtros devuelve todo; hasActiveFilters lo refleja', () => {
    expect(applyFilters(tasks, EMPTY_FILTERS, NOW)).toHaveLength(2);
    expect(hasActiveFilters(EMPTY_FILTERS)).toBe(false);
    expect(hasActiveFilters({ ...EMPTY_FILTERS, status: 'done' })).toBe(true);
  });

  it('filtra por persona (incluida la opción sintética «sin asignar»), estado, área y categoría', () => {
    expect(applyFilters(tasks, { ...EMPTY_FILTERS, person: 'ana' }, NOW).map((t) => t.name)).toEqual(['Limpiar los Baños']);
    expect(applyFilters(tasks, { ...EMPTY_FILTERS, person: UNASSIGNED }, NOW).map((t) => t.name)).toEqual(['Cocinar']);
    expect(applyFilters(tasks, { ...EMPTY_FILTERS, status: 'done' }, NOW)).toHaveLength(1);
    expect(applyFilters(tasks, { ...EMPTY_FILTERS, workArea: 'a2' }, NOW)).toHaveLength(1);
    expect(applyFilters(tasks, { ...EMPTY_FILTERS, category: 'c1' }, NOW)).toHaveLength(1);
  });

  it('el periodo excluye lo creado antes de la ventana', () => {
    const r = applyFilters(tasks, { ...EMPTY_FILTERS, period: '30' }, NOW);
    expect(r.map((t) => t.name)).toEqual(['Limpiar los Baños']);
  });
});

describe('sortTasks', () => {
  const lk: Lookups = { person: (id) => id, category: (id) => id, workArea: (id) => id };

  it('los vacíos van SIEMPRE al final, en ambas direcciones', () => {
    const t = [makeTask({ name: 'a', assigned_to: null }), makeTask({ name: 'b', assigned_to: 'Zoe' }), makeTask({ name: 'c', assigned_to: 'Ana' })];
    expect(sortTasks(t, { field: 'person', direction: 'asc' }, lk).map((x) => x.name)).toEqual(['c', 'b', 'a']);
    expect(sortTasks(t, { field: 'person', direction: 'desc' }, lk).map((x) => x.name)).toEqual(['b', 'c', 'a']);
  });

  it('el estado ordena por el flujo, no alfabéticamente', () => {
    const t = [makeTask({ name: 'x', status: 'done' }), makeTask({ name: 'y', status: 'pending' }), makeTask({ name: 'z', status: 'in_progress' })];
    expect(sortTasks(t, { field: 'status', direction: 'asc' }, lk).map((x) => x.status)).toEqual(['pending', 'in_progress', 'done']);
  });

  it('no muta el arreglo original y desempata por nombre', () => {
    const t = [makeTask({ name: 'b' }), makeTask({ name: 'a' })];
    const out = sortTasks(t, { field: 'created', direction: 'desc' }, lk);
    expect(out.map((x) => x.name)).toEqual(['a', 'b']);
    expect(t.map((x) => x.name)).toEqual(['b', 'a']);
  });
});
