import React, { useDeferredValue, useMemo, useState } from 'react';
import { FileText } from 'lucide-react';
import { t } from '../lib/i18n';
import { formatDate, formatDateTime } from '../lib/format';
import { Area, AuditEvent, AuthorityRequest } from '../types/database';

// Pantallas de administración y gobierno (sólo Dirección; la base impone el acceso con RLS).

export const AreasView: React.FC<{ areas: Area[] }> = ({ areas }) => (
  <section className="overflow-hidden rounded-xl border border-gray-200 bg-white shadow-sm">
    <div className="border-b border-gray-200 px-5 py-4">
      <h2 className="text-base font-bold text-carbon">{t('dashboard.areas_title')}</h2>
    </div>
    <ul className="divide-y divide-gray-100">
      {areas.map((area) => (
        <li key={area.id} className="flex items-center justify-between gap-3 px-5 py-3 hover:bg-gray-50">
          <div className="flex min-w-0 items-center gap-3">
            <span
              className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-claro text-xs font-bold text-turquesa-dark"
              aria-hidden="true"
            >
              {area.code.substring(0, 2).toUpperCase()}
            </span>
            <div className="min-w-0">
              <h3 className="truncate text-sm font-semibold text-carbon">{area.name}</h3>
              <p className="truncate font-mono text-xs text-gray-500">{area.code}</p>
            </div>
          </div>
          <span className="shrink-0 rounded-full bg-green-100 px-2.5 py-0.5 text-xs font-medium text-green-800">
            {t('dashboard.active_badge')}
          </span>
        </li>
      ))}
    </ul>
  </section>
);

const AUDIT_PAGE = 50;

