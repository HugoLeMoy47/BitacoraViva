import React, { useEffect, useMemo, useState } from 'react';
import { History } from 'lucide-react';
import { t } from '../lib/i18n';
import { api, CaseStatusHistoryRow } from '../lib/data';
import { useCatalog } from '../lib/catalog';
import { formatDate } from '../lib/format';

// Historial completo de estatus de un expediente (BV-2.3): qué valor, desde cuándo, hasta cuándo,
// quién y por qué. El estatus no se sobrescribe: cada cambio cierra el vigente y abre uno nuevo.
const MS_DAY = 86_400_000;
const days = (from: string, to: string | null) =>
  Math.max(0, Math.floor(((to ? new Date(to).getTime() : Date.now()) - new Date(from).getTime()) / MS_DAY));

export const StatusHistory: React.FC<{ caseId: string }> = ({ caseId }) => {
  const { statusAxes, statusValues, userNames } = useCatalog();
  const [rows, setRows] = useState<CaseStatusHistoryRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setRows(null);
    setError(null);
    api
      .loadCaseStatusHistory(caseId)
      .then((r) => { if (!cancelled) setRows(r); })
      .catch((e) => { if (!cancelled) setError(e instanceof Error ? e.message : String(e)); });
    return () => { cancelled = true; };
  }, [caseId]);

  const valueLabel = useMemo(() => {
    const map = new Map<string, string>();
    Object.values(statusValues).flat().forEach((v) => map.set(v.id, v.label_es));
    return map;
  }, [statusValues]);

  return (
    <section className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
      <h3 className="mb-1 flex items-center gap-2 text-sm font-bold text-carbon">
        <History className="h-4 w-4 text-turquesa-dark" aria-hidden="true" />
        {t('cases.history.title')}
      </h3>
      <p className="mb-3 text-xs text-gray-500">{t('cases.history.subtitle')}</p>

      {error && <p role="alert" className="text-xs text-alerta">{error}</p>}
      {!error && rows === null && <p className="text-xs text-gray-500">{t('session.loading')}</p>}

      {rows && (
        <div className="space-y-2">
          {statusAxes.map((axis) => {
            const items = rows.filter((r) => r.axis_id === axis.id);
            if (items.length === 0) return null;
            return (
              <details key={axis.id} className="rounded-lg border border-gray-200 bg-gray-50">
                <summary className="flex cursor-pointer items-center justify-between gap-2 px-3 py-2 text-xs font-semibold text-carbon">
                  <span>{axis.label_es}</span>
                  <span className="font-mono font-normal text-gray-500">
                    {t('cases.history.changes').replace('{n}', String(items.length))}
                  </span>
                </summary>
                <ol className="space-y-3 border-t border-gray-200 px-3 py-3">
                  {items.map((r, i) => {
                    const who = r.created_by ? userNames[r.created_by] : undefined;
                    return (
                      <li key={`${r.valid_from}-${i}`} className="text-xs">
                        <p className="flex flex-wrap items-baseline gap-x-2">
                          <strong className="text-carbon">{valueLabel.get(r.value_id) ?? '—'}</strong>
                          {!r.valid_to && (
                            <span className="rounded bg-claro px-1.5 text-turquesa-dark">{t('cases.history.current')}</span>
                          )}
                        </p>
                        <p className="text-gray-500">
                          {r.valid_to
                            ? t('cases.history.range').replace('{from}', formatDate(r.valid_from)).replace('{to}', formatDate(r.valid_to))
                            : t('cases.history.since').replace('{from}', formatDate(r.valid_from))}
                          {' · '}
                          {t('cases.history.days').replace('{n}', String(days(r.valid_from, r.valid_to)))}
                          {who ? ` · ${who}` : ''}
                        </p>
                        {r.reason && <p className="italic text-gray-600">“{r.reason}”</p>}
                      </li>
                    );
                  })}
                </ol>
              </details>
            );
          })}
        </div>
      )}
    </section>
  );
};
