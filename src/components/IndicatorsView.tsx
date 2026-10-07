import React, { useEffect, useMemo, useState } from 'react';
import { ArrowDown, ArrowUp, BarChart3, EyeOff, ShieldCheck } from 'lucide-react';
import { t } from '../lib/i18n';
import { api, AggregateMetrics, AggregateMetricRow } from '../lib/data';
import { VULNERABILITY_CATALOG } from '../lib/catalogs';
import { VulnerabilityMarkerCode } from '../types/database';
import { TrendChart, TrendPoint } from './TrendChart';

// Orden de lectura: embudo de gestión, perfil y riesgo. Ingresos/egresos van en la tendencia.
const METRIC_ORDER = [
  'case_stage',
  'engagement_status',
  'shelter_status',
  'legal_status',
  'nationality',
  'age_band',
  'sex',
  'intake_window_type',
  'vulnerability',
];

type Preset = 'all' | '30' | '90' | '180' | 'custom';

const iso = (d: Date) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

function presetRange(p: Preset): { from: string | null; to: string | null } {
  if (p === 'all' || p === 'custom') return { from: null, to: null };
  const to = new Date();
  const from = new Date();
  from.setDate(from.getDate() - (Number(p) - 1));
  return { from: iso(from), to: iso(to) };
}

// Etiqueta legible de cada grupo. Los estatus ya llegan en español desde el catálogo.
function bucketLabel(metric: string, bucket: string): string {
  switch (metric) {
    case 'intake_window_type':
      return t(`indicators.window.${bucket}`);
    case 'sex':
      return t(`indicators.sex.${bucket}`);
    case 'age_band':
      return t('indicators.age_years').replace('{band}', bucket);
    case 'vulnerability':
      return VULNERABILITY_CATALOG[bucket as VulnerabilityMarkerCode]?.label || bucket;
    default:
      return bucket;
  }
}

// Diferencia contra el periodo anterior. Sólo si ambas cifras son visibles (cada una con su umbral).
const Delta: React.FC<{ current: number | null; previous: number | null; unit?: string }> = ({
  current,
  previous,
  unit = '',
}) => {
  if (current === null || previous === null) return null;
  const diff = Math.round((current - previous) * 10) / 10;
  if (diff === 0) {
    return <span className="text-xs text-gray-500 font-mono">= {previous}{unit}</span>;
  }
  const Icon = diff > 0 ? ArrowUp : ArrowDown;
  return (
    <span
      className="inline-flex items-center gap-0.5 text-xs text-gray-500 font-mono"
      title={t('indicators.vs_previous').replace('{n}', `${previous}${unit}`)}
    >
      <Icon className="w-3 h-3" aria-hidden="true" />
      {diff > 0 ? '+' : '−'}{Math.abs(diff)}{unit}
      <span className="text-gray-500">{t('indicators.vs_short').replace('{n}', `${previous}${unit}`)}</span>
    </span>
  );
};