export const AuditView: React.FC<{ events: AuditEvent[]; userNames: Record<string, string> }> = ({ events, userNames }) => {
  const [action, setAction] = useState('');
  const [table, setTable] = useState('');
  const [actor, setActor] = useState('');
  const [text, setText] = useState('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [limit, setLimit] = useState(AUDIT_PAGE);
  const term = useDeferredValue(text).trim().toLowerCase();

  const actions = useMemo(() => Array.from(new Set(events.map((e) => e.action))).sort(), [events]);
  const tables = useMemo(() => Array.from(new Set(events.map((e) => e.table_name))).sort(), [events]);
  const actors = useMemo(
    () => Array.from(new Set(events.map((e) => e.user_id).filter((x): x is string => !!x))),
    [events]
  );
  const actorName = (id: string | null) => (id ? userNames[id] ?? id.slice(0, 8) : t('audit.system'));

  const filtered = useMemo(
    () =>
      events.filter((e) => {
        if (action && e.action !== action) return false;
        if (table && e.table_name !== table) return false;
        if (actor && e.user_id !== actor) return false;
        const day = e.created_at.slice(0, 10);
        if (from && day < from) return false;
        if (to && day > to) return false;
        if (!term) return true;
        return (
          (e.record_id ?? '').toLowerCase().includes(term) ||
          JSON.stringify(e.new_values ?? {}).toLowerCase().includes(term) ||
          JSON.stringify(e.old_values ?? {}).toLowerCase().includes(term)
        );
      }),
    [events, action, table, actor, from, to, term]
  );
  const visible = filtered.slice(0, limit);
  const selectCls = 'w-full rounded-lg border border-gray-300 bg-white p-2 text-sm focus:border-turquesa focus:outline-none';
  const reset = () => setLimit(AUDIT_PAGE);
  const clear = () => {
    setAction('');
    setTable('');
    setActor('');
    setText('');
    setFrom('');
    setTo('');
    reset();
  };
  const hasFilters = !!(action || table || actor || text || from || to);

  return (
    <section className="overflow-hidden rounded-xl border border-gray-200 bg-white shadow-sm">
      <div className="border-b border-gray-200 px-5 py-4">
        <h2 className="text-base font-bold text-carbon">{t('dashboard.audit_title')}</h2>
        <p className="text-xs text-gray-600">{t('audit.subtitle')}</p>
      </div>

      <div className="grid grid-cols-2 gap-3 border-b border-gray-200 bg-gray-50 p-4 lg:grid-cols-6">
        <div>
          <label htmlFor="au-action" className="mb-1 block text-xs font-medium text-gray-600">{t('audit.filters.action')}</label>
          <select id="au-action" name="au-action" value={action} onChange={(e) => { setAction(e.target.value); reset(); }} className={selectCls}>
            <option value="">{t('audit.filters.all_f')}</option>
            {actions.map((x) => <option key={x} value={x}>{x}</option>)}
          </select>
        </div>
        <div>
          <label htmlFor="au-table" className="mb-1 block text-xs font-medium text-gray-600">{t('audit.filters.table')}</label>
          <select id="au-table" name="au-table" value={table} onChange={(e) => { setTable(e.target.value); reset(); }} className={selectCls}>
            <option value="">{t('audit.filters.all_f')}</option>
            {tables.map((x) => <option key={x} value={x}>{x}</option>)}
          </select>
        </div>
        <div className="col-span-2 lg:col-span-1">
          <label htmlFor="au-actor" className="mb-1 block text-xs font-medium text-gray-600">{t('audit.filters.actor')}</label>
          <select id="au-actor" name="au-actor" value={actor} onChange={(e) => { setActor(e.target.value); reset(); }} className={selectCls}>
            <option value="">{t('audit.filters.all_f')}</option>
            {actors.map((id) => <option key={id} value={id}>{actorName(id)}</option>)}
          </select>
        </div>
        <div>
          <label htmlFor="au-from" className="mb-1 block text-xs font-medium text-gray-600">{t('audit.filters.from')}</label>
          <input id="au-from" name="au-from" type="date" value={from} onChange={(e) => { setFrom(e.target.value); reset(); }} className={selectCls} />
        </div>
        <div>
          <label htmlFor="au-to" className="mb-1 block text-xs font-medium text-gray-600">{t('audit.filters.to')}</label>
          <input id="au-to" name="au-to" type="date" value={to} onChange={(e) => { setTo(e.target.value); reset(); }} className={selectCls} />
        </div>
        <div className="col-span-2 lg:col-span-1">
          <label htmlFor="au-text" className="mb-1 block text-xs font-medium text-gray-600">{t('audit.filters.search')}</label>
          <input id="au-text" name="au-text" type="search" autoComplete="off" value={text} onChange={(e) => { setText(e.target.value); reset(); }} placeholder={t('audit.filters.search_ph')} className={selectCls} />
        </div>
        <div className="col-span-2 flex flex-wrap items-center justify-between gap-2 lg:col-span-6">
          <p aria-live="polite" className="font-mono text-xs text-gray-600">
            {t('audit.showing').replace('{shown}', String(visible.length)).replace('{total}', String(filtered.length))}
            {events.length >= 500 && ' · ' + t('audit.limit_note')}
          </p>
          {hasFilters && (
            <button type="button" onClick={clear} className="text-sm font-semibold text-turquesa-dark underline">{t('cases.list.clear')}</button>
          )}
        </div>
      </div>

      <div className="overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200 text-xs">
          <thead className="bg-gray-50 font-medium uppercase text-gray-600">
            <tr>
              <th scope="col" className="px-5 py-3 text-left">{t('dashboard.table_column_timestamp')}</th>
              <th scope="col" className="px-5 py-3 text-left">{t('dashboard.table_column_action')}</th>
              <th scope="col" className="px-5 py-3 text-left">{t('dashboard.table_column_table')}</th>
              <th scope="col" className="px-5 py-3 text-left">{t('audit.filters.actor')}</th>
              <th scope="col" className="px-5 py-3 text-left">{t('dashboard.table_column_record')}</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100 bg-white">
            {visible.map((event) => (
              <tr key={event.id} className="hover:bg-gray-50">
                <td className="whitespace-nowrap px-5 py-3 text-gray-700">{formatDateTime(event.created_at)}</td>
                <td className="whitespace-nowrap px-5 py-3">
                  <span className="rounded border border-gray-300 bg-gray-100 px-2 py-0.5 font-mono text-xs font-bold text-carbon">{event.action}</span>
                </td>
                <td className="px-5 py-3 font-mono font-semibold text-carbon">{event.table_name}</td>
                <td className="whitespace-nowrap px-5 py-3 text-gray-700">{actorName(event.user_id)}</td>
                <td className="max-w-[14rem] truncate px-5 py-3 font-mono text-gray-600" title={event.record_id ?? ''}>{event.record_id}</td>
              </tr>
            ))}
            {visible.length === 0 && (
              <tr>
                <td colSpan={5} className="px-5 py-8 text-center text-sm text-gray-600">{t('audit.no_results')}</td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {filtered.length > visible.length && (
        <div className="border-t border-gray-200 p-4 text-center">
          <button
            type="button"
            onClick={() => setLimit((n) => n + AUDIT_PAGE)}
            className="rounded-lg border border-gray-300 bg-white px-5 py-2 text-sm font-semibold text-carbon hover:bg-gray-50"
          >
            {t('cases.list.more').replace('{n}', String(Math.min(AUDIT_PAGE, filtered.length - visible.length)))}
          </button>
        </div>
      )}
    </section>
  );
};

export const AuthorityView: React.FC<{ requests: AuthorityRequest[] }> = ({ requests }) => (
  <section className="overflow-hidden rounded-xl border border-gray-200 bg-white shadow-sm">
    <div className="flex flex-wrap items-center justify-between gap-2 border-b border-gray-200 px-5 py-4">
      <div>
        <h2 className="text-base font-bold text-carbon">{t('authority_requests.title')}</h2>
        <p className="text-xs text-gray-500">{t('authority_requests.subtitle')}</p>
      </div>
      <span className="rounded border border-turquesa/30 bg-claro px-2 py-1 font-mono text-xs text-carbon">
        {t('authority_requests.count').replace('{n}', String(requests.length))}
      </span>
    </div>

    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-gray-200 text-xs">
        <thead className="bg-gray-50 font-medium uppercase text-gray-500">
          <tr>
            <th scope="col" className="px-5 py-3 text-left">{t('authority_requests.table_column_authority')}</th>
            <th scope="col" className="px-5 py-3 text-left">{t('authority_requests.table_column_ref')}</th>
            <th scope="col" className="px-5 py-3 text-left">{t('authority_requests.table_column_type')}</th>
            <th scope="col" className="px-5 py-3 text-left">{t('authority_requests.table_column_received')}</th>
            <th scope="col" className="px-5 py-3 text-left">{t('authority_requests.table_column_status')}</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100 bg-white">
          {requests.map((req) => (
            <tr key={req.id} className="hover:bg-gray-50">
              <td className="px-5 py-3 font-semibold text-carbon">{req.authority_name}</td>
              <td className="px-5 py-3 font-mono text-gray-700">{req.official_letter_ref}</td>
              <td className="px-5 py-3 text-gray-600">{req.request_type}</td>
              <td className="whitespace-nowrap px-5 py-3 text-gray-500">{formatDate(req.received_at)}</td>
              <td className="px-5 py-3">
                <span
                  className={`rounded px-2 py-0.5 text-xs font-medium ${
                    req.extract_delivered ? 'bg-green-100 text-green-800' : 'bg-amber-100 text-amber-800'
                  }`}
                >
                  {req.extract_delivered ? t('authority_requests.status_delivered') : t('authority_requests.status_pending')}
                </span>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>

    <p className="flex items-start gap-2 border-t border-gray-200 bg-gray-50 p-4 text-xs text-gray-600">
      <FileText className="mt-0.5 h-4 w-4 shrink-0 text-turquesa-dark" aria-hidden="true" />
      <span>{t('authority_requests.governance_note')}</span>
    </p>
  </section>
);
