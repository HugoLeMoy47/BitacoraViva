import React from 'react';

// Barras horizontales HECHAS DE HTML, no de SVG. Un <svg viewBox="…"> con ancho fluido escala todo lo
// que lleva dentro, el texto incluido: en un Android de 360 una etiqueta de 13 px llegaba a pintarse a
// 6 px reales, y ese error es invisible leyendo el código. Aquí el texto es texto (con el tamaño real y
// el que la persona configuró en su teléfono) y la barra es un ancho porcentual. Cada fila lleva
// también su cifra escrita: el color nunca es la única forma de leer el dato.

export interface BarSegment {
  value: number;
  /** clase de color del segmento (p. ej. `bg-turquesa`) */
  className: string;
  /** nombre del segmento, para lectores de pantalla y leyenda */
  label: string;
}

export interface BarItem {
  key: string;
  label: string;
  segments: BarSegment[];
  /** Cifra escrita a la derecha de la barra */
  valueText: string;
}

interface ReportBarsProps {
  items: BarItem[];
  /** Escala común (el mayor total). Si no se da, se calcula. */
  max?: number;
  /** `stacked`: segmentos en una sola barra · `grouped`: una barra delgada por segmento */
  mode?: 'stacked' | 'grouped';
  ariaLabel: string;
}

export const ReportBars: React.FC<ReportBarsProps> = ({ items, max, mode = 'stacked', ariaLabel }) => {
  const scale =
    max ?? Math.max(1, ...items.map((i) => (mode === 'stacked' ? i.segments.reduce((s, x) => s + x.value, 0) : Math.max(0, ...i.segments.map((x) => x.value)))));

  return (
    <ul aria-label={ariaLabel} className="space-y-3">
      {items.map((item) => (
        <li key={item.key} className="grid grid-cols-1 gap-1 sm:grid-cols-[minmax(7rem,12rem)_1fr_auto] sm:items-center sm:gap-3">
          <span className="truncate text-sm text-carbon" title={item.label}>
            {item.label}
          </span>
          {mode === 'stacked' ? (
            <div className="flex h-3 overflow-hidden rounded-full bg-gray-100" aria-hidden="true">
              {item.segments.map((s) => (
                <div key={s.label} className={s.className} style={{ width: `${(s.value / scale) * 100}%` }} />
              ))}
            </div>
          ) : (
            <div className="space-y-1" aria-hidden="true">
              {item.segments.map((s) => (
                <div key={s.label} className="h-2 overflow-hidden rounded-full bg-gray-100">
                  <div className={`h-full ${s.className}`} style={{ width: `${(s.value / scale) * 100}%` }} />
                </div>
              ))}
            </div>
          )}
          <span className="font-mono text-xs text-gray-700">{item.valueText}</span>
        </li>
      ))}
    </ul>
  );
};

/** Leyenda de colores con su nombre escrito. */
export const BarLegend: React.FC<{ items: { className: string; label: string }[] }> = ({ items }) => (
  <ul className="mb-3 flex flex-wrap gap-x-4 gap-y-1 text-xs text-gray-700">
    {items.map((i) => (
      <li key={i.label} className="inline-flex items-center gap-1.5">
        <span className={`inline-block h-3 w-3 rounded-sm ${i.className}`} aria-hidden="true" />
        {i.label}
      </li>
    ))}
  </ul>
);
