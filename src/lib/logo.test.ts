import { describe, expect, it } from 'vitest';
import { LOGO_MAX_BYTES, logoExtension, logoStoragePath, validateLogoFile } from './logo';

const f = (type: string, size: number, name = 'logo') => ({ type, size, name });

describe('logotipo: qué archivos se aceptan', () => {
  it('acepta PNG, JPG y WebP de hasta 1 MB', () => {
    expect(validateLogoFile(f('image/png', 1000))).toBeNull();
    expect(validateLogoFile(f('image/jpeg', 1000))).toBeNull();
    expect(validateLogoFile(f('image/webp', LOGO_MAX_BYTES))).toBeNull();
  });
  it('rechaza SVG (puede llevar código), GIF y cualquier otro tipo', () => {
    expect(validateLogoFile(f('image/svg+xml', 1000))).toBe('type');
    expect(validateLogoFile(f('image/gif', 1000))).toBe('type');
    expect(validateLogoFile(f('application/pdf', 1000))).toBe('type');
    expect(validateLogoFile(f('', 1000))).toBe('type');
  });
  it('rechaza lo que pasa de 1 MB', () => {
    expect(validateLogoFile(f('image/png', LOGO_MAX_BYTES + 1))).toBe('size');
  });
  it('rechaza un archivo vacío', () => {
    expect(validateLogoFile(f('image/png', 0))).toBe('empty');
  });
  it('el tipo se revisa antes que el tamaño', () => {
    expect(validateLogoFile(f('image/svg+xml', LOGO_MAX_BYTES + 1))).toBe('type');
  });
});

describe('logotipo: ruta de almacenamiento', () => {
  it('la extensión sale del tipo, no del nombre que trae el archivo', () => {
    expect(logoExtension('image/png')).toBe('png');
    expect(logoExtension('image/jpeg')).toBe('jpg');
    expect(logoExtension('image/webp')).toBe('webp');
  });
  it('la ruta lleva la organización y un identificador al azar, con el formato que exige la base', () => {
    const path = logoStoragePath('aaaaaaaa-0000-0000-0000-00000000000a', '11111111-1111-4111-8111-111111111111', 'image/png');
    expect(path).toBe('aaaaaaaa-0000-0000-0000-00000000000a/logo-11111111-1111-4111-8111-111111111111.png');
    expect(path).toMatch(/^[0-9a-f-]{36}\/logo-[0-9a-f-]{36}\.(png|jpg|webp)$/);
  });
});
