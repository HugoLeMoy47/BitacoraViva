import { supabase } from './supabase';
import { DbError } from './errors';

// Invitar personas (E16 fase C, ADR-0010): la regla vive en la base; la función de borde `invite-user` solo invita por correo.
// Aquí se llama a esa función con la sesión de quien invita y se traducen sus errores a códigos que la interfaz entiende.
export interface InviteResult {
  /** Verdadero si era un reenvío a una cuenta que aún no aceptó la invitación */
  resend: boolean;
}

// Códigos que la función devuelve tal cual: los de la base (BVnnn) y los propios de la función.
const KNOWN_CODE = /^(BV\d{3}|INVITE_FAILED|INVITE_SEND_FAILED|ORIGIN_NOT_ALLOWED|NO_SESSION)$/;

export function inviteErrorFromBody(body: unknown, fallbackMessage: string): DbError {
  const code = (body as { code?: unknown } | null)?.code;
  if (typeof code === 'string' && KNOWN_CODE.test(code)) return new DbError(code, code);
  return new DbError(fallbackMessage);
}

export async function invitePerson(email: string, fullName: string): Promise<InviteResult> {
  const { data, error } = await supabase.functions.invoke('invite-user', { body: { email, full_name: fullName } });
  if (error) {
    let body: unknown = null;
    const response = (error as { context?: Response }).context;
    try {
      body = response ? await response.json() : null;
    } catch {
      body = null;
    }
    throw inviteErrorFromBody(body, error.message);
  }
  if (!data?.ok) throw inviteErrorFromBody(data, 'invite-user');
  return { resend: data.resend === true };
}
