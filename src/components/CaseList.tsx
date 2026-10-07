import React, { useDeferredValue, useMemo, useState } from 'react';
import { ChevronRight, Search } from 'lucide-react';
import { t } from '../lib/i18n';
import { CaseWithDetails } from '../types/database';
import { VULNERABILITY_CATALOG } from '../lib/catalogs';
import { useCatalog } from '../lib/catalog';
import { hrefFor } from '../lib/router';

// Lista de expedientes: tarjetas en celular (toda la tarjeta es el enlace), tabla en pantallas
// anchas, filtros que se pueden limpiar y carga progresiva en lugar de pintar todo de golpe.
const PAGE = 30;

type SortKey = 'recent' | 'folio' | 'person';

const personName = (c: CaseWithDetails) => `${c.person.given_name} ${c.person.paternal_family_name}`;

const Badges: React.FC<{ c: CaseWithDetails }> = ({ c }) => (
  <>
    {c.vulnerabilities.some((v) => v.marker_code === 'unaccompanied_child') && (
      <span className="rounded bg-red-100 px-1.5 text-xs font-bold text-red-800">{t('cases.badge_unaccompanied')}</span>
    )}
    {c.parent_case_id && (
      <span className="rounded bg-purple-100 px-1.5 text-xs font-medium text-purple-800">{t('cases.badge_subfolio')}</span>
    )}
    {c.previous_case_id && (
      <span className="rounded bg-blue-100 px-1.5 text-xs font-medium text-blue-800">{t('cases.badge_reentry')}</span>
    )}
  </>
);

const Markers: React.FC<{ c: CaseWithDetails; max?: number }> = ({ c, max = 2 }) => {
  const labels = c.vulnerabilities.map((v) => VULNERABILITY_CATALOG[v.marker_code]?.label ?? v.marker_code);
  if (labels.length === 0) return <span className="text-xs text-gray-500">—</span>;
  return (
    <div className="flex flex-wrap gap-1">
      {labels.slice(0, max).map((l) => (
        <span key={l} className="rounded border border-gray-200 bg-gray-100 px-2 py-0.5 text-xs text-gray-700">{l}</span>
      ))}
      {labels.length > max && (
        <span className="rounded px-1 py-0.5 text-xs font-semibold text-gray-600">
          {t('cases.list.marker_more').replace('{n}', String(labels.length - max))}
        </span>
      )}
    </div>
  );
};

