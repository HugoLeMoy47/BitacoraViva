import { describe, expect, it } from 'vitest';
import { DbError, friendlyError } from './errors';
import { TaskError, taskErrorMessage } from './tasks';
import { t } from './i18n';

// E13 fase 1: la interfaz traduce los errores de la base por CÓDIGO, no buscando palabras en el mensaje.

describe('friendlyError con código de la plataforma (BVnnn)', () => {
  it('muestra el texto del código y no el mensaje crudo de la base', () => {
    const e = new DbError('Acceso denegado: La anonimización irreversible está reservada exclusivamente al rol director (ADR-0001).', 'BV104');
    const texto = friendlyError(e);
    expect(texto).toBe(t('errors.db.bv104'));
    expect(texto).not.toMatch(/ADR-0001|Ethos|BV-\d|fn_/);
  });

  it('entiende el código aunque el mensaje de la base cambie de idioma o de redacción', () => {
    expect(friendlyError(new DbError('Access denied: only management may anonymize.', 'BV104'))).toBe(t('errors.db.bv104'));
  });

  it('un código sin texto cae en el mensaje genérico, sin romperse', () => {
    const texto = friendlyError(new DbError('algo raro', 'BV999'));
    expect(texto).toContain('algo raro');
  });

  it('sin código, sigue reconociendo los errores de red y de sesión como antes', () => {
    expect(friendlyError(new DbError('Failed to fetch'))).toBe(t('errors.network'));
    expect(friendlyError('JWT expired')).toBe(t('errors.session'));
  });

  it('acepta un texto suelto (compatibilidad con quien aún pasa cadenas)', () => {
    expect(friendlyError('duplicate key value violates unique constraint')).toBe(t('errors.duplicate'));
  });
});

describe('errores de tareas', () => {
  it('conservan sus códigos TK y, si llega un código BV, usan el texto de la plataforma', () => {
    expect(taskErrorMessage(new TaskError('x', 'TK002'))).toBe(t('errors.task.tk002'));
    expect(taskErrorMessage(new TaskError('mensaje de la base', 'BV113'))).toBe(t('errors.db.bv113'));
  });
});
