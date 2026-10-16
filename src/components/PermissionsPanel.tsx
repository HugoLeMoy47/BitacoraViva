import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Plus } from 'lucide-react';
import { t } from '../lib/i18n';
import { friendlyError } from '../lib/errors';
import { supabase } from '../lib/supabase';
import { dataApi } from '../lib/data';
import { useCatalog } from '../lib/catalog';
import { useToast } from '../lib/toast';
import { formatDate } from '../lib/format';
import { ROLE_NAMES } from '../lib/navigation';
import { ModalShell } from './ModalShell';
import { DisabledReason, describedBy } from './DisabledReason';

// Permisos (E16 fase B): qué puede hacer cada ROL y cada ÁREA. Un permiso («capacidad») se concede a un rol o a un área; un área
// vale para quien tiene un rol operativo (dirección, ingreso o atención) en ella. Solo la dirección cambia permisos (para que
// delegar la gestión del equipo no permita escalar privilegios). Quitar un permiso pide motivo y queda en el historial.
// Lo que no está en esta lista (la deuda D-24) sigue por nombre de rol: no es configurable todavía.
const INPUT = 'min-h-11 w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-turquesa focus:outline-none';
const BTN = 'inline-flex min-h-11 items-center gap-1.5 rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50';
const BTN_PRIMARY = 'inline-flex min-h-11 items-center gap-1.5 rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon shadow-sm hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50';

interface Capability { code: string; description_es: string; sort_order: number }
interface Grant {
  id: string;
  capability_code: string;
  role_name: string | null;
  area_id: string | null;
  granted_at: string;
  grant_reason: string | null;
  revoked_at: string | null;
  revoke_reason: string | null;
}

