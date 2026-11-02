import { describe, expect, it } from 'vitest';
import { isDisabledByNone, toggleIdentityDocument, toSubmit } from './identityDocuments';

describe('documentos de identificación: «No cuenta con documentos» es excluyente', () => {
  it('marcar «ninguno» desmarca todo lo demás', () => {
    expect(toggleIdentityDocument(['passport', 'curp'], 'none')).toEqual(['none']);
  });
  it('con «ninguno» marcado, las demás opciones quedan deshabilitadas', () => {
    expect(isDisabledByNone(['none'], 'passport')).toBe(true);
    expect(isDisabledByNone(['none'], 'none')).toBe(false);
    expect(isDisabledByNone(['passport'], 'curp')).toBe(false);
    expect(isDisabledByNone([], 'passport')).toBe(false);
  });
  it('tocar otra opción con «ninguno» marcado no hace nada', () => {
    expect(toggleIdentityDocument(['none'], 'passport')).toEqual(['none']);
  });
  it('se puede desmarcar «ninguno» y volver a elegir', () => {
    const sinNinguno = toggleIdentityDocument(['none'], 'none');
    expect(sinNinguno).toEqual([]);
    expect(toggleIdentityDocument(sinNinguno, 'passport')).toEqual(['passport']);
  });
  it('marca y desmarca las demás opciones sin repetir', () => {
    expect(toggleIdentityDocument([], 'passport')).toEqual(['passport']);
    expect(toggleIdentityDocument(['passport'], 'curp')).toEqual(['passport', 'curp']);
    expect(toggleIdentityDocument(['passport', 'curp'], 'passport')).toEqual(['curp']);
  });
});

describe('qué se envía al guardar', () => {
  it('«ninguno» viaja solo, como respuesta explícita', () => {
    expect(toSubmit(['none'])).toEqual(['none']);
  });
  it('sin selección no se envía nada (No registrado), no «ninguno»', () => {
    expect(toSubmit([])).toBeNull();
  });
  it('nunca se envía «ninguno» junto con otros, aunque llegue así', () => {
    expect(toSubmit(['none', 'passport'])).toEqual(['none']);
  });
  it('se envían los elegidos', () => {
    expect(toSubmit(['passport', 'curp'])).toEqual(['passport', 'curp']);
  });
});
