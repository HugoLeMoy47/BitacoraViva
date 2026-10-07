import React, { useEffect, useRef } from 'react';

// Pestañas accesibles: role="tablist"/"tab", aria-selected, un solo tab en el orden de Tab
// (el resto se alcanza con flechas, Inicio y Fin) y la pestaña activa siempre a la vista.
export interface TabItem {
  id: string;
  label: React.ReactNode;
  icon?: React.ReactNode;
  badge?: React.ReactNode;
}

interface TabsProps {
  items: TabItem[];
  value: string;
  onChange: (id: string) => void;
  ariaLabel: string;
  className?: string;
}

export const Tabs: React.FC<TabsProps> = ({ items, value, onChange, ariaLabel, className = '' }) => {
  const listRef = useRef<HTMLDivElement>(null);

  // Mantiene la pestaña activa visible aunque la fila se desplace
  useEffect(() => {
    const el = listRef.current?.querySelector<HTMLElement>('[aria-selected="true"]');
    el?.scrollIntoView?.({ inline: 'nearest', block: 'nearest' });
  }, [value]);

  const onKeyDown = (e: React.KeyboardEvent) => {
    const idx = items.findIndex((i) => i.id === value);
    let next = idx;
    if (e.key === 'ArrowRight') next = (idx + 1) % items.length;
    else if (e.key === 'ArrowLeft') next = (idx - 1 + items.length) % items.length;
    else if (e.key === 'Home') next = 0;
    else if (e.key === 'End') next = items.length - 1;
    else return;
    e.preventDefault();
    onChange(items[next].id);
    requestAnimationFrame(() => listRef.current?.querySelectorAll<HTMLElement>('[role="tab"]')[next]?.focus());
  };

  return (
    <div
      ref={listRef}
      role="tablist"
      aria-label={ariaLabel}
      onKeyDown={onKeyDown}
      className={`flex gap-1 overflow-x-auto border-b border-gray-200 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden ${className}`}
    >
      {items.map((item) => {
        const selected = item.id === value;
        return (
          <button
            key={item.id}
            type="button"
            role="tab"
            aria-selected={selected}
            tabIndex={selected ? 0 : -1}
            onClick={() => onChange(item.id)}
            className={`shrink-0 whitespace-nowrap px-4 py-3 text-sm font-semibold border-b-2 -mb-px flex items-center gap-2 transition ${
              selected ? 'border-turquesa text-carbon' : 'border-transparent text-gray-500 hover:text-carbon'
            }`}
          >
            {item.icon}
            <span>{item.label}</span>
            {item.badge}
          </button>
        );
      })}
    </div>
  );
};
