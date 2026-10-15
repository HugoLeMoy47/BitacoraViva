import React, { useMemo, useState } from 'react';
import { Plus, Trash2 } from 'lucide-react';
import { t } from '../lib/i18n';
import { friendlyError } from '../lib/errors';
import { dataApi } from '../lib/data';
import { useCatalog } from '../lib/catalog';
import { useSession } from '../lib/session';
import { useToast } from '../lib/toast';
import { BandRow, keyFromLabel, validateBands } from '../lib/dictionaries';
import { CatalogItem } from '../types/database';
import { Tabs } from './Tabs';
import { DisabledReason, describedBy } from './DisabledReason';

// Diccionarios editables (E14): los administran dirección y Trabajo Social (la base lo exige). Aquí se agregan, se
// renombran y se retiran valores; retirar NO borra: el valor deja de ofrecerse, pero lo ya registrado lo conserva.
// Los grupos por edad se reemplazan completos y lo anterior se cierra con motivo.
type TabId = CatalogItem['catalog'] | 'age_bands';
const TABS: TabId[] = ['service_line', 'specific_need', 'language', 'religion', 'age_bands'];
const SENSITIVE: TabId[] = ['specific_need', 'language', 'religion'];

const INPUT = 'min-h-11 w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-turquesa focus:outline-none';
const BTN = 'inline-flex min-h-11 items-center gap-1.5 rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50';
const BTN_PRIMARY = 'inline-flex min-h-11 items-center gap-1.5 rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon shadow-sm hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50';

export const DictionariesView: React.FC<{ onChanged: () => Promise<void> }> = ({ onChanged }) => {
  const [tab, setTab] = useState<TabId>('service_line');
  return (
    <div className="mx-auto max-w-4xl space-y-5">
      <div>
        <h2 className="font-title text-2xl font-bold text-carbon">{t('dictionaries.title')}</h2>
        <p className="mt-1 text-sm text-gray-600">{t('dictionaries.subtitle')}</p>
      </div>
      <Tabs
        ariaLabel={t('dictionaries.tabs')}
        value={tab}
        onChange={(id) => setTab(id as TabId)}
        items={TABS.map((id) => ({ id, label: t(`dictionaries.tab.${id}`) }))}
      />
      <div className="rounded-2xl border border-gray-200 bg-white p-5">
        {tab === 'age_bands' ? <AgeBandsEditor onChanged={onChanged} /> : <ItemsEditor key={tab} catalog={tab} onChanged={onChanged} />}
        {SENSITIVE.includes(tab) && <p className="mt-4 rounded-lg bg-amber-50 p-3 text-sm text-amber-900">{t('dictionaries.sensitive_note')}</p>}
      </div>
    </div>
  );
};

