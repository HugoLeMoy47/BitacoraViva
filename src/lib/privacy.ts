import { Consent } from '../types/database';

// El consentimiento es un registro por evento: el vigente de cada tipo es el ÚLTIMO (puede haberse revocado
// después de concederse). Es la misma regla que aplica la base (`fn_person_has_sensitive_consent`); la
// interfaz solo la usa para explicar por qué un dato sensible no se puede registrar todavía.
export function hasCurrentSensitiveConsent(consents: Consent[] | undefined): boolean {
  const sensitive = (consents ?? []).filter((c) => c.consent_type === 'sensitive_data');
  if (sensitive.length === 0) return false;
  const last = sensitive.reduce((a, b) => (new Date(b.granted_at).getTime() >= new Date(a.granted_at).getTime() ? b : a));
  return last.status === 'granted';
}
