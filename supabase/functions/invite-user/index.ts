// invite-user · ADR-0010. Cableado real de la función de borde: aquí (y solo aquí) se usa la llave de servicio.
// La llave la inyecta Supabase como secreto del proyecto (SUPABASE_SERVICE_ROLE_KEY); no está en el repositorio.
// La lógica y sus pruebas están en handler.ts.
import { createClient } from 'npm:@supabase/supabase-js@2.116.0';
import { handle, type Deps } from './handler.ts';

function need(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Falta el secreto ${name}`);
  return value;
}

const url = need('SUPABASE_URL');
const anonKey = need('SUPABASE_ANON_KEY');
const serviceKey = need('SUPABASE_SERVICE_ROLE_KEY');

const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

const deps: Deps = {
  allowedOrigins: need('ALLOWED_ORIGINS').split(',').map((o) => o.trim()).filter(Boolean),
  redirectTo: need('INVITE_REDIRECT_URL'),
  asCaller: (authorization) =>
    createClient(url, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    }) as unknown as ReturnType<Deps['asCaller']>,
  admin: {
    invite: async (email, redirectTo, data) => {
      const { data: res, error } = await admin.auth.admin.inviteUserByEmail(email, { redirectTo, data });
      return { userId: res?.user?.id ?? null, error: error?.message ?? null };
    },
    deleteUser: async (id) => {
      await admin.auth.admin.deleteUser(id);
    },
    completeInvitation: async (invitationId, userId) => {
      const { error } = await admin.rpc('fn_complete_invitation', { p_invitation_id: invitationId, p_user_id: userId });
      return { error: error ? { code: error.code } : null };
    },
  },
  // Sin datos personales: el manejador solo pasa identificadores de la invitación
  log: (msg, fields) => console.log(JSON.stringify({ msg, ...fields })),
};

Deno.serve((req) => handle(req, deps));
