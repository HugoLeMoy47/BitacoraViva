import React, { useEffect, useRef } from 'react';

// Cascarón accesible de todos los modales:
//  · role="dialog" + aria-modal, nombrado por su primer encabezado
//  · se cierra con Escape
//  · el foco entra al abrir, queda atrapado dentro y se devuelve al cerrar
//  · el fondo no se desplaza mientras está abierto
// No cierra al hacer clic fuera: una captura a medias no debe perderse por un toque accidental.

const FOCUSABLE =
  'a[href], button:not([disabled]), input:not([disabled]):not([type="hidden"]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

let counter = 0;

interface ModalShellProps {
  onClose: () => void;
  className?: string;
  children: React.ReactNode;
}

export const ModalShell: React.FC<ModalShellProps> = ({ onClose, className = '', children }) => {
  const ref = useRef<HTMLDivElement>(null);
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;

  useEffect(() => {
    const root = ref.current;
    if (!root) return;
    const previouslyFocused = document.activeElement as HTMLElement | null;

    // Nombre accesible: el primer encabezado del modal
    const heading = root.querySelector<HTMLElement>('h1, h2, h3');
    if (heading) {
      if (!heading.id) heading.id = `modal-title-${++counter}`;
      root.setAttribute('aria-labelledby', heading.id);
    }

    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';

    const focusables = () => Array.from(root.querySelectorAll<HTMLElement>(FOCUSABLE)).filter((el) => el.offsetParent !== null);
    // Foco inicial: primer campo de captura si existe; si no, el primer control
    const first = root.querySelector<HTMLElement>('input:not([type="hidden"]):not([type="radio"]):not([type="checkbox"]), textarea, select') || focusables()[0];
    (first || root).focus({ preventScroll: true });

    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation();
        onCloseRef.current();
        return;
      }
      if (e.key !== 'Tab') return;
      const items = focusables();
      if (items.length === 0) {
        e.preventDefault();
        return;
      }
      const firstEl = items[0];
      const lastEl = items[items.length - 1];
      if (e.shiftKey && document.activeElement === firstEl) {
        e.preventDefault();
        lastEl.focus();
      } else if (!e.shiftKey && document.activeElement === lastEl) {
        e.preventDefault();
        firstEl.focus();
      }
    };
    document.addEventListener('keydown', onKeyDown, true);

    return () => {
      document.removeEventListener('keydown', onKeyDown, true);
      document.body.style.overflow = prevOverflow;
      previouslyFocused?.focus?.({ preventScroll: true });
    };
  }, []);

  return (
    <div ref={ref} role="dialog" aria-modal="true" tabIndex={-1} className={`${className} modal-scroll outline-none`}>
      {children}
    </div>
  );
};
