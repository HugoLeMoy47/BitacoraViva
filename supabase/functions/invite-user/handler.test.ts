import { describe, expect, it, vi } from 'vitest';
import { handle, type Deps } from './handler';

// La regla de quién puede invitar vive en la base (fn_prepare_invitation). Aquí se prueba lo que sí hace la función:
// pasar la sesión de quien invita, usar la llave solo para invitar y completar, deshacer si algo falla, y no abrir la puerta
// a otros orígenes.
const ORIGIN = 'https://bitacora.example';
const REDIRECT = 'https://bitacora.example/#/bienvenida';

function deps(over: Partial<{
  prepare: { data: unknown; error: { code?: string; message: string } | null };
  invite: { userId: string | null; error: string | null };
  complete: { error: { code?: string } | null };
}> = {}) {
  const calls: { rpcAsCaller: unknown[]; invite: unknown[]; complete: unknown[]; deleted: string[]; logs: string[]; authorization: string[] } = {
    rpcAsCaller: [], invite: [], complete: [], deleted: [], logs: [], authorization: [],
  };
  const d: Deps = {
    allowedOrigins: [ORIGIN],
    redirectTo: REDIRECT,
    asCaller: (authorization) => {
      calls.authorization.push(authorization);
      return {
        rpc: async (name, args) => {
          calls.rpcAsCaller.push([name, args]);
          return over.prepare ?? { data: { invitation_id: 'inv-1', resend: false, user_id: null }, error: null };
        },
      };
    },
    admin: {
      invite: async (email, redirectTo, data) => {
        calls.invite.push([email, redirectTo, data]);
        return over.invite ?? { userId: 'user-1', error: null };
      },
      deleteUser: async (id) => { calls.deleted.push(id); },
      completeInvitation: async (invitationId, userId) => {
        calls.complete.push([invitationId, userId]);
        return over.complete ?? { error: null };
      },
    },
    log: (msg, fields) => { calls.logs.push(msg + ' ' + JSON.stringify(fields)); },
  };
  return { d, calls };
}

const post = (body: unknown, headers: Record<string, string> = {}) =>
  new Request('https://x.supabase.co/functions/v1/invite-user', {
    method: 'POST',
    headers: { 'content-type': 'application/json', origin: ORIGIN, authorization: 'Bearer jwt-de-quien-invita', ...headers },
    body: JSON.stringify(body),
  });
const json = async (r: Response) => (await r.json()) as Record<string, unknown>;

