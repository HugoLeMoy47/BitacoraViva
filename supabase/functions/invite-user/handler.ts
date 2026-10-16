// invite-user · ADR-0010. La función es DELGADA: la regla de quién puede invitar vive en la base
// (fn_prepare_invitation, con la sesión de quien invita; fn_complete_invitation, solo para la llave de servicio).
// Aquí solo se hace lo que la base no puede: invitar por correo y deshacer si algo falla.
//
// Este archivo no importa nada de Deno ni de npm: recibe sus dependencias (`Deps`) para poder probarse con vitest.
// El cableado real, con la llave de servicio, está en index.ts.

export interface DbResult<T = unknown> {
  data: T | null;
  error: { code?: string; message: string } | null;
}

export interface Deps {
  /** Orígenes de la aplicación a los que se responde (CORS). */
  allowedOrigins: string[];
  /** Adonde lleva el enlace del correo. Fija en configuración: nunca viene de la petición. */
  redirectTo: string;
  /** Cliente con la sesión de quien invita: lo que pregunte, lo decide la base con SU identidad. */
  asCaller: (authorization: string) => { rpc: (name: string, args: Record<string, unknown>) => Promise<DbResult> };
  /** Lo único que se hace con la llave de servicio. */
  admin: {
    invite: (email: string, redirectTo: string, data: Record<string, unknown>) => Promise<{ userId: string | null; error: string | null }>;
    deleteUser: (id: string) => Promise<void>;
    completeInvitation: (invitationId: string, userId: string) => Promise<{ error: { code?: string } | null }>;
  };
  /** Registro sin datos personales: nunca el correo ni el nombre. */
  log: (msg: string, fields: Record<string, unknown>) => void;
}

const MAX_BODY = 2000;

// Código de la base → estado HTTP. El código viaja tal cual para que la interfaz lo traduzca (errors.db.bvnnn).
const STATUS_BY_CODE: Record<string, number> = { BV346: 403, BV354: 422, BV355: 422, BV356: 409, BV357: 429 };

function corsHeaders(origin: string | null, deps: Deps): Record<string, string> {
  if (!origin || !deps.allowedOrigins.includes(origin)) return {};
  return {
    'access-control-allow-origin': origin,
    'access-control-allow-methods': 'POST, OPTIONS',
    'access-control-allow-headers': 'authorization, content-type, apikey, x-client-info',
    'access-control-max-age': '600',
    vary: 'origin',
  };
}

function reply(status: number, body: unknown, cors: Record<string, string>): Response {
  return new Response(status === 204 ? null : JSON.stringify(body), {
    status,
    headers: { ...cors, ...(status === 204 ? {} : { 'content-type': 'application/json' }) },
  });
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const origin = req.headers.get('origin');
  const cors = corsHeaders(origin, deps);

  // Un navegador desde otro origen no recibe respuesta útil (ni siquiera en el preflight)
  if (origin && !cors['access-control-allow-origin']) return reply(403, { ok: false, code: 'ORIGIN_NOT_ALLOWED' }, {});
  if (req.method === 'OPTIONS') return reply(204, null, cors);
  if (req.method !== 'POST') return reply(405, { ok: false, code: 'METHOD_NOT_ALLOWED' }, cors);

  const authorization = req.headers.get('authorization');
  if (!authorization || !/^Bearer\s+\S+/i.test(authorization)) return reply(401, { ok: false, code: 'NO_SESSION' }, cors);

  const raw = await req.text();
  if (raw.length > MAX_BODY) return reply(413, { ok: false, code: 'BODY_TOO_LARGE' }, cors);
  let body: { email?: unknown; full_name?: unknown };
  try {
    body = JSON.parse(raw);
  } catch {
    return reply(400, { ok: false, code: 'BAD_REQUEST' }, cors);
  }
  if (typeof body?.email !== 'string' || typeof body?.full_name !== 'string') return reply(400, { ok: false, code: 'BAD_REQUEST' }, cors);
  // Solo correo y nombre llegan a la base: la organización sale de la sesión y el rol lo otorga la dirección después
  const email = body.email;
  const fullName = body.full_name;

  // 1. La base decide, con la identidad de quien invita
  const prepared = await deps.asCaller(authorization).rpc('fn_prepare_invitation', { p_email: email, p_full_name: fullName });
  if (prepared.error) {
    const code = prepared.error.code ?? '';
    deps.log('prepare rechazada', { code });
    const status = STATUS_BY_CODE[code];
    if (status) return reply(status, { ok: false, code }, cors);
    return reply(500, { ok: false, code: 'INVITE_FAILED' }, cors);
  }
  const prep = prepared.data as { invitation_id?: string; resend?: boolean } | null;
  if (!prep?.invitation_id) return reply(500, { ok: false, code: 'INVITE_FAILED' }, cors);
  const resend = prep.resend === true;

  // 2. Con la llave: invitar por correo (en un reenvío, GoTrue vuelve a enviar a la cuenta sin confirmar)
  const invited = await deps.admin.invite(email.trim().toLowerCase(), deps.redirectTo, { full_name: fullName.trim() });
  if (invited.error || !invited.userId) {
    deps.log('envío fallido', { invitation: prep.invitation_id, resend });
    return reply(502, { ok: false, code: 'INVITE_SEND_FAILED' }, cors);
  }

  // 3. La base crea el perfil (sin ningún rol); si falla, se deshace la cuenta recién creada (no en un reenvío)
  const done = await deps.admin.completeInvitation(prep.invitation_id, invited.userId);
  if (done.error) {
    deps.log('completar fallido', { invitation: prep.invitation_id, resend, code: done.error.code ?? null });
    if (!resend) await deps.admin.deleteUser(invited.userId);
    return reply(500, { ok: false, code: 'INVITE_FAILED' }, cors);
  }

  deps.log('invitación enviada', { invitation: prep.invitation_id, resend });
  return reply(200, { ok: true, resend }, cors);
}
