// Reglas de la evidencia fotográfica (BV-7.14), en un solo lugar y sin tocar la red.
//
// La base y el bucket imponen lo mismo (JPEG/PNG/WebP, 5 MB, ruta {organización}/{tarea}/{archivo}); aquí
// se replica para no mandar un archivo que se va a rechazar. La que manda es la base.

export const EVIDENCE_MIME_TYPES = ['image/jpeg', 'image/png', 'image/webp'] as const;
export const EVIDENCE_MAX_BYTES = 5 * 1024 * 1024;
/** Lado mayor tras reducir: una foto de celular (4000 px, 6 MB) pesa ~300 KB a 1600 px y se sigue leyendo */
export const EVIDENCE_MAX_SIDE = 1600;
export const EVIDENCE_SIGNED_URL_SECONDS = 60;

export type EvidenceProblem = 'type' | 'size' | 'empty';

const EXTENSION: Record<string, string> = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };

export function isEvidenceMime(mime: string): boolean {
  return (EVIDENCE_MIME_TYPES as readonly string[]).includes(mime);
}

/** Null si el archivo es aceptable; si no, el motivo (clave para el mensaje). */
export function evidenceProblem(file: { type: string; size: number }): EvidenceProblem | null {
  if (!isEvidenceMime(file.type)) return 'type';
  if (file.size <= 0) return 'empty';
  if (file.size > EVIDENCE_MAX_BYTES) return 'size';
  return null;
}

/** Tamaño tras reducir, conservando la proporción. Nunca agranda. */
export function scaledSize(width: number, height: number, maxSide: number = EVIDENCE_MAX_SIDE): { width: number; height: number } {
  const longest = Math.max(width, height);
  if (longest <= maxSide) return { width, height };
  const k = maxSide / longest;
  return { width: Math.max(1, Math.round(width * k)), height: Math.max(1, Math.round(height * k)) };
}

/** Ruta en el bucket. El nombre es aleatorio: nunca se usa el del archivo (puede traer datos de la persona). */
export function evidencePath(organizationId: string, taskId: string, mime: string, fileId: string): string {
  return `${organizationId}/${taskId}/${fileId}.${EXTENSION[mime] ?? 'jpg'}`;
}

/**
 * Prepara la foto para subirla: la reduce y la recodifica en JPEG (esto también elimina los metadatos EXIF,
 * entre ellos la ubicación GPS). Si el navegador no puede decodificarla, devuelve el original y deja que la
 * validación decida.
 */
export async function prepareEvidence(file: File): Promise<File> {
  if (!isEvidenceMime(file.type)) return file;
  try {
    const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' });
    const { width, height } = scaledSize(bitmap.width, bitmap.height);
    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext('2d');
    if (!ctx) return file;
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, width, height);
    ctx.drawImage(bitmap, 0, 0, width, height);
    bitmap.close();
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/jpeg', 0.82));
    if (!blob) return file;
    return new File([blob], 'evidencia.jpg', { type: 'image/jpeg' });
  } catch {
    return file;
  }
}