export const CaseList: React.FC<{ cases: CaseWithDetails[]; currentUserId: string }> = ({ cases, currentUserId }) => {
  const { statusValues } = useCatalog();
  const [search, setSearch] = useState('');
  const [stage, setStage] = useState('');
  const [engagement, setEngagement] = useState('');
  const [onlyMarkers, setOnlyMarkers] = useState(false);
  const [onlyMine, setOnlyMine] = useState(false);
  const [sort, setSort] = useState<SortKey>('recent');
  const [limit, setLimit] = useState(PAGE);
  const term = useDeferredValue(search).trim().toLowerCase();

  const filtered = useMemo(() => {
    const list = cases.filter((c) => {
      if (stage && c.statuses.case_stage.valueCode !== stage) return false;
      if (engagement && c.statuses.engagement_status.valueCode !== engagement) return false;
      if (onlyMarkers && c.vulnerabilities.length === 0) return false;
      if (onlyMine && c.assigned_user_id !== currentUserId) return false;
      if (!term) return true;
      return (
        c.case_number.toLowerCase().includes(term) ||
        personName(c).toLowerCase().includes(term) ||
        (c.person.preferred_name ?? '').toLowerCase().includes(term) ||
        (c.person.other_nationality ?? '').toLowerCase().includes(term) ||
        c.vulnerabilities.some((v) => (VULNERABILITY_CATALOG[v.marker_code]?.label ?? '').toLowerCase().includes(term))
      );
    });
    return [...list].sort((a, b) =>
      sort === 'folio'
        ? a.case_number.localeCompare(b.case_number)
        : sort === 'person'
          ? personName(a).localeCompare(personName(b), 'es')
          : b.opened_at.localeCompare(a.opened_at)
    );
  }, [cases, term, stage, engagement, onlyMarkers, onlyMine, sort, currentUserId]);

  const visible = filtered.slice(0, limit);
  const hasFilters = !!(search || stage || engagement || onlyMarkers || onlyMine);
  const clear = () => {
    setSearch('');
    setStage('');
    setEngagement('');
    setOnlyMarkers(false);
    setOnlyMine(false);
    setLimit(PAGE);
  };
  const resetPage = () => setLimit(PAGE);

  const selectCls = 'w-full rounded-lg border border-gray-300 bg-white p-2 text-sm focus:border-turquesa focus:outline-none';

  return (
    <div className="space-y-4">
      <div className="space-y-3 rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
        <div className="relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-500" aria-hidden="true" />
          <label htmlFor="cases-search" className="sr-only">{t('cases.list.search_label')}</label>
          <input
            id="cases-search"
            name="cases-search"
            type="search"
            autoComplete="off"
            value={search}
            onChange={(e) => { setSearch(e.target.value); resetPage(); }}
            placeholder={t('cases.search_placeholder')}
            className="w-full rounded-lg border border-gray-300 py-2 pl-9 pr-3 text-sm focus:border-turquesa focus:outline-none"
          />
        </div>

        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <div>
            <label htmlFor="f-stage" className="mb-1 block text-xs font-medium text-gray-600">{t('cases.list.stage')}</label>
            <select id="f-stage" name="f-stage" value={stage} onChange={(e) => { setStage(e.target.value); resetPage(); }} className={selectCls}>
              <option value="">{t('cases.list.all_f')}</option>
              {statusValues.case_stage.map((v) => <option key={v.id} value={v.code}>{v.label_es}</option>)}
            </select>
          </div>
          <div>
            <label htmlFor="f-eng" className="mb-1 block text-xs font-medium text-gray-600">{t('cases.list.engagement')}</label>
            <select id="f-eng" name="f-eng" value={engagement} onChange={(e) => { setEngagement(e.target.value); resetPage(); }} className={selectCls}>
              <option value="">{t('cases.list.all_f')}</option>
              {statusValues.engagement_status.map((v) => <option key={v.id} value={v.code}>{v.label_es}</option>)}
            </select>
          </div>
          <div className="col-span-2 lg:col-span-1">
            <label htmlFor="f-sort" className="mb-1 block text-xs font-medium text-gray-600">{t('cases.list.sort')}</label>
            <select id="f-sort" name="f-sort" value={sort} onChange={(e) => setSort(e.target.value as SortKey)} className={selectCls}>
              <option value="recent">{t('cases.list.sort_recent')}</option>
              <option value="folio">{t('cases.list.sort_folio')}</option>
              <option value="person">{t('cases.list.sort_person')}</option>
            </select>
          </div>
          <div className="col-span-2 flex flex-wrap items-end gap-x-4 gap-y-2 lg:col-span-1">
            <label className="flex items-center gap-2 text-sm text-carbon">
              <input type="checkbox" checked={onlyMarkers} onChange={(e) => { setOnlyMarkers(e.target.checked); resetPage(); }} className="rounded border-gray-300 text-turquesa" />
              {t('cases.list.only_markers')}
            </label>
            <label className="flex items-center gap-2 text-sm text-carbon">
              <input type="checkbox" checked={onlyMine} onChange={(e) => { setOnlyMine(e.target.checked); resetPage(); }} className="rounded border-gray-300 text-turquesa" />
              {t('cases.list.only_mine')}
            </label>
          </div>
        </div>

        <div className="flex flex-wrap items-center justify-between gap-2">
          <p aria-live="polite" className="font-mono text-xs text-gray-600">
            {t('cases.list.showing').replace('{shown}', String(visible.length)).replace('{total}', String(filtered.length))}
          </p>
          {hasFilters && (
            <button type="button" onClick={clear} className="text-sm font-semibold text-turquesa-dark underline">
              {t('cases.list.clear')}
            </button>
          )}
        </div>
      </div>

      {filtered.length === 0 ? (
        <p className="rounded-xl border border-gray-200 bg-white p-8 text-center text-sm text-gray-600">
          {cases.length === 0 ? t('cases.list.empty') : t('cases.list.no_results')}
        </p>
      ) : (
        <>
          {/* Celular y tableta vertical: tarjetas */}
          <ul className="space-y-3 md:hidden">
            {visible.map((c) => (
              <li key={c.id}>
                <a
                  href={hrefFor('cases', c.case_number)}
                  className="block rounded-xl border border-gray-200 bg-white p-4 shadow-sm active:bg-gray-50"
                >
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <p className="flex flex-wrap items-center gap-1.5">
                        <span className="font-mono text-sm font-bold text-carbon">{c.case_number}</span>
                        <Badges c={c} />
                      </p>
                      <p className="mt-1 text-base font-bold text-carbon">{personName(c)}</p>
                      {c.person.preferred_name && <p className="text-sm italic text-turquesa-dark">“{c.person.preferred_name}”</p>}
                    </div>
                    <ChevronRight className="mt-1 h-5 w-5 shrink-0 text-turquesa-dark" aria-hidden="true" />
                  </div>
                  <p className="mt-2 flex flex-wrap items-center gap-2 text-sm">
                    <span className="rounded-full border border-turquesa/30 bg-claro px-2.5 py-0.5 text-xs font-bold text-turquesa-dark">
                      {c.statuses.engagement_status.label}
                    </span>
                    <span className="text-xs text-gray-600">{c.statuses.case_stage.label}</span>
                  </p>
                  <p className="mt-1 text-xs text-gray-600">
                    {c.person.other_nationality || '—'} · {c.person.other_language || 'Español'}
                  </p>
                  {c.vulnerabilities.length > 0 && <div className="mt-2"><Markers c={c} /></div>}
                </a>
              </li>
            ))}
          </ul>

          {/* Pantallas anchas: tabla */}
          <div className="hidden overflow-hidden rounded-2xl border border-gray-200 bg-white shadow-sm md:block">
            <table className="min-w-full divide-y divide-gray-200 text-sm">
              <thead className="bg-gray-50 text-xs font-semibold uppercase text-gray-600">
                <tr>
                  <th scope="col" className="px-5 py-3 text-left">{t('cases.col_folio')}</th>
                  <th scope="col" className="px-5 py-3 text-left">{t('cases.col_person')}</th>
                  <th scope="col" className="hidden px-5 py-3 text-left lg:table-cell">{t('cases.col_nationality')}</th>
                  <th scope="col" className="px-5 py-3 text-left">{t('cases.col_priority_status')}</th>
                  <th scope="col" className="hidden px-5 py-3 text-left xl:table-cell">{t('cases.col_vulnerabilities')}</th>
                  <th scope="col" className="px-5 py-3 text-right"><span className="sr-only">{t('cases.col_actions')}</span></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {visible.map((c) => (
                  <tr key={c.id} className="hover:bg-gray-50">
                    <td className="whitespace-nowrap px-5 py-3 align-top">
                      <a href={hrefFor('cases', c.case_number)} className="inline-flex min-h-11 items-center font-mono font-bold text-carbon hover:underline">{c.case_number}</a>
                      <div className="mt-1 flex flex-wrap gap-1"><Badges c={c} /></div>
                    </td>
                    <td className="px-5 py-3 align-top">
                      <div className="font-bold text-carbon">{personName(c)}</div>
                      {c.person.preferred_name && <div className="text-xs italic text-turquesa-dark">“{c.person.preferred_name}”</div>}
                    </td>
                    <td className="hidden px-5 py-3 align-top text-gray-700 lg:table-cell">
                      <div>{c.person.other_nationality || '—'}</div>
                      <div className="text-xs text-gray-600">{c.person.other_language || 'Español'}</div>
                    </td>
                    <td className="px-5 py-3 align-top">
                      <span className="inline-block rounded-full border border-turquesa/30 bg-claro px-2.5 py-0.5 text-xs font-bold text-turquesa-dark">
                        {c.statuses.engagement_status.label}
                      </span>
                      <div className="mt-1 text-xs text-gray-600">{c.statuses.case_stage.label}</div>
                    </td>
                    <td className="hidden max-w-xs px-5 py-3 align-top xl:table-cell"><Markers c={c} /></td>
                    <td className="whitespace-nowrap px-5 py-3 text-right align-top">
                      <a
                        href={hrefFor('cases', c.case_number)}
                        className="inline-flex min-h-11 items-center gap-1 rounded-lg border border-gray-200 bg-gray-100 px-3 text-sm font-semibold text-carbon hover:bg-claro"
                      >
                        {t('cases.action_view_detail')}
                        <ChevronRight className="h-4 w-4 text-turquesa-dark" aria-hidden="true" />
                      </a>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {filtered.length > visible.length && (
            <div className="text-center">
              <button
                type="button"
                onClick={() => setLimit((n) => n + PAGE)}
                className="rounded-lg border border-gray-300 bg-white px-5 py-2 text-sm font-semibold text-carbon hover:bg-gray-50"
              >
                {t('cases.list.more').replace('{n}', String(Math.min(PAGE, filtered.length - visible.length)))}
              </button>
            </div>
          )}
        </>
      )}
    </div>
  );
};
