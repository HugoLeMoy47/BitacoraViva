import { describe, expect, it } from 'vitest';
import { hasCurrentSensitiveConsent } from './privacy';
import { Consent } from '../types/database';

const consent = (consent_type: Consent['consent_type'], status: Consent['status'], granted_at: string): Consent => ({
  id: `${consent_type}-${granted_at}`,
  organization_id: 'o',
  person_id: 'p',
  consent_type,
  status,
  is_minor_assent: false,
  granted_at,
  granted_by_user_id: 'u',
  created_at: granted_at,
});

describe('consentimiento sensible vigente', () => {
  it('sin consentimientos no hay consentimiento sensible', () => {
    expect(hasCurrentSensitiveConsent(undefined)).toBe(false);
    expect(hasCurrentSensitiveConsent([])).toBe(false);
  });

  it('el consentimiento general no cuenta como sensible', () => {
    expect(hasCurrentSensitiveConsent([consent('general_care', 'granted', '2026-10-01T10:00:00Z')])).toBe(false);
  });

  it('el sensible concedido está vigente', () => {
    expect(hasCurrentSensitiveConsent([consent('sensitive_data', 'granted', '2026-10-01T10:00:00Z')])).toBe(true);
  });

  it('si se concedió y luego se retiró, ya no está vigente (gana el último)', () => {
    expect(
      hasCurrentSensitiveConsent([
        consent('sensitive_data', 'revoked', '2026-10-03T10:00:00Z'),
        consent('sensitive_data', 'granted', '2026-10-01T10:00:00Z'),
      ])
    ).toBe(false);
  });

  it('si se retiró y luego se volvió a conceder, está vigente', () => {
    expect(
      hasCurrentSensitiveConsent([
        consent('sensitive_data', 'granted', '2026-10-05T10:00:00Z'),
        consent('sensitive_data', 'revoked', '2026-10-03T10:00:00Z'),
        consent('sensitive_data', 'granted', '2026-10-01T10:00:00Z'),
      ])
    ).toBe(true);
  });
});
