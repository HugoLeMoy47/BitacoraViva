import React from 'react';
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

export const AuditView: React.FC<{ events: AuditEvent[] }> = ({ events }) => (
  <section className="overflow-hidden rounded-xl border border-gray-200 bg-white shadow-sm">
    <div className="flex flex-wrap items-center justify-between gap-2 border-b border-gray-200 px-5 py-4">
      <div>
        <h2 className="text-base font-bold text-carbon">{t('dashboard.audit_title')}</h2>
        <p className="text-xs text-gray-500">{t('audit.subtitle')}</p>
      </div>
      <span className="rounded border border-turquesa/30 bg-claro px-2 py-1 font-mono text-xs text-carbon">
        {t('audit.count').replace('{n}', String(events.length))}
      </span>
    </div>
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-gray-200 text-xs">
        <thead className="bg-gray-50 font-medium uppercase text-gray-500">
          <tr>
            <th scope="col" className="px-5 py-3 text-left">{t('dashboard.table_column_action')}</th>
            <th scope="col" className="px-5 py-3 text-left">{t('dashboard.table_column_table')}</th>
            <th scope="col" className="px-5 py-3 text-left">{t('dashboard.table_column_record')}</th>
            <th scope="col" className="px-5 py-3 text-left">{t('dashboard.table_column_timestamp')}</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-100 bg-white">
          {events.map((event) => (
            <tr key={event.id} className="font-mono hover:bg-gray-50">
              <td className="whitespace-nowrap px-5 py-3">
                <span className="rounded border border-gray-300 bg-gray-100 px-2 py-0.5 text-xs font-bold text-carbon">
                  {event.action}
                </span>
              </td>
              <td className="px-5 py-3 font-semibold text-carbon">{event.table_name}</td>
              <td className="max-w-xs truncate px-5 py-3 text-gray-500" title={event.record_id ?? ''}>{event.record_id}</td>
              <td className="whitespace-nowrap px-5 py-3 text-gray-500">{formatDateTime(event.created_at)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  </section>
);

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
