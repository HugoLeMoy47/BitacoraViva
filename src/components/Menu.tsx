import React, { useEffect, useRef, useState } from 'react';

// Menú desplegable accesible (aria-haspopup="menu"): abre con clic o teclado, flechas para
// moverse, Escape y clic fuera para cerrar, y devuelve el foco al botón.
export interface MenuItem {
  id: string;
  label: React.ReactNode;
  icon?: React.ReactNode;
  onSelect: () => void;
  current?: boolean;
  danger?: boolean;
}

interface MenuProps {
  /** Contenido visible del botón */
  trigger: React.ReactNode;
  /** Nombre accesible del botón cuando el contenido es sólo un icono */
  ariaLabel?: string;
  triggerClassName?: string;
  items: MenuItem[];
  /** Información no interactiva que encabeza el menú (p. ej. la cuenta) */
  header?: React.ReactNode;
  placement?: 'bottom-end' | 'bottom-start' | 'top-end';
}

export const Menu: React.FC<MenuProps> = ({
  trigger,
  ariaLabel,
  triggerClassName = '',
  items,
  header,
  placement = 'bottom-end',
}) => {
  const [open, setOpen] = useState(false);
  const wrapRef = useRef<HTMLDivElement>(null);
  const btnRef = useRef<HTMLButtonElement>(null);
  const listRef = useRef<HTMLDivElement>(null);

  const close = (refocus = true) => {
    setOpen(false);
    if (refocus) btnRef.current?.focus();
  };

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      if (!wrapRef.current?.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', onDown);
    // Foco inicial: el elemento actual o el primero
    const entries = listRef.current?.querySelectorAll<HTMLElement>('[role="menuitem"]');
    (listRef.current?.querySelector<HTMLElement>('[aria-current="page"]') || entries?.[0])?.focus();
    return () => document.removeEventListener('mousedown', onDown);
  }, [open]);

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (!open) {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        setOpen(true);
      }
      return;
    }
    const entries = Array.from(listRef.current?.querySelectorAll<HTMLElement>('[role="menuitem"]') ?? []);
    const idx = entries.indexOf(document.activeElement as HTMLElement);
    if (e.key === 'Escape') {
      e.preventDefault();
      e.stopPropagation();
      close();
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      entries[(idx + 1) % entries.length]?.focus();
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      entries[(idx - 1 + entries.length) % entries.length]?.focus();
    } else if (e.key === 'Home') {
      e.preventDefault();
      entries[0]?.focus();
    } else if (e.key === 'End') {
      e.preventDefault();
      entries[entries.length - 1]?.focus();
    } else if (e.key === 'Tab') {
      setOpen(false);
    }
  };

  const pos =
    placement === 'top-end'
      ? 'bottom-full mb-2 right-0'
      : placement === 'bottom-start'
        ? 'top-full mt-2 left-0'
        : 'top-full mt-2 right-0';

  return (
    <div ref={wrapRef} className="relative" onKeyDown={onKeyDown}>
      <button
        ref={btnRef}
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label={ariaLabel}
        onClick={() => setOpen((v) => !v)}
        className={triggerClassName}
      >
        {trigger}
      </button>
      {open && (
        <div
          ref={listRef}
          role="menu"
          className={`absolute z-50 min-w-60 max-w-[calc(100vw-1.5rem)] rounded-xl border border-gray-200 bg-white py-1 text-carbon shadow-xl ${pos}`}
        >
          {header && <div className="border-b border-gray-100 px-4 py-3">{header}</div>}
          {items.map((item) => (
            <button
              key={item.id}
              type="button"
              role="menuitem"
              tabIndex={-1}
              aria-current={item.current ? 'page' : undefined}
              onClick={() => {
                setOpen(false);
                item.onSelect();
              }}
              className={`flex w-full items-center gap-2 px-4 py-2.5 text-left text-sm hover:bg-gray-50 focus-visible:bg-gray-50 ${
                item.danger ? 'text-alerta' : item.current ? 'font-semibold text-carbon' : 'text-gray-700'
              }`}
            >
              {item.icon}
              <span className="flex-1">{item.label}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
};
