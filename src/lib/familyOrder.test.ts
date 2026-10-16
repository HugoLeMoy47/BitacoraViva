import { describe, expect, it } from 'vitest';
import { suggestFamilyOrder, FamilyMemberInput } from './familyOrder';

const m = (caseId: string, roleKey: string | null, birthDate: string | null = '2000-01-01'): FamilyMemberInput => ({ caseId, caseNumber: caseId, roleKey, birthDate });
const ids = (r: ReturnType<typeof suggestFamilyOrder>) => (r.ok ? r.order.map((o) => `${o.order}:${o.caseId}`) : []);

describe('orden sugerido de la familia', () => {
  it('1.º madre, 2.º padre o pareja, 3.º hijos de mayor a menor, 4.º otros', () => {
    const r = suggestFamilyOrder([
      m('otro', 'other', '1960-01-01'),
      m('hijo-menor', 'child', '2020-05-01'),
      m('padre', 'father_partner', '1985-01-01'),
      m('hijo-mayor', 'child', '2010-03-01'),
      m('madre', 'mother', '1987-01-01'),
    ]);
    expect(ids(r)).toEqual(['1:madre', '2:padre', '3:hijo-mayor', '4:hijo-menor', '5:otro']);
  });

  it('el orden es consecutivo desde 1, aunque falten roles de la regla', () => {
    expect(ids(suggestFamilyOrder([m('a', 'child', '2015-01-01'), m('b', 'mother')]))).toEqual(['1:b', '2:a']);
  });

  it('un papel que la organización agregó (no es de los cuatro) cuenta como «otro»', () => {
    expect(ids(suggestFamilyOrder([m('abuela', 'grandmother', '1950-01-01'), m('hijo', 'child', '2018-01-01'), m('madre', 'mother')]))).toEqual(['1:madre', '2:hijo', '3:abuela']);
  });

  it('con la misma fecha de nacimiento (mellizos) desempata el folio', () => {
    expect(ids(suggestFamilyOrder([m('b', 'child', '2015-06-01'), m('a', 'child', '2015-06-01')]))).toEqual(['1:a', '2:b']);
  });

  it('un hijo sin fecha de nacimiento va al final de los hijos (no se supone una edad)', () => {
    expect(ids(suggestFamilyOrder([m('x', 'child', null), m('y', 'child', '2012-01-01')]))).toEqual(['1:y', '2:x']);
  });

  it('si a alguien le falta el papel no se sugiere nada y se dice quién falta', () => {
    const r = suggestFamilyOrder([m('a', 'mother'), m('b', null), m('c', 'child')]);
    expect(r).toEqual({ ok: false, missing: ['b'] });
  });

  it('una familia vacía o de una sola persona no necesita orden', () => {
    expect(suggestFamilyOrder([])).toEqual({ ok: true, order: [] });
    expect(ids(suggestFamilyOrder([m('solo', 'mother')]))).toEqual(['1:solo']);
  });
});
