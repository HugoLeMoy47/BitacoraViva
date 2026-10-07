import React, { useEffect, useMemo, useState } from 'react';
import { Activity, Bell, Clock, ShieldAlert, UserPlus, Users } from 'lucide-react';
import { t } from '../lib/i18n';
import { CaseWithDetails, SharingEvent } from '../types/database';
import { useCatalog } from '../lib/catalog';
import { api, StageHistoryRow } from '../lib/data';

// Tablero de operación para Dirección (BV-2.4): qué requiere atención hoy.
// A diferencia de los indicadores agregados, aquí sí hay expedientes identificables:
// es una vista de trabajo del rol director, y todo lo que muestra ya lo permite RLS.
interface Props {
  cases: CaseWithDetails[];
  sharingEvents: SharingEvent[];
  onOpenCase: (caseId: string) => void;
  onOpenDigest: () => void;
}

const MS_DAY = 86_400_000;
const daysSince = (iso: string) => Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / MS_DAY));

// Estatus de acompañamiento que no deberían estancarse
const STALLED_CODES = ['first_contact', 'under_assessment', 'paused'];

const Kpi: React.FC<{
  icon: React.ReactNode;
  label: string;
  value: number;
  hint?: string;
  onClick?: () => void;
  tone?: 'default' | 'attention';
}> = ({ icon, label, value, hint, onClick, tone = 'default' }) => {
  const body = (
    <>
      <div className={`p-2 rounded-lg ${tone === 'attention' && value > 0 ? 'bg-alerta-bg text-alerta' : 'bg-claro text-turquesa-dark'}`}>
        {icon}
      </div>
      <div className="text-left">
        <span className="block text-2xl font-bold text-carbon leading-none">{value}</span>
        <span className="block text-xs font-semibold text-carbon mt-1">{label}</span>
        {hint && <span className="block text-[11px] text-gray-500">{hint}</span>}
      </div>
    </>
  );
  const cls = 'bg-white rounded-xl border border-gray-200 shadow-sm p-4 flex items-start gap-3';
  return onClick ? (
    <button type="button" onClick={onClick} className={`${cls} hover:border-turquesa transition w-full`}>{body}</button>
  ) : (
    <div className={cls}>{body}</div>
  );
};

