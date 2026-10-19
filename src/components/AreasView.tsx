import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { ArrowLeft, ChevronRight, Plus } from 'lucide-react';
import { t } from '../lib/i18n';
import { friendlyError } from '../lib/errors';
import { supabase } from '../lib/supabase';
import { dataApi } from '../lib/data';
import { useToast } from '../lib/toast';
import { peoplePerArea, sortAreas } from '../lib/areas';
import { Area } from '../types/database';
import { ModalShell } from './ModalShell';
import { DisabledReason, describedBy } from './DisabledReason';

// Áreas (E17 fase 3): una tabla con un panel lateral para crear, renombrar, desactivar y reactivar áreas (nunca se borran) y
// elegir cuál es el «área general» (donde escribe en la bitácora quien no tiene área) y cuál se propone al abrir un expediente.
// La regla (permiso de administrar áreas, nombre válido y único, motivo al desactivar, una marca por organización) vive en la base.
const INPUT = 'min-h-11 w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-turquesa focus:outline-none';
const BTN = 'inline-flex min-h-11 items-center gap-1.5 rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50';
const BTN_PRIMARY = 'inline-flex min-h-11 items-center gap-1.5 rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon shadow-sm hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50';
const ALERT = 'rounded-lg border border-alerta-dark/40 bg-alerta-bg/40 p-3 text-sm font-semibold text-alerta-dark';

