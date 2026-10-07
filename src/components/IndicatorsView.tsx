import React, { useEffect, useState } from 'react';
import { BarChart3, EyeOff, ShieldCheck } from 'lucide-react';
import { t } from '../lib/i18n';
import { api, AggregateMetrics } from '../lib/data';
import { VULNERABILITY_CATALOG } from '../lib/catalogs';
import { VulnerabilityMarkerCode } from '../types/database';

// Orden de lectura: volumen y tendencia, embudo de gestión, perfil y riesgo.
const METRIC_ORDER = [
  'intake_month',
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

// Etiqueta legible de cada grupo. Los estatus ya llegan en español desde el catálogo.
function bucketLabel(metric: string, bucket: string): string {
  switch (metric) {
    case 'intake_window_type':
      return t(`indicators.window.${bucket}`);
    case 'sex':
      return t(`indicators.sex.${bucket}`);
    case 'age_band':
      return t('indicators.age_years').replace('{band}', bucket);
    case 'intake_month': {
      const [y, m] = bucket.split('-').map(Number);
      return new Date(y, m - 1, 1).toLocaleDateString('es-MX', { month: 'long', year: 'numeric' });
    }
    case 'vulnerability':
      return VULNERABILITY_CATALOG[bucket as VulnerabilityMarkerCode]?.label || bucket;
    default:
      return bucket;
  }
}

export const IndicatorsView: React.FC = () => {
  const [data, setData] = useState<AggregateMetrics | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    api
      .aggregateMetrics()
      .then((r) => { if (!cancelled) setData(r); })
      .catch((e) => { if (!cancelled) setError(e instanceof Error ? e.message : String(e)); });
    return () => { cancelled = true; };
  }, []);

  if (error) {
    return (
      <div role="alert" className="rounded-lg border border-alerta/20 bg-alerta-bg p-4 text-xs text-alerta">
        {error}
      </div>
    );
  }
  if (!data) {
    return <p className="text-sm text-gray-500">{t('session.loading')}</p>;
  }

  const min = data.min_group_size;
  const total = data.rows.find((r) => r.metric === 'total_cases');
  const groups = METRIC_ORDER.map((metric) => ({
    metric,
    rows: data.rows.filter((r) => r.metric === metric),
  })).filter((g) => g.rows.length > 0);
  const allSuppressed = data.rows.every((r) => r.suppressed);

  return (
    <div className="space-y-6">
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
            <span className="text-[11px] text-gray-500">{t('indicators.metric.total_cases')}</span>
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
                          className="flex items-center gap-1 text-xs text-gray-400 shrink-0"
                          title={t('indicators.suppressed_hint')}
                        >
                          <EyeOff className="w-3.5 h-3.5" />
                          {t('indicators.suppressed').replace('{n}', String(min))}
                        </span>
                      ) : (
                        <span className="font-mono font-bold text-carbon shrink-0">{r.count}</span>
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
  );
};