export const PermissionsPanel: React.FC = () => {
  const { areas } = useCatalog();
  const toast = useToast();
  const [caps, setCaps] = useState<Capability[] | null>(null);
  const [grants, setGrants] = useState<Grant[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [adding, setAdding] = useState<string | null>(null);
  const [revoking, setRevoking] = useState<Grant | null>(null);

  const load = useCallback(async () => {
    try {
      const [c, g] = await Promise.all([
        supabase.from('capability').select('code, description_es, sort_order').order('sort_order'),
        supabase.from('capability_grant').select('id, capability_code, role_name, area_id, granted_at, grant_reason, revoked_at, revoke_reason'),
      ]);
      if (c.error) throw c.error;
      if (g.error) throw g.error;
      setCaps((c.data ?? []) as Capability[]);
      setGrants((g.data ?? []) as Grant[]);
      setLoadError(null);
    } catch (e) {
      setLoadError(friendlyError(e));
    }
  }, []);
  useEffect(() => { void load(); }, [load]);

  const subject = (g: Grant) => (g.role_name ? `${t('permissions.role')}: ${t(`roles.${g.role_name}.title`)}` : `${t('permissions.area')}: ${areas.find((a) => a.id === g.area_id)?.name ?? '—'}`);

  return (
    <div className="space-y-4">
      <p className="text-sm text-gray-600">{t('permissions.subtitle')}</p>
      <p className="text-sm text-gray-600">{t('permissions.only_direction')}</p>
      {loadError && <p role="alert" className="rounded-lg border border-alerta-dark/40 bg-alerta-bg/40 p-3 text-sm font-semibold text-alerta-dark">{loadError}</p>}
      {!caps && !loadError && <p className="text-sm text-gray-600">{t('team.loading')}</p>}
      <ul className="space-y-4">
        {(caps ?? []).map((c) => {
          const active = grants.filter((g) => g.capability_code === c.code && !g.revoked_at);
          const history = grants.filter((g) => g.capability_code === c.code && g.revoked_at);
          return (
            <li key={c.code} className="rounded-2xl border border-gray-200 bg-white p-5">
              <h3 className="text-base font-bold text-carbon">{c.description_es}</h3>
              {active.length === 0 ? (
                <p className="mt-2 text-sm text-gray-700">{t('permissions.none_default')}</p>
              ) : (
                <ul className="mt-2 divide-y divide-gray-100">
                  {active.map((g) => (
                    <li key={g.id} className="flex flex-wrap items-center gap-2 py-2">
                      <span className="min-w-0 flex-1 text-sm text-carbon">
                        <span className="font-semibold">{subject(g)}</span>
                        <span className="text-gray-600"> · {t('team.since')} {formatDate(g.granted_at)}</span>
                        {g.grant_reason && <span className="block text-xs text-gray-600">{g.grant_reason}</span>}
                      </span>
                      <button type="button" className={BTN} onClick={() => setRevoking(g)}>{t('permissions.remove')}</button>
                    </li>
                  ))}
                </ul>
              )}
              <div className="mt-3">
                <button type="button" className={BTN} aria-expanded={adding === c.code} onClick={() => setAdding(adding === c.code ? null : c.code)}>
                  <Plus className="h-4 w-4" aria-hidden="true" />
                  {t('permissions.grant')}
                </button>
              </div>
              {adding === c.code && <GrantForm capability={c.code} onCancel={() => setAdding(null)} onDone={async () => { setAdding(null); toast.success(t('permissions.granted')); await load(); }} />}
              {history.length > 0 && (
                <details className="mt-3 text-sm text-gray-700">
                  <summary className="cursor-pointer font-semibold">{t('team.history')} ({history.length})</summary>
                  <ul className="mt-2 space-y-1.5">
                    {history.map((g) => (
                      <li key={g.id}>
                        <span className="font-semibold">{subject(g)}</span> · {formatDate(g.granted_at)} → {formatDate(g.revoked_at as string)}
                        {g.revoke_reason && <span className="text-gray-600"> · {g.revoke_reason}</span>}
                      </li>
                    ))}
                  </ul>
                </details>
              )}
            </li>
          );
        })}
      </ul>
      <p className="text-sm text-gray-600">{t('permissions.debt_note')}</p>

      {revoking && (
        <RevokeModal
          title={t('permissions.remove_title')}
          hint={subject(revoking)}
          onSubmit={async (reason) => { await dataApi.revokeCapability(revoking.id, reason); toast.success(t('permissions.removed')); await load(); }}
          onClose={() => setRevoking(null)}
        />
      )}
    </div>
  );
};

const GrantForm: React.FC<{ capability: string; onDone: () => Promise<void>; onCancel: () => void }> = ({ capability, onDone, onCancel }) => {
  const uid = React.useId();
  const { areas } = useCatalog();
  const [kind, setKind] = useState<'role' | 'area'>('role');
  const [value, setValue] = useState('');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const activeAreas = useMemo(() => areas.filter((a) => a.active), [areas]);
  const blocked = value === '' ? t(kind === 'role' ? 'permissions.reason_role' : 'permissions.reason_area') : null;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (blocked || busy) return;
    setBusy(true);
    setError(null);
    try {
      await dataApi.grantCapability(capability, kind === 'role' ? value : null, kind === 'area' ? value : null, reason);
      await onDone();
    } catch (err) {
      setError(friendlyError(err));
      setBusy(false);
    }
  };

  return (
    <form onSubmit={submit} className="mt-3 space-y-3 rounded-xl border border-gray-200 bg-gray-50 p-4">
      <fieldset>
        <legend className="mb-1 text-sm font-semibold text-gray-700">{t('permissions.grant_to')}</legend>
        <div className="flex flex-wrap gap-5">
          {(['role', 'area'] as const).map((k) => (
            <label key={k} className="flex min-h-11 items-center gap-2 text-sm text-carbon">
              <input type="radio" name={`${uid}-k`} checked={kind === k} onChange={() => { setKind(k); setValue(''); }} />
              {t(`permissions.kind_${k}`)}
            </label>
          ))}
        </div>
      </fieldset>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <div>
          <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-v`}>{t(kind === 'role' ? 'team.field_role' : 'team.field_area')}</label>
          <select id={`${uid}-v`} name={`${uid}-v`} autoComplete="off" className={INPUT} value={value} onChange={(e) => setValue(e.target.value)}>
            <option value="">{t(kind === 'role' ? 'team.choose_role' : 'permissions.choose_area')}</option>
            {kind === 'role'
              ? ROLE_NAMES.map((r) => <option key={r} value={r}>{t(`roles.${r}.title`)}</option>)
              : activeAreas.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
          </select>
        </div>
        <div>
          <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-m`}>{t('team.field_reason_optional')}</label>
          <input id={`${uid}-m`} name={`${uid}-m`} autoComplete="off" className={INPUT} maxLength={300} value={reason} onChange={(e) => setReason(e.target.value)} />
        </div>
      </div>
      {kind === 'area' && <p className="text-sm text-gray-700">{t('permissions.area_note')}</p>}
      {error && <p role="alert" className="rounded-lg border border-alerta-dark/40 bg-alerta-bg/40 p-3 text-sm font-semibold text-alerta-dark">{error}</p>}
      <DisabledReason id={uid} reason={blocked} />
      <div className="flex flex-wrap gap-2">
        <button type="submit" className={BTN_PRIMARY} disabled={!!blocked || busy} {...describedBy(uid, blocked)}>{busy ? t('case_extra.saving') : t('permissions.grant_submit')}</button>
        <button type="button" className={BTN} onClick={onCancel}>{t('common.cancel')}</button>
      </div>
    </form>
  );
};

const RevokeModal: React.FC<{ title: string; hint: string; onSubmit: (reason: string) => Promise<void>; onClose: () => void }> = ({ title, hint, onSubmit, onClose }) => {
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
        <h3 className="font-title text-base font-bold text-carbon">{title}</h3>
        <p className="text-sm text-gray-700">{hint}</p>
        <div>
          <label className="block text-sm font-semibold text-gray-800" htmlFor={`${uid}-r`}>{t('case_extra.reason_label')}</label>
          <input id={`${uid}-r`} name={`${uid}-r`} autoComplete="off" autoFocus className={INPUT} maxLength={300} value={reason} onChange={(e) => setReason(e.target.value)} />
        </div>
        {error && <p role="alert" className="rounded-lg border border-alerta-dark/40 bg-alerta-bg/40 p-3 text-sm font-semibold text-alerta-dark">{error}</p>}
        <DisabledReason id={uid} reason={blocked} />
        <div className="flex items-center justify-end gap-3">
          <button type="button" className={BTN} onClick={onClose}>{t('common.cancel')}</button>
          <button type="submit" className={BTN_PRIMARY} disabled={!!blocked || busy} {...describedBy(uid, blocked)}>{busy ? t('case_extra.saving') : t('permissions.remove')}</button>
        </div>
      </form>
    </ModalShell>
  );
};
