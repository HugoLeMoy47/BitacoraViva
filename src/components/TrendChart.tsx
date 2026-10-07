import React, { useEffect, useRef, useState } from 'react';
import { t } from '../lib/i18n';
import { formatMonth, formatMonthShort } from '../lib/format';

// Gráfica de barras agrupadas: ingresos vs egresos por mes.
// Colores: ranuras 1 y 2 de la paleta categórica validada (azul / naranja), en orden fijo.
// Una sola escala. La leyenda siempre está; el valor máximo de cada serie lleva etiqueta
// directa; el resto se lee en el tooltip y en la vista de tabla. Una celda suprimida (< n)
// no dibuja barra: se marca con un trazo punteado y se explica en el tooltip.
export interface TrendPoint {
  month: string; // YYYY-MM
  intake: number | null; // null = suprimido
  egress: number | null;
}

const SERIES = [
  { key: 'intake' as const, color: '#2a78d6', label: 'indicators.trend.intake' },
  { key: 'egress' as const, color: '#eb6834', label: 'indicators.trend.egress' },
];

function monthLabel(m: string): string {
  return formatMonth(m);
}

function niceMax(v: number): number {
  if (v <= 5) return 5;
  const step = v <= 20 ? 5 : v <= 50 ? 10 : 20;
  return Math.ceil(v / step) * step;
}

