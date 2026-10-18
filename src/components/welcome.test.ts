import { describe, expect, it } from 'vitest';
import { isWelcomeUrl } from './WelcomePage';

describe('enlace de bienvenida', () => {
  it('se reconoce solo con el parámetro de la invitación', () => {
    expect(isWelcomeUrl('?bienvenida=1')).toBe(true);
    expect(isWelcomeUrl('?bienvenida')).toBe(true);
    expect(isWelcomeUrl('')).toBe(false);
    expect(isWelcomeUrl('?otra=1')).toBe(false);
    expect(isWelcomeUrl('?x=1&bienvenida=1')).toBe(true);
  });
});