export const OperationsDashboard: React.FC<Props> = ({ cases, sharingEvents, onOpenCase, onOpenDigest }) => {
  const { statusAxes, statusValues } = useCatalog();
  const [threshold, setThreshold] = useState(30);
  const [history, setHistory] = useState<StageHistoryRow[] | null>(null);
  const [historyError, setHistoryError] = useState<string | null>(null);

  const stageAxis = statusAxes.find((a) => a.code === 'case_stage');

  useEffect(() => {
    if (!stageAxis) return;
    let cancelled = false;
    api
      .loadStageHistory(stageAxis.id)
      .then((r) => { if (!cancelled) setHistory(r); })
      .catch((e) => { if (!cancelled) setHistoryError(e instanceof Error ? e.message : String(e)); });
    return () => { cancelled = true; };
  }, [stageAxis?.id]);

  const live = useMemo(() => cases.filter((c) => !c.person.is_anonymized), [cases]);

  const kpis = useMemo(() => {
    const today = Date.now();
    return {
      activeCare: live.filter((c) => c.statuses.engagement_status.isActiveCare).length,
      recentIntake: live.filter((c) => today - new Date(c.opened_at).getTime() <= 30 * MS_DAY).length,
      withMarkers: live.filter((c) => c.vulnerabilities.length > 0).length,
      pendingDigest: sharingEvents.filter((s) => !s.acknowledged_at).length,
    };
  }, [live, sharingEvents]);

  const attention = useMemo(
    () =>
      live
        .filter((c) => STALLED_CODES.includes(c.statuses.engagement_status.valueCode))
        .map((c) => ({ c, days: daysSince(c.statuses.engagement_status.valid_from) }))
        .filter((x) => x.days >= threshold)
        .sort((a, b) => b.days - a.days),
    [live, threshold]
  );

  // Control P-06: expedientes con datos sensibles sin consentimiento expreso vigente
  const missingSensitive = useMemo(
    () => live.filter((c) => !(c.consents || []).some((k) => k.consent_type === 'sensitive_data' && k.status === 'granted')),
    [live]
  );

  // Permanencia por etapa: promedio de días que los casos pasaron (o llevan) en cada etapa
  const stageRows = useMemo(() => {
    const values = statusValues.case_stage;
    return values.map((v) => {
      const rows = (history || []).filter((h) => h.value_id === v.id);
      const caseIds = new Set(rows.map((h) => h.case_id));
      const avg = rows.length
        ? rows.reduce((acc, h) => {
            const end = h.valid_to ? new Date(h.valid_to).getTime() : Date.now();
            return acc + (end - new Date(h.valid_from).getTime()) / MS_DAY;
          }, 0) / rows.length
        : null;
      const now = live.filter((c) => c.statuses.case_stage.valueCode === v.code).length;
      return { id: v.id, label: v.label_es, now, avg: avg === null ? null : Math.round(avg * 10) / 10, n: caseIds.size };
    });
  }, [history, statusValues.case_stage, live]);
  const maxAvg = Math.max(1, ...stageRows.map((r) => r.avg ?? 0));

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-base font-bold text-carbon">{t('operations.title')}</h2>
        <p className="text-xs text-gray-500">{t('operations.subtitle')}</p>
      </div>

      <div className="grid grid-cols-2 lg:grid-cols-5 gap-3">
        <Kpi icon={<Activity className="w-5 h-5" />} label={t('operations.kpi.active_care')} value={kpis.activeCare} />
        <Kpi icon={<UserPlus className="w-5 h-5" />} label={t('operations.kpi.recent_intake')} value={kpis.recentIntake} hint={t('operations.kpi.last_30')} />
        <Kpi
          icon={<Clock className="w-5 h-5" />}
          label={t('operations.kpi.attention')}
          value={attention.length}
          hint={t('operations.kpi.attention_hint').replace('{n}', String(threshold))}
          tone="attention"
        />
        <Kpi
          icon={<Bell className="w-5 h-5" />}
          label={t('operations.kpi.digest')}
          value={kpis.pendingDigest}
          hint={t('operations.kpi.digest_hint')}
          onClick={onOpenDigest}
          tone="attention"
        />
        <Kpi
          icon={<ShieldAlert className="w-5 h-5" />}
          label={t('operations.kpi.p06')}
          value={missingSensitive.length}
          hint={t('operations.kpi.p06_hint')}
          tone="attention"
        />
      </div>

      <div className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden">
        <div className="px-5 py-3 border-b border-gray-200 bg-gray-50 flex items-center justify-between flex-wrap gap-2">
          <div>
            <h3 className="text-xs font-bold uppercase tracking-wide text-gray-600">{t('operations.attention.title')}</h3>
            <p className="text-[11px] text-gray-500">{t('operations.attention.subtitle')}</p>
          </div>
          <label className="flex items-center gap-2 text-xs text-gray-600">
            {t('operations.attention.threshold')}
            <select
              value={threshold}
              onChange={(e) => setThreshold(Number(e.target.value))}
              className="p-1.5 border rounded-lg border-gray-300 text-xs"
            >
              {[14, 30, 45, 60].map((n) => (
                <option key={n} value={n}>{n} {t('operations.days')}</option>
              ))}
            </select>
          </label>
        </div>
        {attention.length === 0 ? (
          <p className="px-5 py-6 text-xs text-gray-500">{t('operations.attention.empty').replace('{n}', String(threshold))}</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full text-xs">
              <thead className="text-gray-500 uppercase bg-white">
                <tr>
                  <th className="px-5 py-2 text-left font-medium">{t('operations.col.folio')}</th>
                  <th className="px-5 py-2 text-left font-medium">{t('operations.col.person')}</th>
                  <th className="px-5 py-2 text-left font-medium">{t('operations.col.status')}</th>
                  <th className="px-5 py-2 text-right font-medium">{t('operations.col.days')}</th>
                  <th className="px-5 py-2" />
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {attention.slice(0, 12).map(({ c, days }) => (
                  <tr key={c.id} className="hover:bg-gray-50">
                    <td className="px-5 py-2 font-mono font-bold text-turquesa-dark">{c.case_number}</td>
                    <td className="px-5 py-2 text-carbon">{c.person.given_name} {c.person.paternal_family_name}</td>
                    <td className="px-5 py-2 text-gray-600">{c.statuses.engagement_status.label}</td>
                    <td className="px-5 py-2 text-right font-mono font-bold text-carbon">{days}</td>
                    <td className="px-5 py-2 text-right">
                      <button type="button" onClick={() => onOpenCase(c.id)} className="font-semibold text-turquesa-dark underline">
                        {t('operations.open_case')}
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            {attention.length > 12 && (
              <p className="px-5 py-2 text-[11px] text-gray-500">{t('operations.attention.more').replace('{n}', String(attention.length - 12))}</p>
            )}
          </div>
        )}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden">
          <div className="px-5 py-3 border-b border-gray-200 bg-gray-50">
            <h3 className="text-xs font-bold uppercase tracking-wide text-gray-600">{t('operations.stage.title')}</h3>
            <p className="text-[11px] text-gray-500">{t('operations.stage.subtitle')}</p>
          </div>
          {historyError ? (
            <p role="alert" className="px-5 py-4 text-xs text-alerta">{historyError}</p>
          ) : (
            <ul className="divide-y divide-gray-100 text-sm">
              {stageRows.map((r) => (
                <li key={r.id} className="px-5 py-2.5">
                  <div className="flex items-center justify-between gap-3">
                    <span className="text-carbon">{r.label}</span>
                    <span className="flex items-center gap-3 shrink-0 text-xs">
                      <span className="flex items-center gap-1 text-gray-500" title={t('operations.stage.now')}>
                        <Users className="w-3.5 h-3.5" aria-hidden="true" />
                        <span className="font-mono">{r.now}</span>
                      </span>
                      <span className="font-mono font-bold text-carbon w-16 text-right">
                        {r.avg === null ? '—' : `${r.avg} ${t('operations.days_short')}`}
                      </span>
                    </span>
                  </div>
                  {r.avg !== null && (
                    <div className="mt-1.5 h-1.5 rounded-full bg-gray-100" aria-hidden="true">
                      <div className="h-1.5 rounded-full bg-turquesa" style={{ width: `${Math.round((r.avg / maxAvg) * 100)}%` }} />
                    </div>
                  )}
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden">
          <div className="px-5 py-3 border-b border-gray-200 bg-gray-50">
            <h3 className="text-xs font-bold uppercase tracking-wide text-gray-600">{t('operations.p06.title')}</h3>
            <p className="text-[11px] text-gray-500">{t('operations.p06.subtitle')}</p>
          </div>
          {missingSensitive.length === 0 ? (
            <p className="px-5 py-6 text-xs text-gray-500">{t('operations.p06.empty')}</p>
          ) : (
            <ul className="divide-y divide-gray-100 text-xs">
              {missingSensitive.slice(0, 8).map((c) => (
                <li key={c.id} className="px-5 py-2.5 flex items-center justify-between gap-3">
                  <span>
                    <span className="font-mono font-bold text-turquesa-dark">{c.case_number}</span>{' '}
                    <span className="text-carbon">{c.person.given_name} {c.person.paternal_family_name}</span>
                  </span>
                  <button type="button" onClick={() => onOpenCase(c.id)} className="font-semibold text-turquesa-dark underline shrink-0">
                    {t('operations.open_case')}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </div>
  );
};