export const TrendChart: React.FC<{ points: TrendPoint[]; minGroup: number }> = ({ points, minGroup }) => {
  const [hover, setHover] = useState<number | null>(null);
  const [asTable, setAsTable] = useState(false);

  // El lienzo se mide en píxeles reales para que el texto conserve su tamaño en cualquier pantalla
  const wrapRef = useRef<HTMLDivElement>(null);
  const [W, setW] = useState(640);
  const H = 240;
  useEffect(() => {
    const el = wrapRef.current;
    if (!el || typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(() => setW(Math.max(280, Math.round(el.clientWidth))));
    ro.observe(el);
    setW(Math.max(280, Math.round(el.clientWidth)));
    return () => ro.disconnect();
  }, []);
  const m = { top: 24, right: 8, bottom: 30, left: 32 };
  const plotW = W - m.left - m.right;
  const plotH = H - m.top - m.bottom;

  const visible = points.flatMap((p) => [p.intake, p.egress]).filter((v): v is number => v !== null);
  const max = niceMax(Math.max(0, ...visible));
  const y = (v: number) => m.top + plotH - (v / max) * plotH;
  const colW = points.length > 0 ? plotW / points.length : plotW;
  const barW = Math.min(18, colW / 2 - 4);

  // Etiqueta directa sólo en el máximo de cada serie (nunca un número por punto)
  const maxOf = (k: 'intake' | 'egress') => {
    let best = -1;
    let bestIdx = -1;
    points.forEach((p, i) => {
      const v = p[k];
      if (v !== null && v > best) { best = v; bestIdx = i; }
    });
    return bestIdx;
  };
  const labelIdx = { intake: maxOf('intake'), egress: maxOf('egress') };

  const ticks = [0, 0.5, 1].map((f) => Math.round(max * f));
  const cell = (v: number | null) => (v === null ? t('indicators.suppressed').replace('{n}', String(minGroup)) : String(v));

  if (points.length === 0) {
    return <p className="text-xs text-gray-500">{t('indicators.trend.empty')}</p>;
  }

  return (
    <div ref={wrapRef} className="relative" style={{ ['--series-1' as string]: '#2a78d6', ['--series-2' as string]: '#eb6834' }}>
      <div className="flex items-center justify-between gap-3 mb-2 flex-wrap">
        <ul className="flex items-center gap-4 text-xs text-gray-700">
          {SERIES.map((s) => (
            <li key={s.key} className="flex items-center gap-1.5">
              <span className="inline-block w-3 h-3 rounded-[3px]" style={{ background: s.color }} aria-hidden="true" />
              {t(s.label)}
            </li>
          ))}
        </ul>
        <button
          type="button"
          onClick={() => setAsTable((v) => !v)}
          className="inline-flex min-h-9 items-center px-2 text-xs font-semibold text-turquesa-dark underline"
        >
          {asTable ? t('indicators.trend.view_chart') : t('indicators.trend.view_table')}
        </button>
      </div>

      {asTable ? (
        <table className="w-full text-xs">
          <thead>
            <tr className="text-left text-gray-500 border-b border-gray-200">
              <th className="py-1.5 font-medium">{t('indicators.trend.month')}</th>
              {SERIES.map((s) => (
                <th key={s.key} className="py-1.5 font-medium text-right">{t(s.label)}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {points.map((p) => (
              <tr key={p.month} className="border-b border-gray-100">
                <td className="py-1.5 text-carbon">{monthLabel(p.month)}</td>
                <td className="py-1.5 text-right font-mono text-carbon">{cell(p.intake)}</td>
                <td className="py-1.5 text-right font-mono text-carbon">{cell(p.egress)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : (
        <>
          <svg
            viewBox={`0 0 ${W} ${H}`}
            role="img"
            aria-label={t('indicators.trend.title')}
            width={W}
            height={H}
            className="block"
            onPointerLeave={() => setHover(null)}
          >
            {/* Cuadrícula recesiva y eje */}
            {ticks.map((tv) => (
              <g key={tv}>
                <line x1={m.left} x2={W - m.right} y1={y(tv)} y2={y(tv)} stroke="#e5e7eb" strokeWidth={1} />
                <text x={m.left - 6} y={y(tv) + 3} textAnchor="end" fontSize={12} fill="#6b7280">{tv}</text>
              </g>
            ))}

            {points.map((p, i) => {
              const cx = m.left + colW * i + colW / 2;
              const bars = [
                { s: SERIES[0], v: p.intake, x: cx - barW - 1 },
                { s: SERIES[1], v: p.egress, x: cx + 1 },
              ];
              return (
                <g key={p.month}>
                  {hover === i && (
                    <rect x={m.left + colW * i} y={m.top} width={colW} height={plotH} fill="#000" opacity={0.04} />
                  )}
                  {bars.map(({ s, v, x }) =>
                    v === null ? (
                      // Celda suprimida: sin barra, trazo punteado sobre la base
                      <line key={s.key} x1={x} x2={x + barW} y1={y(0) - 2} y2={y(0) - 2} stroke={s.color} strokeWidth={2} strokeDasharray="2 2" opacity={0.7} />
                    ) : (
                      <g key={s.key}>
                        <path
                          d={`M${x},${y(0)} V${y(v) + 4} Q${x},${y(v)} ${x + 4},${y(v)} H${x + barW - 4} Q${x + barW},${y(v)} ${x + barW},${y(v) + 4} V${y(0)} Z`}
                          fill={s.color}
                          opacity={hover === null || hover === i ? 1 : 0.55}
                        />
                        {labelIdx[s.key] === i && (
                          <text x={x + barW / 2} y={y(v) - 4} textAnchor="middle" fontSize={12} fontWeight={600} fill="#1f2937">{v}</text>
                        )}
                      </g>
                    )
                  )}
                  <text x={cx} y={H - 10} textAnchor="middle" fontSize={12} fill="#6b7280">{colW < 70 ? formatMonthShort(p.month, i === 0 || p.month.endsWith('-01')) : monthLabel(p.month)}</text>
                  {/* Área de impacto: toda la columna, más grande que la marca */}
                  <rect
                    x={m.left + colW * i}
                    y={m.top}
                    width={colW}
                    height={plotH + 18}
                    fill="transparent"
                    tabIndex={0}
                    role="img"
                    aria-label={`${monthLabel(p.month)}: ${t('indicators.trend.intake')} ${cell(p.intake)}, ${t('indicators.trend.egress')} ${cell(p.egress)}`}
                    onPointerMove={() => setHover(i)}
                    onFocus={() => setHover(i)}
                    onBlur={() => setHover(null)}
                  />
                </g>
              );
            })}
          </svg>

          {hover !== null && (
            <div
              role="status"
              className="pointer-events-none absolute z-10 rounded-lg border border-gray-200 bg-white px-3 py-2 text-xs shadow-md"
              style={{
                left: `${((m.left + colW * hover + colW / 2) / W) * 100}%`,
                top: 28,
                transform: hover > points.length / 2 ? 'translateX(-105%)' : 'translateX(5%)',
              }}
            >
              <p className="font-semibold text-carbon mb-1">{monthLabel(points[hover].month)}</p>
              {SERIES.map((s) => (
                <p key={s.key} className="flex items-center gap-2 text-gray-600">
                  <span className="inline-block w-3 h-0.5" style={{ background: s.color }} aria-hidden="true" />
                  <strong className="text-carbon font-mono">{cell(points[hover][s.key])}</strong>
                  <span>{t(s.label)}</span>
                </p>
              ))}
            </div>
          )}
        </>
      )}
    </div>
  );
};