// ------------------------------------------------------------------ Valores de un diccionario
const ItemsEditor: React.FC<{ catalog: CatalogItem['catalog']; onChanged: () => Promise<void> }> = ({ catalog, onChanged }) => {
  const { catalogItems } = useCatalog();
  const { user } = useSession();
  const toast = useToast();
  const items = useMemo(() => catalogItems.filter((i) => i.catalog === catalog).sort((a, b) => a.sort_order - b.sort_order), [catalogItems, catalog]);
  const [newLabel, setNewLabel] = useState('');
  const [editing, setEditing] = useState<{ id: string; label: string } | null>(null);
  const [busy, setBusy] = useState(false);

  const run = async (action: () => Promise<void>, okKey: string) => {
    setBusy(true);
    try {
      await action();
      toast.success(t(okKey));
      await onChanged();
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      setBusy(false);
    }
  };

  const orgId = user?.profile.organization_id ?? '';
  const exists = (label: string) => items.some((i) => i.label_es.trim().toLowerCase() === label.trim().toLowerCase());
  const addReason = !newLabel.trim() ? t('dictionaries.reason_name') : exists(newLabel) ? t('dictionaries.reason_exists') : null;
  const add = (e: React.FormEvent) => {
    e.preventDefault();
    if (addReason) return;
    const key = keyFromLabel(newLabel, catalogItems.filter((i) => i.catalog === catalog).map((i) => i.key));
    const sort = Math.max(0, ...items.filter((i) => !i.is_system).map((i) => i.sort_order)) + 1;
    run(async () => {
      await dataApi.addCatalogItem(orgId, catalog, key, newLabel, sort);
      setNewLabel('');
    }, 'dictionaries.added');
  };

  return (
    <div>
      <h3 className="text-base font-bold text-carbon">{t(`dictionaries.tab.${catalog}`)}</h3>
      <p className="mt-1 text-sm text-gray-600">{t(`dictionaries.hint.${catalog}`)}</p>
      <ul className="mt-4 divide-y divide-gray-100">
        {items.map((i) => (
          <li key={i.id} className="flex flex-wrap items-center gap-2 py-2">
            {editing?.id === i.id ? (
              <>
                <label className="sr-only" htmlFor={`dic-edit-${i.id}`}>{t('dictionaries.item_name')}</label>
                <input id={`dic-edit-${i.id}`} name={`dic-edit-${i.id}`} autoComplete="off" autoFocus className={`${INPUT} max-w-sm`} value={editing.label} maxLength={80}
                  onChange={(e) => setEditing({ id: i.id, label: e.target.value })} />
                <button type="button" className={BTN_PRIMARY} disabled={busy || !editing.label.trim()}
                  onClick={() => run(async () => { await dataApi.updateCatalogItem(i.id, { label_es: editing.label.trim() }); setEditing(null); }, 'dictionaries.renamed')}>
                  {t('common.save')}
                </button>
                <button type="button" className={BTN} onClick={() => setEditing(null)}>{t('common.cancel')}</button>
              </>
            ) : (
              <>
                <span className={`min-w-0 flex-1 text-sm ${i.is_active ? 'font-semibold text-carbon' : 'text-gray-500 line-through'}`}>{i.label_es}</span>
                {i.is_system && <span className="rounded-md bg-gray-100 px-2 py-0.5 text-xs font-semibold text-gray-700">{t('dictionaries.system')}</span>}
                {!i.is_active && <span className="rounded-md bg-amber-100 px-2 py-0.5 text-xs font-semibold text-amber-800">{t('dictionaries.retired')}</span>}
                <button type="button" className={BTN} disabled={busy} onClick={() => setEditing({ id: i.id, label: i.label_es })}>{t('dictionaries.rename')}</button>
                {!i.is_system && (
                  <button type="button" className={BTN} disabled={busy}
                    onClick={() => run(() => dataApi.updateCatalogItem(i.id, { is_active: !i.is_active }), i.is_active ? 'dictionaries.retired_ok' : 'dictionaries.reactivated')}>
                    {i.is_active ? t('dictionaries.retire') : t('dictionaries.reactivate')}
                  </button>
                )}
              </>
            )}
          </li>
        ))}
        {items.length === 0 && <li className="py-3 text-sm text-gray-600">{t('dictionaries.empty')}</li>}
      </ul>

      <form onSubmit={add} className="mt-5 border-t border-gray-100 pt-4">
        <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor="dic-new">{t('dictionaries.new_value')}</label>
        <div className="flex flex-wrap items-start gap-2">
          <input id="dic-new" name="dic-new" autoComplete="off" className={`${INPUT} max-w-sm`} value={newLabel} maxLength={80} onChange={(e) => setNewLabel(e.target.value)} />
          <button type="submit" className={BTN_PRIMARY} disabled={busy || !!addReason} {...describedBy('dic-new', addReason)}>
            <Plus className="h-4 w-4" aria-hidden="true" />
            {t('dictionaries.add')}
          </button>
        </div>
        <DisabledReason id="dic-new" reason={addReason} className="mt-2" />
      </form>
    </div>
  );
};