describe('invite-user · la función delgada de ADR-0010', () => {
  it('invita: prepara con la sesión de quien invita, invita por correo y completa; responde ok', async () => {
    const { d, calls } = deps();
    const r = await handle(post({ email: 'Nueva@Tst.invalid', full_name: 'Nueva Persona' }), d);
    expect(r.status).toBe(200);
    expect(await json(r)).toEqual({ ok: true, resend: false });
    expect(calls.authorization).toEqual(['Bearer jwt-de-quien-invita']);
    expect(calls.rpcAsCaller).toEqual([['fn_prepare_invitation', { p_email: 'Nueva@Tst.invalid', p_full_name: 'Nueva Persona' }]]);
    expect(calls.invite).toEqual([['nueva@tst.invalid', REDIRECT, { full_name: 'Nueva Persona' }]]);
    expect(calls.complete).toEqual([['inv-1', 'user-1']]);
    expect(calls.deleted).toEqual([]);
  });

  it('la redirección es la configurada, nunca una que venga en la petición', async () => {
    const { d, calls } = deps();
    await handle(post({ email: 'a@b.co', full_name: 'A', redirect_to: 'https://malo.example' }), d);
    expect(calls.invite[0]).toEqual(['a@b.co', REDIRECT, { full_name: 'A' }]);
  });

  it('ni la organización ni el rol salen de la petición: solo correo y nombre llegan a la base', async () => {
    const { d, calls } = deps();
    await handle(post({ email: 'a@b.co', full_name: 'A', organization_id: 'otra', role: 'director' }), d);
    expect(calls.rpcAsCaller).toEqual([['fn_prepare_invitation', { p_email: 'a@b.co', p_full_name: 'A' }]]);
  });

  it('si la base rechaza (sin permiso), no se invita ni se usa la llave', async () => {
    const { d, calls } = deps({ prepare: { data: null, error: { code: 'BV346', message: 'Acceso denegado' } } });
    const r = await handle(post({ email: 'a@b.co', full_name: 'A' }), d);
    expect(r.status).toBe(403);
    expect(await json(r)).toEqual({ ok: false, code: 'BV346' });
    expect(calls.invite).toEqual([]);
    expect(calls.complete).toEqual([]);
  });

  it.each([
    ['BV354', 422], ['BV355', 422], ['BV356', 409], ['BV357', 429],
  ])('traduce %s a un estado HTTP y conserva el código', async (code, status) => {
    const { d } = deps({ prepare: { data: null, error: { code, message: 'x' } } });
    const r = await handle(post({ email: 'a@b.co', full_name: 'A' }), d);
    expect(r.status).toBe(status);
    expect(await json(r)).toEqual({ ok: false, code });
  });

  it('un error desconocido de la base no se filtra: código genérico', async () => {
    const { d } = deps({ prepare: { data: null, error: { code: '42P01', message: 'relation "user_invitation" does not exist' } } });
    const r = await handle(post({ email: 'a@b.co', full_name: 'A' }), d);
    expect(r.status).toBe(500);
    expect(await json(r)).toEqual({ ok: false, code: 'INVITE_FAILED' });
  });

  it('si el correo no se pudo enviar, responde con su código y no completa', async () => {
    const { d, calls } = deps({ invite: { userId: null, error: 'rate limit' } });
    const r = await handle(post({ email: 'a@b.co', full_name: 'A' }), d);
    expect(r.status).toBe(502);
    expect(await json(r)).toEqual({ ok: false, code: 'INVITE_SEND_FAILED' });
    expect(calls.complete).toEqual([]);
    expect(calls.deleted).toEqual([]);
  });

  it('si completar falla en una invitación nueva, borra la cuenta recién creada', async () => {
    const { d, calls } = deps({ complete: { error: { code: 'BV358' } } });
    const r = await handle(post({ email: 'a@b.co', full_name: 'A' }), d);
    expect(r.status).toBe(500);
    expect(await json(r)).toEqual({ ok: false, code: 'INVITE_FAILED' });
    expect(calls.deleted).toEqual(['user-1']);
  });

  it('en un reenvío no borra la cuenta aunque algo falle', async () => {
    const { d, calls } = deps({
      prepare: { data: { invitation_id: 'inv-2', resend: true, user_id: 'user-9' }, error: null },
      complete: { error: { code: 'BV358' } },
    });
    const r = await handle(post({ email: 'a@b.co', full_name: 'A' }), d);
    expect(r.status).toBe(500);
    expect(calls.deleted).toEqual([]);
  });

  it('un reenvío responde resend: true', async () => {
    const { d } = deps({ prepare: { data: { invitation_id: 'inv-2', resend: true, user_id: 'user-9' }, error: null }, invite: { userId: 'user-9', error: null } });
    const r = await handle(post({ email: 'a@b.co', full_name: 'A' }), d);
    expect(await json(r)).toEqual({ ok: true, resend: true });
  });

  it('exige la sesión: sin Authorization responde 401 y no toca nada', async () => {
    const { d, calls } = deps();
    const req = new Request('https://x/f', { method: 'POST', headers: { origin: ORIGIN, 'content-type': 'application/json' }, body: JSON.stringify({ email: 'a@b.co', full_name: 'A' }) });
    const r = await handle(req, d);
    expect(r.status).toBe(401);
    expect(calls.rpcAsCaller).toEqual([]);
  });

  it('solo acepta POST', async () => {
    const { d } = deps();
    const r = await handle(new Request('https://x/f', { method: 'GET', headers: { origin: ORIGIN, authorization: 'Bearer x' } }), d);
    expect(r.status).toBe(405);
  });

  it('un cuerpo que no es JSON o no trae texto responde 400', async () => {
    const { d, calls } = deps();
    const bad = new Request('https://x/f', { method: 'POST', headers: { origin: ORIGIN, authorization: 'Bearer x' }, body: 'no es json' });
    expect((await handle(bad, d)).status).toBe(400);
    expect((await handle(post({ email: 42, full_name: 'A' }), d)).status).toBe(400);
    expect((await handle(post({ email: 'a@b.co' }), d)).status).toBe(400);
    expect(calls.rpcAsCaller).toEqual([]);
  });

  it('un cuerpo enorme se rechaza antes de procesarlo', async () => {
    const { d, calls } = deps();
    const r = await handle(post({ email: 'a@b.co', full_name: 'x'.repeat(5000) }), d);
    expect(r.status).toBe(413);
    expect(calls.rpcAsCaller).toEqual([]);
  });

  describe('orígenes (CORS)', () => {
    it('responde al origen permitido y a ningún otro', async () => {
      const { d } = deps();
      const ok = await handle(post({ email: 'a@b.co', full_name: 'A' }), d);
      expect(ok.headers.get('access-control-allow-origin')).toBe(ORIGIN);
      const otro = await handle(post({ email: 'a@b.co', full_name: 'A' }, { origin: 'https://malo.example' }), d);
      expect(otro.status).toBe(403);
      expect(otro.headers.get('access-control-allow-origin')).toBeNull();
    });

    it('el preflight del origen permitido responde 204 con los métodos y cabeceras', async () => {
      const { d, calls } = deps();
      const r = await handle(new Request('https://x/f', { method: 'OPTIONS', headers: { origin: ORIGIN, 'access-control-request-method': 'POST' } }), d);
      expect(r.status).toBe(204);
      expect(r.headers.get('access-control-allow-origin')).toBe(ORIGIN);
      expect(r.headers.get('access-control-allow-methods')).toContain('POST');
      expect(r.headers.get('access-control-allow-headers')?.toLowerCase()).toContain('authorization');
      expect(calls.rpcAsCaller).toEqual([]);
    });

    it('el preflight de otro origen se rechaza', async () => {
      const { d } = deps();
      const r = await handle(new Request('https://x/f', { method: 'OPTIONS', headers: { origin: 'https://malo.example' } }), d);
      expect(r.status).toBe(403);
    });
  });

  it('el registro no guarda el correo ni el nombre (ni al invitar ni al rechazar)', async () => {
    const ok = deps();
    await handle(post({ email: 'secreta@tst.invalid', full_name: 'Persona Secreta' }), ok.d);
    const no = deps({ prepare: { data: null, error: { code: 'BV356', message: 'secreta@tst.invalid' } } });
    await handle(post({ email: 'secreta@tst.invalid', full_name: 'Persona Secreta' }), no.d);
    const todo = [...ok.calls.logs, ...no.calls.logs].join(' | ');
    expect(todo.length).toBeGreaterThan(0);
    expect(todo).not.toContain('secreta');
    expect(todo).not.toContain('Persona Secreta');
  });
});
