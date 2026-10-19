import { supabase } from './supabase';

// E17 fase 4 · Logotipo de la organización. La regla vive en la base (bucket `org-assets` con tipo y tamaño limitados, política de
// subida y `fn_set_organization_logo`); aquí se valida antes de subir para dar un aviso claro y se arma la ruta que la base exige.
export const LOGO_BUCKET = 'org-assets';
export const LOGO_MAX_BYTES = 1024 * 1024;
/** SVG queda fuera a propósito: puede llevar código. */
export const LOGO_TYPES = ['image/png', 'image/jpeg', 'image/webp'] as const;

export type LogoProblem = 'type' | 'size' | 'empty';

export function validateLogoFile(file: { type: string; size: number }): LogoProblem | null {
  if (!(LOGO_TYPES as readonly string[]).includes(file.type)) return 'type';
  if (file.size <= 0) return 'empty';
  if (file.size > LOGO_MAX_BYTES) return 'size';
  return null;
}

export function logoExtension(mime: string): 'png' | 'jpg' | 'webp' {
  return mime === 'image/jpeg' ? 'jpg' : mime === 'image/webp' ? 'webp' : 'png';
}

/** `<organización>/logo-<id al azar>.<ext>`: cada logotipo es un archivo nuevo y el anterior se conserva. */
export const logoStoragePath = (organizationId: string, id: string, mime: string): string =>
  `${organizationId}/logo-${id}.${logoExtension(mime)}`;

/** Dirección pública del logotipo vigente (el bucket es público: no es un dato sensible). */
export const logoPublicUrl = (path: string | null | undefined): string | null =>
  path ? supabase.storage.from(LOGO_BUCKET).getPublicUrl(path).data.publicUrl : null;

/** Sube el archivo a la carpeta de la organización y devuelve su ruta (falla si la base lo rechaza). */
export async function uploadLogoFile(organizationId: string, file: File): Promise<string> {
  const path = logoStoragePath(organizationId, crypto.randomUUID(), file.type);
  const { error } = await supabase.storage.from(LOGO_BUCKET).upload(path, file, { contentType: file.type, upsert: false });
  if (error) throw error;
  return path;
}