// ------------------------------------------------------------------ Grupos por edad
const AgeBandsEditor: React.FC<{ onChanged: () => Promise<void> }> = ({ onChanged }) => {
  const { ageBands } = useCatalog();
  const toast = useToast();
  const initial = (): BandRow[] => ageBands.map((b) => ({ label: b.label_es, minAge: String(b.min_age) }));
  const [rows, setRows] = useState<BandRow[]>(initial);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);

  const hadBands = ageBands.length > 0;
  const changed = JSON.stringify(rows) !== JSON.stringify(initial());
  const problem = validateBands(rows);
  const blocked = !changed
    ? t('dictionaries.bands_no_change')
    : problem
      ? t(problem)
      : hadBands && !reason.trim()
        ? t('dictionaries.bands_need_reason')
        : null;

  const setRow = (i: number, patch: Partial<BandRow>) => setRows((r) => r.map((x, j) => (j === i ? { ...x, ...patch } : x)));

  const save = async (e: React.FormEvent) => {
    e.preventDefault();
    if (blocked) return;
    setBusy(true);
    try {
      await dataApi.setAgeBands(rows.map((r) => ({ label: r.label.trim(), min_age: Number(r.minAge) })), reason);
      toast.success(t('dictionaries.bands_saved'));
      setReason('');
      await onChanged();
    } catch (err) {
      toast.error(friendlyError(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <form onSubmit={save}>
      <h3 className="text-base font-bold text-carbon">{t('dictionaries.tab.age_bands')}</h3>
      <p className="mt-1 text-sm text-gray-600">{t('dictionaries.hint.age_bands')}</p>
      {!hadBands && <p className="mt-3 rounded-lg bg-amber-50 p-3 text-sm text-amber-900">{t('dictionaries.bands_none')}</p>}
      <ul className="mt-4 space-y-2">
        {rows.map((r, i) => (
          <li key={i} className="grid grid-cols-[minmax(0,1fr)_7rem_auto] items-end gap-2">
            <div>
              <label className="mb-1 block text-xs font-semibold text-gray-600" htmlFor={`band-name-${i}`}>{t('dictionaries.band_name')}</label>
              <input id={`band-name-${i}`} name={`band-name-${i}`} autoComplete="off" className={INPUT} value={r.label} maxLength={60} onChange={(e) => setRow(i, { label: e.target.value })} />
            </div>
            <div>
              <label className="mb-1 block text-xs font-semibold text-gray-600" htmlFor={`band-age-${i}`}>{t('dictionaries.band_from')}</label>
              <input id={`band-age-${i}`} name={`band-age-${i}`} autoComplete="off" inputMode="numeric" className={INPUT} value={r.minAge} maxLength={3} onChange={(e) => setRow(i, { minAge: e.target.value })} />
            </div>
            <button type="button" className={BTN} aria-label={t('dictionaries.band_remove').replace('{name}', r.label || String(i + 1))} onClick={() => setRows((x) => x.filter((_, j) => j !== i))}>
              <Trash2 className="h-4 w-4" aria-hidden="true" />
            </button>
          </li>
        ))}
      </ul>
      <button type="button" className={`${BTN} mt-3`} onClick={() => setRows((r) => [...r, { label: '', minAge: '' }])}>
        <Plus className="h-4 w-4" aria-hidden="true" />
        {t('dictionaries.band_add')}
      </button>
      <p className="mt-3 text-sm text-gray-600">{t('dictionaries.bands_explain')}</p>

      {hadBands && (
        <div className="mt-4">
          <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor="bands-reason">{t('dictionaries.bands_reason')}</label>
          <input id="bands-reason" name="bands-reason" autoComplete="off" className={`${INPUT} max-w-lg`} value={reason} maxLength={300} onChange={(e) => setReason(e.target.value)} />
        </div>
      )}
      <div className="mt-4">
        <DisabledReason id="bands" reason={blocked} className="mb-2" />
        <button type="submit" className={BTN_PRIMARY} disabled={busy || !!blocked} {...describedBy('bands', blocked)}>{t('dictionaries.bands_save')}</button>
      </div>
    </form>
  );
};
