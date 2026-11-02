import { describe, expect, it, vi } from 'vitest';
import {
  PHOTO_MAX_SIDE, PHOTO_MIME, PHOTO_QUALITY, WATERMARK_ANGLE, WATERMARK_OPACITY, WATERMARK_TEXT,
  centeredSquareCrop, processDossierPhoto, targetSize, watermarkRows, type PhotoCanvas, type PhotoDeps,
} from './photo-processor';

// Lo que estas pruebas NO pueden comprobar sin un navegador real: que el archivo resultante no traiga metadatos EXIF (se apoya en que
// un lienzo nuevo no los hereda) ni que la trama estorbe de verdad a un clasificador facial (eso no está verificado).

describe('privacidad visual de la fotografía: constantes del contrato', () => {
  it('300×300 máximo, WebP al 70 %, marca diagonal a -30° y 30 % de opacidad con el texto acordado', () => {
    expect(PHOTO_MAX_SIDE).toBe(300);
    expect(PHOTO_MIME).toBe('image/webp');
    expect(PHOTO_QUALITY).toBe(0.7);
    expect(WATERMARK_ANGLE).toBeCloseTo((-30 * Math.PI) / 180);
    expect(WATERMARK_OPACITY).toBe(0.3);
    expect(WATERMARK_TEXT).toBe('USO EXCLUSIVO ALBERGUE — PROHIBIDO USO BIOMÉTRICO O ALGORÍTMICO');
  });
});

describe('recorte y tamaño', () => {
  it('recorta un cuadrado centrado (sin detección de rostros: eso sería procesamiento biométrico, prohibido por el Ethos)', () => {
    expect(centeredSquareCrop(4000, 3000)).toEqual({ sx: 500, sy: 0, side: 3000 });
    expect(centeredSquareCrop(3000, 4000)).toEqual({ sx: 0, sy: 500, side: 3000 });
    expect(centeredSquareCrop(500, 500)).toEqual({ sx: 0, sy: 0, side: 500 });
  });
  it('nunca pasa de 300 px por lado y no agranda una imagen pequeña', () => {
    expect(targetSize(3000)).toBe(300);
    expect(targetSize(300)).toBe(300);
    expect(targetSize(120)).toBe(120);
  });
  it('rechaza una imagen sin dimensiones', () => {
    expect(() => centeredSquareCrop(0, 100)).toThrow();
    expect(() => targetSize(0)).toThrow();
  });
});

describe('trama de la marca de agua', () => {
  it('cubre el lienzo de lado a lado, con varias filas del texto', () => {
    // filas en el marco ya rotado y centrado en el lienzo: deben llegar más allá de las esquinas (±size/2) para que la franja cruce de lado a lado
    const rows = watermarkRows(300);
    expect(rows.length).toBeGreaterThanOrEqual(3);
    expect(Math.min(...rows)).toBeLessThanOrEqual(-150);
    expect(Math.max(...rows)).toBeGreaterThanOrEqual(150);
  });
});

// Un lienzo falso que registra lo que se le hace: comprueba el contrato sin navegador
function fakeCanvas() {
  const calls: { op: string; args?: unknown[] }[] = [];
  const size = [0, 0];
  const ctx = {
    set globalAlpha(v: number) { calls.push({ op: 'globalAlpha', args: [v] }); },
    set fillStyle(v: string) { calls.push({ op: 'fillStyle', args: [v] }); },
    set strokeStyle(v: string) { calls.push({ op: 'strokeStyle', args: [v] }); },
    set lineWidth(v: number) { calls.push({ op: 'lineWidth', args: [v] }); },
    set font(v: string) { calls.push({ op: 'font', args: [v] }); },
    set textBaseline(v: string) { calls.push({ op: 'textBaseline', args: [v] }); },
    drawImage: (...a: unknown[]) => calls.push({ op: 'drawImage', args: a }),
    save: () => calls.push({ op: 'save' }),
    restore: () => calls.push({ op: 'restore' }),
    translate: (...a: unknown[]) => calls.push({ op: 'translate', args: a }),
    rotate: (...a: unknown[]) => calls.push({ op: 'rotate', args: a }),
    fillText: (...a: unknown[]) => calls.push({ op: 'fillText', args: a }),
    strokeText: (...a: unknown[]) => calls.push({ op: 'strokeText', args: a }),
    measureText: () => ({ width: 120 }),
  };
  const canvas: PhotoCanvas = {
    set width(v: number) { size[0] = v; },
    get width() { return size[0]; },
    set height(v: number) { size[1] = v; },
    get height() { return size[1]; },
    getContext: () => ctx as unknown as ReturnType<PhotoCanvas['getContext']>,
    toBlob: vi.fn((cb: (b: Blob | null) => void, type?: string, quality?: number) => {
      calls.push({ op: 'toBlob', args: [type, quality] });
      cb(new Blob(['webp'], { type }));
    }),
  };
  return { canvas, calls };
}

