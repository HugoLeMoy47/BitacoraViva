// Privacidad visual de la fotografía de identificación (Ethos E-01, enmienda v1.4; contrato del ciclo «Ingreso y expediente» §4).
//
// La fotografía sirve para que una persona reconozca a otra (filiación y credencial en el albergue), NO para que una máquina lo
// haga. Antes de subir, el cliente: (1) la redibuja en un lienzo nuevo —así no pasan los metadatos EXIF, el GPS ni la cabecera de
// la cámara—, (2) la recorta al centro y la reduce a 300×300 como máximo, (3) estampa una franja diagonal a -30° con el aviso de uso
// al 30 % de opacidad y (4) la comprime a WebP al 70 %.
//
// Lo que este módulo NO hace, a propósito: detectar el rostro para centrar el recorte (eso sería procesamiento biométrico, que el
// Ethos prohíbe); se recorta al centro de la imagen. Y lo que NO está verificado: que la trama estorbe de verdad a un clasificador
// facial (es una mitigación, no una garantía) ni, en las pruebas unitarias, que el archivo final esté libre de EXIF (se apoya en
// que un lienzo nuevo no hereda metadatos; se debe comprobar a mano con una foto real).

export const PHOTO_MAX_SIDE = 300;
export const PHOTO_MIME = 'image/webp';
export const PHOTO_QUALITY = 0.7;
export const WATERMARK_ANGLE = (-30 * Math.PI) / 180;
export const WATERMARK_OPACITY = 0.3;
export const WATERMARK_TEXT = 'USO EXCLUSIVO ALBERGUE — PROHIBIDO USO BIOMÉTRICO O ALGORÍTMICO';

export interface PhotoContext {
  globalAlpha: number;
  fillStyle: string;
  strokeStyle: string;
  lineWidth: number;
  font: string;
  textBaseline: string;
  drawImage(image: unknown, sx: number, sy: number, sw: number, sh: number, dx: number, dy: number, dw: number, dh: number): void;
  save(): void;
  restore(): void;
  translate(x: number, y: number): void;
  rotate(angle: number): void;
  fillText(text: string, x: number, y: number): void;
  strokeText(text: string, x: number, y: number): void;
  measureText(text: string): { width: number };
}

export interface PhotoCanvas {
  width: number;
  height: number;
  getContext(type: '2d'): PhotoContext | null;
  toBlob(callback: (blob: Blob | null) => void, type?: string, quality?: number): void;
}

export interface DecodedImage {
  width: number;
  height: number;
  close?: () => void;
}

export interface PhotoDeps {
  decode: (file: Blob) => Promise<DecodedImage>;
  createCanvas: () => PhotoCanvas;
}

/** Cuadrado centrado de la imagen (sin buscar rostros). */
export function centeredSquareCrop(width: number, height: number): { sx: number; sy: number; side: number } {
  if (!(width > 0) || !(height > 0)) throw new Error('La imagen no tiene dimensiones válidas.');
  const side = Math.min(width, height);
  return { sx: Math.round((width - side) / 2), sy: Math.round((height - side) / 2), side };
}

/** Lado final: nunca más de 300 px y sin agrandar una imagen pequeña. */
export function targetSize(side: number): number {
  if (!(side > 0)) throw new Error('La imagen no tiene dimensiones válidas.');
  return Math.min(side, PHOTO_MAX_SIDE);
}

/** Posición vertical de cada fila del texto, en el marco rotado y centrado: llega más allá de las esquinas para cruzar de lado a lado. */
export function watermarkRows(size: number): number[] {
  const step = Math.max(10, Math.round(size / 6));
  const reach = Math.ceil(size * 0.75);
  const rows: number[] = [];
  for (let y = -reach; y <= reach; y += step) rows.push(y);
  return rows;
}

function stampWatermark(ctx: PhotoContext, size: number): void {
  const fontPx = Math.max(8, Math.round(size / 22));
  ctx.save();
  ctx.translate(size / 2, size / 2);
  ctx.rotate(WATERMARK_ANGLE);
  ctx.globalAlpha = WATERMARK_OPACITY;
  ctx.font = `bold ${fontPx}px sans-serif`;
  ctx.textBaseline = 'middle';
  ctx.fillStyle = '#ffffff';
  ctx.strokeStyle = '#808080';
  ctx.lineWidth = Math.max(1, fontPx / 10);
  const width = Math.max(1, ctx.measureText(WATERMARK_TEXT).width);
  const gap = fontPx * 2;
  const reach = Math.ceil(size * 0.75);
  watermarkRows(size).forEach((y, i) => {
    // las filas se desfasan para que la trama no deje columnas vacías
    for (let x = -reach - ((i * (width + gap)) / 3) % (width + gap); x < reach; x += width + gap) {
      ctx.strokeText(WATERMARK_TEXT, x, y);
      ctx.fillText(WATERMARK_TEXT, x, y);
    }
  });
  ctx.restore();
}

const defaultDeps: PhotoDeps = {
  // `from-image` respeta la orientación que trae la cámara antes de descartar los metadatos
  decode: (file) => createImageBitmap(file, { imageOrientation: 'from-image' }),
  createCanvas: () => document.createElement('canvas') as unknown as PhotoCanvas,
};

/** Procesa la fotografía y devuelve el WebP listo para subir. Falla —sin dejar nada a medias— si no se puede leer o codificar. */
export async function processDossierPhoto(file: Blob, deps: PhotoDeps = defaultDeps): Promise<Blob> {
  const image = await deps.decode(file);
  try {
    const { sx, sy, side } = centeredSquareCrop(image.width, image.height);
    const size = targetSize(side);
    const canvas = deps.createCanvas();
    canvas.width = size;
    canvas.height = size;
    const ctx = canvas.getContext('2d');
    if (!ctx) throw new Error('El navegador no puede procesar la imagen.');
    ctx.drawImage(image, sx, sy, side, side, 0, 0, size, size);
    stampWatermark(ctx, size);
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, PHOTO_MIME, PHOTO_QUALITY));
    if (!blob || blob.type !== PHOTO_MIME) throw new Error('El navegador no pudo guardar la imagen en WebP.');
    return blob;
  } finally {
    image.close?.();
  }
}