export const AreasView: React.FC<{ areas: Area[]; onChanged: () => Promise<void> }> = ({ areas, onChanged }) => {
  const toast = useToast();
  const [people, setPeople] = useState<Map<string, number>>(new Map());
  const [creating, setCreating] = useState(false);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [deactivating, setDeactivating] = useState<Area | null>(null);

  const loadPeople = useCallback(async () => {
    const { data } = await supabase.from('user_role').select('user_id, area_id, revoked_at');
    setPeople(peoplePerArea((data ?? []) as { user_id: string; area_id: string | null; revoked_at: string | null }[]));
  }, []);
  useEffect(() => { void loadPeople(); }, [loadPeople]);

  const ordered = useMemo(() => sortAreas(areas), [areas]);
  const selected = areas.find((a) => a.id === selectedId) ?? null;
  const done = async (okKey: string) => { toast.success(t(okKey)); await onChanged(); await loadPeople(); };

  return (
    <div className="mx-auto max-w-6xl space-y-5">
      <div>
        <h2 className="font-title text-2xl font-bold text-carbon">{t('areas.title')}</h2>
        <p className="mt-1 text-sm text-gray-700">{t('areas.subtitle')}</p>
      </div>
      <div>
        <button type="button" className={BTN} aria-expanded={creating} onClick={() => setCreating(!creating)}>
          <Plus className="h-4 w-4" aria-hidden="true" />
          {t('areas.create')}
        </button>
        {creating && <CreateForm onCancel={() => setCreating(false)} onDone={async () => { setCreating(false); await done('areas.created'); }} />}
      </div>

      <div className={`grid gap-5 ${selected ? 'lg:grid-cols-[minmax(0,1fr)_24rem]' : ''}`}>
        <div className={`min-w-0 space-y-2 ${selected ? 'hidden lg:block' : ''}`}>
          <p className="text-sm text-gray-700" aria-live="polite">{t('areas.count').replace('{n}', String(areas.length))}</p>
          <div className="hidden overflow-hidden rounded-2xl border border-gray-200 bg-white md:block">
            <table className="w-full text-left text-sm">
              <caption className="sr-only">{t('areas.title')}</caption>
              <thead className="border-b border-gray-200 bg-gray-50 text-xs font-bold uppercase tracking-wide text-gray-700">
                <tr>
                  <th scope="col" className="px-4 py-3">{t('areas.col_name')}</th>
                  <th scope="col" className="px-4 py-3">{t('areas.col_people')}</th>
                  <th scope="col" className="px-4 py-3">{t('areas.col_status')}</th>
                  <th scope="col" className="px-4 py-3">{t('areas.col_marks')}</th>
                  <th scope="col" className="w-10 px-2 py-3"><span className="sr-only">{t('team.col_open')}</span></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {ordered.map((a) => (
                  <tr key={a.id} className={selectedId === a.id ? 'bg-claro/60' : 'hover:bg-gray-50'}>
                    <td className="px-4 py-3">
                      <button type="button" className="min-h-11 text-left font-bold text-carbon" aria-current={selectedId === a.id} onClick={() => setSelectedId(a.id)}>{a.name}</button>
                    </td>
                    <td className="px-4 py-3 text-carbon">{people.get(a.id) ?? 0}</td>
                    <td className="px-4 py-3"><StatusBadge active={a.active} /></td>
                    <td className="px-4 py-3"><Marks area={a} /></td>
                    <td className="px-2 py-3 text-gray-700"><ChevronRight className="h-4 w-4" aria-hidden="true" /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <ul className="space-y-2 md:hidden">
            {ordered.map((a) => (
              <li key={a.id} className="rounded-2xl border border-gray-200 bg-white p-4">
                <button type="button" className="block min-h-11 w-full text-left" onClick={() => setSelectedId(a.id)}>
                  <span className="flex flex-wrap items-center justify-between gap-2">
                    <span className="font-bold text-carbon">{a.name}</span>
                    <StatusBadge active={a.active} />
                  </span>
                  <span className="block text-sm text-gray-700">{t('areas.people_count').replace('{n}', String(people.get(a.id) ?? 0))}</span>
                </button>
                <div className="mt-2"><Marks area={a} /></div>
              </li>
            ))}
          </ul>
        </div>

        {selected && (
          <AreaPanel
            key={selected.id}
            area={selected}
            people={people.get(selected.id) ?? 0}
            onClose={() => setSelectedId(null)}
            onDeactivate={() => setDeactivating(selected)}
            done={done}
          />
        )}
      </div>

      {deactivating && (
        <DeactivateModal
          area={deactivating}
          people={people.get(deactivating.id) ?? 0}
          onSubmit={async (reason) => { await dataApi.setAreaActive(deactivating.id, false, reason); await done('areas.deactivated'); }}
          onClose={() => setDeactivating(null)}
        />
      )}
    </div>
  );
};

const StatusBadge: React.FC<{ active: boolean }> = ({ active }) => (
  <span className={`inline-block whitespace-nowrap rounded-md px-2.5 py-1 text-xs font-bold ${active ? 'bg-green-100 text-green-800' : 'bg-amber-100 text-amber-800'}`}>
    {t(active ? 'areas.status_active' : 'areas.status_inactive')}
  </span>
);

const Marks: React.FC<{ area: Area }> = ({ area }) => {
  if (!area.is_general && !area.is_default_intake) return <span className="text-sm text-gray-700">—</span>;
  return (
    <ul className="flex flex-wrap gap-1.5">
      {area.is_general && <li className="rounded-md bg-claro px-2 py-0.5 text-xs font-semibold text-carbon">{t('areas.mark_general')}</li>}
      {area.is_default_intake && <li className="rounded-md bg-claro px-2 py-0.5 text-xs font-semibold text-carbon">{t('areas.mark_default')}</li>}
    </ul>
  );
};

const AreaPanel: React.FC<{
  area: Area; people: number; onClose: () => void; onDeactivate: () => void; done: (okKey: string) => Promise<void>;
}> = ({ area, people, onClose, onDeactivate, done }) => {
  const uid = React.useId();
  const [name, setName] = useState(area.name);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const trimmed = name.trim();
  const renameBlocked = trimmed === '' ? t('areas.reason_name') : trimmed === area.name ? t('areas.reason_same') : null;
  const marked = area.is_general || area.is_default_intake;

  const run = async (key: string, fn: () => Promise<unknown>, okKey: string) => {
    setBusy(key);
    setError(null);
    try {
      await fn();
      await done(okKey);
    } catch (e) {
      setError(friendlyError(e));
    } finally {
      setBusy(null);
    }
  };

  return (
    <aside aria-label={area.name} className="min-w-0 space-y-5 rounded-2xl border border-gray-200 bg-white p-5">
      <button type="button" className={`${BTN} lg:hidden`} onClick={onClose}>
        <ArrowLeft className="h-4 w-4" aria-hidden="true" />
        {t('areas.back_to_list')}
      </button>
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <h3 className="break-words text-lg font-bold text-carbon">{area.name}</h3>
          <p className="text-sm text-gray-700">{t('areas.people_count').replace('{n}', String(people))}</p>
        </div>
        <StatusBadge active={area.active} />
      </div>
      <button type="button" className={`${BTN} hidden lg:inline-flex`} onClick={onClose}>{t('areas.close_panel')}</button>
      {error && <p role="alert" className={ALERT}>{error}</p>}

      <form
        className="space-y-2"
        onSubmit={(e) => { e.preventDefault(); if (!renameBlocked) void run('rename', () => dataApi.renameArea(area.id, trimmed), 'areas.renamed'); }}
      >
        <label className="block text-sm font-semibold text-gray-700" htmlFor={`${uid}-n`}>{t('areas.rename_label')}</label>
        <input id={`${uid}-n`} name={`${uid}-n`} autoComplete="off" className={INPUT} maxLength={80} value={name} onChange={(e) => setName(e.target.value)} />
        <DisabledReason id={`${uid}-rn`} reason={renameBlocked} />
        <button type="submit" className={BTN_PRIMARY} disabled={!!renameBlocked || busy === 'rename'} {...describedBy(`${uid}-rn`, renameBlocked)}>
          {busy === 'rename' ? t('case_extra.saving') : t('areas.rename_submit')}
        </button>
      </form>

      <section className="space-y-3">
        <h4 className="text-sm font-bold text-carbon">{t('areas.marks_title')}</h4>
        <div className="space-y-1">
          <p className="text-sm text-gray-700">{t('areas.general_hint')}</p>
          {area.is_general
            ? <p className="text-sm font-semibold text-carbon">{t('areas.is_general_now')}</p>
            : <button type="button" className={BTN} disabled={!area.active || busy === 'general'} onClick={() => run('general', () => dataApi.setDefaultArea('general', area.id), 'areas.mark_saved')}>{t('areas.set_general')}</button>}
        </div>
        <div className="space-y-1">
          <p className="text-sm text-gray-700">{t('areas.default_hint')}</p>
          {area.is_default_intake
            ? <p className="text-sm font-semibold text-carbon">{t('areas.is_default_now')}</p>
            : <button type="button" className={BTN} disabled={!area.active || busy === 'default'} onClick={() => run('default', () => dataApi.setDefaultArea('default_intake', area.id), 'areas.mark_saved')}>{t('areas.set_default')}</button>}
        </div>
        {!area.active && <p className="text-sm text-gray-700">{t('areas.marks_inactive')}</p>}
      </section>

      <div className="space-y-2 border-t border-gray-100 pt-4">
        {area.active ? (
          <>
            <button type="button" className={BTN} disabled={marked} aria-describedby={marked ? `${uid}-marked` : undefined} onClick={onDeactivate}>{t('areas.deactivate')}</button>
            {marked && <p id={`${uid}-marked`} className="text-sm text-gray-700">{t('areas.cannot_deactivate_marked')}</p>}
          </>
        ) : (
          <button type="button" className={BTN} disabled={busy === 'react'} onClick={() => run('react', () => dataApi.setAreaActive(area.id, true), 'areas.reactivated')}>{t('areas.reactivate')}</button>
        )}
      </div>
    </aside>
  );
};

const CreateForm: React.FC<{ onDone: () => Promise<void>; onCancel: () => void }> = ({ onDone, onCancel }) => {
  const uid = React.useId();
  const [name, setName] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const blocked = name.trim() === '' ? t('areas.reason_name') : null;
  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (blocked || busy) return;
    setBusy(true);
    setError(null);
    try {
      await dataApi.createArea(name.trim());
      await onDone();
    } catch (err) {
      setError(friendlyError(err));
      setBusy(false);
    }
  };
  return (
    <form onSubmit={submit} className="mt-3 space-y-3 rounded-xl border border-gray-200 bg-gray-50 p-4">
      <div>
        <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-n`}>{t('areas.field_name')}</label>
        <input id={`${uid}-n`} name={`${uid}-n`} autoComplete="off" className={INPUT} maxLength={80} value={name} onChange={(e) => setName(e.target.value)} />
      </div>
      {error && <p role="alert" className={ALERT}>{error}</p>}
      <DisabledReason id={uid} reason={blocked} />
      <div className="flex flex-wrap gap-2">
        <button type="submit" className={BTN_PRIMARY} disabled={!!blocked || busy} {...describedBy(uid, blocked)}>{busy ? t('case_extra.saving') : t('areas.create_submit')}</button>
        <button type="button" className={BTN} onClick={onCancel}>{t('common.cancel')}</button>
      </div>
    </form>
  );
};

const DeactivateModal: React.FC<{ area: Area; people: number; onSubmit: (reason: string) => Promise<void>; onClose: () => void }> = ({ area, people, onSubmit, onClose }) => {
  const uid = React.useId();
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const blocked = reason.trim() === '' ? t('team.reason_missing') : null;
  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (blocked || busy) return;
    setBusy(true);
    setError(null);
    try {
      await onSubmit(reason.trim());
      onClose();
    } catch (err) {
      setError(friendlyError(err));
      setBusy(false);
    }
  };
  return (
    <ModalShell onClose={onClose} className="fixed inset-0 z-50 flex items-center justify-center bg-carbon/60 p-4 backdrop-blur-sm">
      <form onSubmit={submit} className="w-full max-w-md space-y-4 rounded-xl bg-white p-6 shadow-2xl">
        <h3 className="font-title text-base font-bold text-carbon">{t('areas.deactivate_title').replace('{name}', area.name)}</h3>
        <p className="text-sm text-gray-700">{t('areas.deactivate_hint').replace('{n}', String(people))}</p>
        <div>
          <label className="block text-sm font-semibold text-gray-800" htmlFor={`${uid}-r`}>{t('case_extra.reason_label')}</label>
          <input id={`${uid}-r`} name={`${uid}-r`} autoComplete="off" autoFocus className={INPUT} maxLength={300} value={reason} onChange={(e) => setReason(e.target.value)} />
        </div>
        {error && <p role="alert" className={ALERT}>{error}</p>}
        <DisabledReason id={uid} reason={blocked} />
        <div className="flex items-center justify-end gap-3">
          <button type="button" className={BTN} onClick={onClose}>{t('common.cancel')}</button>
          <button type="submit" className={BTN_PRIMARY} disabled={!!blocked || busy} {...describedBy(uid, blocked)}>{busy ? t('case_extra.saving') : t('areas.deactivate')}</button>
        </div>
      </form>
    </ModalShell>
  );
};