describe('el procesamiento de la imagen (pipeline del contrato)', () => {
  const run = async (w: number, h: number) => {
    const f = fakeCanvas();
    const close = vi.fn();
    const deps: PhotoDeps = { decode: async () => ({ width: w, height: h, close }), createCanvas: () => f.canvas };
    const out = await processDossierPhoto(new Blob(['x'], { type: 'image/jpeg' }), deps);
    return { ...f, out, close };
  };

  it('una foto de 4000×3000 sale de 300×300 como WebP al 70 %', async () => {
    const r = await run(4000, 3000);
    expect(r.canvas.width).toBe(300);
    expect(r.canvas.height).toBe(300);
    expect(r.out.type).toBe('image/webp');
    expect(r.calls.find((c) => c.op === 'toBlob')?.args).toEqual(['image/webp', 0.7]);
  });

  it('se dibuja recortada al centro, de una sola vez en el lienzo nuevo (así no pasan los metadatos EXIF)', async () => {
    const r = await run(4000, 3000);
    const draws = r.calls.filter((c) => c.op === 'drawImage');
    expect(draws).toHaveLength(1);
    expect(draws[0].args?.slice(1)).toEqual([500, 0, 3000, 3000, 0, 0, 300, 300]);
  });

  it('estampa la marca diagonal a -30°, al 30 % de opacidad, con el texto del contrato', async () => {
    const r = await run(4000, 3000);
    expect(r.calls.some((c) => c.op === 'rotate' && Math.abs((c.args?.[0] as number) - WATERMARK_ANGLE) < 1e-9)).toBe(true);
    expect(r.calls.some((c) => c.op === 'globalAlpha' && c.args?.[0] === 0.3)).toBe(true);
    const texts = r.calls.filter((c) => c.op === 'fillText');
    expect(texts.length).toBeGreaterThanOrEqual(3);
    for (const t of texts) expect(t.args?.[0]).toBe(WATERMARK_TEXT);
    expect(r.calls.some((c) => c.op === 'strokeText')).toBe(true);
  });

  it('la marca se dibuja DESPUÉS de la imagen (encima de ella)', async () => {
    const r = await run(1000, 1000);
    const iDraw = r.calls.findIndex((c) => c.op === 'drawImage');
    const iText = r.calls.findIndex((c) => c.op === 'fillText');
    expect(iDraw).toBeGreaterThanOrEqual(0);
    expect(iText).toBeGreaterThan(iDraw);
  });

  it('una imagen pequeña no se agranda', async () => {
    const r = await run(120, 90);
    expect(r.canvas.width).toBe(90);
    expect(r.canvas.height).toBe(90);
  });

  it('libera la imagen decodificada', async () => {
    const r = await run(800, 600);
    expect(r.close).toHaveBeenCalled();
  });

  it('si el navegador no puede codificar WebP, falla (no sube un formato que no es el pedido)', async () => {
    const f = fakeCanvas();
    (f.canvas.toBlob as ReturnType<typeof vi.fn>).mockImplementation((cb: (b: Blob | null) => void) => cb(new Blob(['x'], { type: 'image/png' })));
    const deps: PhotoDeps = { decode: async () => ({ width: 500, height: 500, close: () => {} }), createCanvas: () => f.canvas };
    await expect(processDossierPhoto(new Blob(['x']), deps)).rejects.toThrow();
  });

  it('si no se puede leer la imagen, falla sin dejar nada a medias', async () => {
    const deps: PhotoDeps = { decode: async () => { throw new Error('corrupta'); }, createCanvas: () => fakeCanvas().canvas };
    await expect(processDossierPhoto(new Blob(['x']), deps)).rejects.toThrow('corrupta');
  });
});
