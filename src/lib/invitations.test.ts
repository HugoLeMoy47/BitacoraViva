import { describe, expect, it } from 'vitest';
import { inviteErrorFromBody } from './invitations';
import { friendlyError } from './errors';

describe('invitar personas: errores de la función', () => {
  it('conserva el código de la base (BVnnn) y la interfaz lo traduce', () => {
    const e = inviteErrorFromBody({ ok: false, code: 'BV356' }, 'x');
    expect(e.code).toBe('BV356');
    expect(friendlyError(e)).toBe('Ese correo ya tiene una cuenta o no se puede invitar.');
  });

  it('el tope por hora y el permiso llegan con su texto', () => {
    expect(friendlyError(inviteErrorFromBody({ ok: false, code: 'BV357' }, 'x'))).toContain('tope de invitaciones');
    expect(friendlyError(inviteErrorFromBody({ ok: false, code: 'BV346' }, 'x'))).toContain('gestión del equipo');
  });

  it('los códigos propios de la función también tienen texto', () => {
    expect(friendlyError(inviteErrorFromBody({ ok: false, code: 'INVITE_SEND_FAILED' }, 'x'))).toContain('No se pudo enviar el correo');
    expect(friendlyError(inviteErrorFromBody({ ok: false, code: 'INVITE_FAILED' }, 'x'))).toContain('No se pudo completar la invitación');
    expect(friendlyError(inviteErrorFromBody({ ok: false, code: 'ORIGIN_NOT_ALLOWED' }, 'x'))).toContain('no está autorizada');
  });

  it('un cuerpo desconocido no se muestra tal cual: error genérico', () => {
    const e = inviteErrorFromBody({ ok: false, code: 'algo raro <script>' }, 'FunctionsHttpError');
    expect(e.code).toBeUndefined();
    expect(friendlyError(e)).not.toContain('<script>');
  });

  it('sin cuerpo (red caída) se trata como error de red o genérico', () => {
    expect(inviteErrorFromBody(null, 'Failed to fetch').message).toBe('Failed to fetch');
    expect(friendlyError(inviteErrorFromBody(null, 'Failed to fetch'))).toBe(friendlyError(new Error('Failed to fetch')));
  });
});
