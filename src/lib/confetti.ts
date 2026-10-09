// Ráfaga ligera de confeti para celebrar una tarea cerrada.
//  · Sin dependencias: usa un canvas nativo.
//  · Respeta `prefers-reduced-motion`: si la persona pidió menos movimiento, no hace nada.
//  · Se limpia sola: el canvas sale del DOM al terminar (1.5 s) y si la pestaña pasa a segundo plano.

const COLORS = ['#01CFCB', '#007a77', '#D9644A', '#f59e0b', '#8b5cf6', '#3b82f6'];
const DURATION_MS = 1500;
const PARTICLES = 45;

export function launchConfetti(): void {
  if (typeof window === 'undefined' || typeof document === 'undefined') return;
  if (window.matchMedia?.('(prefers-reduced-motion: reduce)')?.matches) return;

  const canvas = document.createElement('canvas');
  canvas.setAttribute('aria-hidden', 'true');
  Object.assign(canvas.style, {
    position: 'fixed',
    top: '0',
    left: '0',
    width: '100vw',
    height: '100vh',
    pointerEvents: 'none',
    zIndex: '9999',
  });
  document.body.appendChild(canvas);

  const ctx = canvas.getContext('2d');
  if (!ctx) {
    canvas.remove();
    return;
  }

  const width = (canvas.width = window.innerWidth);
  const height = (canvas.height = window.innerHeight);

  const particles = Array.from({ length: PARTICLES }, () => ({
    x: width * 0.5 + (Math.random() - 0.5) * width * 0.4,
    y: height * 0.35 + (Math.random() - 0.5) * 50,
    vx: (Math.random() - 0.5) * 8,
    vy: -Math.random() * 6 - 2,
    size: Math.random() * 6 + 4,
    color: COLORS[Math.floor(Math.random() * COLORS.length)],
    rotation: Math.random() * 360,
    spin: (Math.random() - 0.5) * 10,
  }));

  const start = performance.now();
  let frame = 0;

  const draw = (now: number) => {
    const elapsed = now - start;
    if (elapsed > DURATION_MS) {
      canvas.remove();
      return;
    }
    ctx.clearRect(0, 0, width, height);
    const fade = Math.max(0, 1 - elapsed / DURATION_MS);
    for (const p of particles) {
      p.x += p.vx;
      p.y += p.vy;
      p.vy += 0.25;
      p.rotation += p.spin;
      ctx.save();
      ctx.translate(p.x, p.y);
      ctx.rotate((p.rotation * Math.PI) / 180);
      ctx.globalAlpha = fade;
      ctx.fillStyle = p.color;
      ctx.fillRect(-p.size / 2, -p.size / 2, p.size, p.size * 0.6);
      ctx.restore();
    }
    frame = requestAnimationFrame(draw);
  };
  frame = requestAnimationFrame(draw);

  window.setTimeout(() => {
    cancelAnimationFrame(frame);
    canvas.remove();
  }, DURATION_MS + 200);
}