export const IndicatorsView: React.FC = () => {
  const [preset, setPreset] = useState<Preset>('all');
  const [customFrom, setCustomFrom] = useState('');
  const [customTo, setCustomTo] = useState('');
  const [compare, setCompare] = useState(true);
  const [data, setData] = useState<AggregateMetrics | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const range = useMemo(() => {
    if (preset === 'custom') {
      return customFrom && customTo && customFrom <= customTo
        ? { from: customFrom, to: customTo }
        : { from: null, to: null };
    }
    return presetRange(preset);
  }, [preset, customFrom, customTo]);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    api
      .aggregateMetrics(range.from, range.to)
      .then((r) => { if (!cancelled) { setData(r); setError(null); } })
      .catch((e) => { if (!cancelled) setError(e instanceof Error ? e.message : String(e)); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [range.from, range.to]);

  const presets: { id: Preset; label: string }[] = [
    { id: 'all', label: t('indicators.period.all') },
    { id: '30', label: t('indicators.period.d30') },
    { id: '90', label: t('indicators.period.d90') },
    { id: '180', label: t('indicators.period.d180') },
    { id: 'custom', label: t('indicators.period.custom') },
  ];

  const filters = (
    <div className="bg-white rounded-xl border border-gray-200 shadow-sm p-4 flex flex-wrap items-center gap-3">
      <span className="text-xs font-bold uppercase tracking-wide text-gray-500">{t('indicators.period.label')}</span>
      <div className="flex flex-wrap gap-1.5" role="group" aria-label={t('indicators.period.label')}>
        {presets.map((p) => (
          <button
            key={p.id}
            type="button"
            onClick={() => setPreset(p.id)}
            aria-pressed={preset === p.id}
            className={`min-h-9 px-3 py-1.5 text-xs font-semibold rounded-lg border transition ${
              preset === p.id ? 'bg-claro border-turquesa text-carbon' : 'border-gray-200 text-gray-600 hover:bg-gray-50'
            }`}
          >
            {p.label}
          </button>
        ))}
      </div>
      {preset === 'custom' && (
        <div className="flex items-center gap-2 text-xs">
          <input
            type="date"
            value={customFrom}
            onChange={(e) => setCustomFrom(e.target.value)}
            aria-label={t('indicators.period.from')}
            className="p-1.5 border rounded-lg border-gray-300"
          />
          <span className="text-gray-500">→</span>
          <input
            type="date"
            value={customTo}
            onChange={(e) => setCustomTo(e.target.value)}
            aria-label={t('indicators.period.to')}
            className="p-1.5 border rounded-lg border-gray-300"
          />
        </div>
      )}
      <label className={`ml-auto flex items-center gap-2 text-xs ${range.from ? 'text-carbon' : 'text-gray-500'}`}>
        <input
          type="checkbox"
          checked={compare && !!range.from}
          disabled={!range.from}
          onChange={(e) => setCompare(e.target.checked)}
          className="rounded border-gray-300 text-turquesa"
        />
        {t('indicators.compare')}
      </label>
    </div>
  );

  if (error && !data) {
    return (
      <div className="space-y-4">
        {filters}
        <div role="alert" className="rounded-lg border border-alerta/20 bg-alerta-bg p-4 text-xs text-alerta">{error}</div>
      </div>
    );
  }
  if (!data) {
    return (
      <div className="space-y-4">
        {filters}
        <p className="text-sm text-gray-500">{t('session.loading')}</p>
      </div>
    );
  }

  const min = data.min_group_size;
  const showPrev = compare && !!data.period.from;
  const row = (metric: string, bucket: string): AggregateMetricRow | undefined =>
    data.rows.find((r) => r.metric === metric && r.bucket === bucket);
  const total = row('total_cases', 'all');
  const allSuppressed = data.rows.every((r) => r.suppressed);

  // Serie mensual: unión de meses de ingresos y egresos, en orden cronológico
  const months = Array.from(
    new Set(data.rows.filter((r) => r.metric === 'intake_month' || r.metric === 'egress_month').map((r) => r.bucket))
  ).sort();
  const trend: TrendPoint[] = months.map((mo) => {
    const a = row('intake_month', mo);
    const b = row('egress_month', mo);
    return { month: mo, intake: a ? a.count : 0, egress: b ? b.count : 0 };
  });

  const groups = METRIC_ORDER.map((metric) => ({
    metric,
    rows: data.rows.filter((r) => r.metric === metric),
  })).filter((g) => g.rows.length > 0);

  const durations = (['to_case_plan', 'to_closure'] as const).map((b) => ({ bucket: b, r: row('duration', b) }));

  return (
    <div className="space-y-6">
      {filters}

      <div className={`space-y-6 transition-opacity ${loading ? 'opacity-60' : ''}`} aria-busy={loading}>
        <div className="bg-white rounded-xl border border-gray-200 shadow-sm p-6">
          <div className="flex items-start justify-between gap-4 flex-wrap">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-claro rounded-lg text-turquesa-dark">
                <BarChart3 className="w-5 h-5" />
              </div>
              <div>
                <h2 className="text-base font-bold text-carbon">{t('indicators.title')}</h2>
                <p className="text-xs text-gray-500">{t('indicators.subtitle')}</p>
              </div>
            </div>
            <div className="text-right">
              <span className="block text-3xl font-bold text-carbon leading-none">
                {total && !total.suppressed ? total.count : '—'}
              </span>
              <span className="text-xs text-gray-500 block">{t('indicators.metric.total_cases')}</span>
              {showPrev && total && <Delta current={total.count} previous={total.prev_count} />}
            </div>
          </div>
          <p className="mt-4 flex items-start gap-2 text-xs text-carbon-muted">
            <ShieldCheck className="w-4 h-4 text-turquesa-dark shrink-0 mt-px" />
            <span>{t('indicators.threshold_note').replace('{n}', String(min))}</span>
          </p>
          {allSuppressed && (
            <p className="mt-3 rounded-lg bg-gray-50 border border-gray-200 p-3 text-xs text-gray-600">
              {t('indicators.all_suppressed').replace('{n}', String(min))}
            </p>
          )}
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <div className="lg:col-span-2 bg-white rounded-xl border border-gray-200 shadow-sm p-5">
            <h3 className="text-xs font-bold uppercase tracking-wide text-gray-600 mb-3">{t('indicators.trend.title')}</h3>
            <TrendChart points={trend} minGroup={min} />
          </div>

          <div className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden">
            <div className="px-5 py-3 border-b border-gray-200 bg-gray-50 text-xs font-bold uppercase tracking-wide text-gray-600">
              {t('indicators.metric.duration')}
            </div>
            <ul className="divide-y divide-gray-100 text-sm">
              {durations.map(({ bucket, r }) => (
                <li key={bucket} className="px-5 py-3">
                  <p className="text-xs text-gray-500">{t(`indicators.duration.${bucket}`)}</p>
                  {!r || r.suppressed ? (
                    <span className="flex items-center gap-1 text-xs text-gray-500 mt-1">
                      <EyeOff className="w-3.5 h-3.5" />
                      {t('indicators.suppressed').replace('{n}', String(min))}
                    </span>
                  ) : (
                    <div className="mt-0.5 flex items-baseline gap-2 flex-wrap">
                      <span className="text-2xl font-bold text-carbon">{r.value}</span>
                      <span className="text-xs text-gray-500">{t('indicators.days_avg').replace('{n}', String(r.count))}</span>
                      {showPrev && <Delta current={r.value} previous={r.prev_value} unit={` ${t('indicators.days_short')}`} />}
                    </div>
                  )}
                </li>
              ))}
            </ul>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {groups.map((g) => {
            const max = Math.max(1, ...g.rows.map((r) => r.count ?? 0));
            return (
              <div key={g.metric} className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden">
                <div className="px-5 py-3 border-b border-gray-200 bg-gray-50 text-xs font-bold uppercase tracking-wide text-gray-600">
                  {t(`indicators.metric.${g.metric}`)}
                </div>
                <ul className="divide-y divide-gray-100 text-sm">
                  {g.rows.map((r) => (
                    <li key={r.bucket} className="px-5 py-2.5">
                      <div className="flex items-center justify-between gap-3">
                        <span className="text-carbon">{bucketLabel(g.metric, r.bucket)}</span>
                        {r.suppressed ? (
                          <span
                            className="flex items-center gap-1 text-xs text-gray-500 shrink-0"
                            title={t('indicators.suppressed_hint')}
                          >
                            <EyeOff className="w-3.5 h-3.5" />
                            {t('indicators.suppressed').replace('{n}', String(min))}
                          </span>
                        ) : (
                          <span className="flex items-center gap-2 shrink-0">
                            {showPrev && <Delta current={r.count} previous={r.prev_count} />}
                            <span className="font-mono font-bold text-carbon">{r.count}</span>
                          </span>
                        )}
                      </div>
                      {!r.suppressed && (
                        <div className="mt-1.5 h-1.5 rounded-full bg-gray-100" aria-hidden="true">
                          <div
                            className="h-1.5 rounded-full bg-turquesa"
                            style={{ width: `${Math.round(((r.count ?? 0) / max) * 100)}%` }}
                          />
                        </div>
                      )}
                    </li>
                  ))}
                </ul>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};
