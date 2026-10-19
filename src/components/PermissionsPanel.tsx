import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Lock, X } from 'lucide-react';
import { t } from '../lib/i18n';
import { friendlyError } from '../lib/errors';
import { supabase } from '../lib/supabase';
import { dataApi } from '../lib/data';
import { useCatalog } from '../lib/catalog';
import { useToast } from '../lib/toast';
import { formatDate } from '../lib/format';
import { ROLE_NAMES } from '../lib/navigation';
import { areaGrants, groupCapabilities, historyEntries, roleGrant, PermissionCapability, PermissionGrant } from '../lib/permissions';
import { ModalShell } from './ModalShell';
import { DisabledReason, describedBy } from './DisabledReason';

// Permisos (E16 fase B, cuadrícula en E17 fase 2): qué puede hacer cada ROL, en una cuadrícula permisos × roles agrupada por
// tema. Marcar una casilla da el permiso al rol; desmarcarla lo quita (pide motivo y queda en el historial). Las EXCEPCIONES POR
// ÁREA dan un permiso solo a quienes trabajan en un área (un área vale para quien tiene un rol operativo en ella). Dirección
// aparece fija con candado: conserva todos los permisos para que la organización nunca se quede sin quien administre. Solo la
// dirección cambia permisos (para que delegar la gestión del equipo no permita escalar privilegios). Lo que no está aquí son
// garantías del producto y no se configuran.
const INPUT = 'min-h-11 w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-turquesa focus:outline-none';
const BTN = 'inline-flex min-h-11 items-center gap-1.5 rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50';
const BTN_PRIMARY = 'inline-flex min-h-11 items-center gap-1.5 rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon shadow-sm hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50';
const ALERT = 'rounded-lg border border-alerta-dark/40 bg-alerta-bg/40 p-3 text-sm font-semibold text-alerta-dark';
const GUARANTEES = ['anonymize', 'arco', 'inbox', 'journal', 'close', 'read', 'permissions'] as const;

export const PermissionsPanel: React.FC = () => {
  const { areas } = useCatalog();
  const toast = useToast();
  const [caps, setCaps] = useState<PermissionCapability[] | null>(null);
  const [grants, setGrants] = useState<PermissionGrant[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [revoking, setRevoking] = useState<{ grant: PermissionGrant; label: string } | null>(null);

  const load = useCallback(async () => {
    try {
      const [c, g] = await Promise.all([
        supabase.from('capability').select('code, description_es, sort_order').order('sort_order'),
        supabase.from('capability_grant').select('id, capability_code, role_name, area_id, granted_at, grant_reason, revoked_at, revoke_reason'),
      ]);
      if (c.error) throw c.error;
      if (g.error) throw g.error;
      setCaps((c.data ?? []) as PermissionCapability[]);
      setGrants((g.data ?? []) as PermissionGrant[]);
      setLoadError(null);
    } catch (e) {
      setLoadError(friendlyError(e));
    }
  }, []);
  useEffect(() => { void load(); }, [load]);

  const groups = useMemo(() => groupCapabilities(caps ?? []), [caps]);
  const activeAreas = useMemo(() => areas.filter((a) => a.active), [areas]);
  const areaName = (id: string | null) => areas.find((a) => a.id === id)?.name ?? '—';
  const capLabel = (code: string) => caps?.find((c) => c.code === code)?.description_es ?? code;
  const subject = (g: PermissionGrant) => (g.role_name ? t(`roles.${g.role_name}.title`) : areaName(g.area_id));

  // Marcar una casilla concede al instante; desmarcarla pide el motivo
  const toggleRole = async (code: string, role: string) => {
    setError(null);
    const current = roleGrant(grants, code, role);
    if (current) {
      setRevoking({ grant: current, label: `${capLabel(code)} · ${t(`roles.${role}.title`)}` });
      return;
    }
    setBusy(`${code}:${role}`);
    try {
      await dataApi.grantCapability(code, role, null, undefined);
      toast.success(t('permissions.granted'));
      await load();
    } catch (e) {
      setError(friendlyError(e));
    } finally {
      setBusy(null);
    }
  };

  const addArea = async (code: string, areaId: string) => {
    if (!areaId) return;
    setError(null);
    setBusy(`${code}:area`);
    try {
      await dataApi.grantCapability(code, null, areaId, undefined);
      toast.success(t('permissions.granted'));
      await load();
    } catch (e) {
      setError(friendlyError(e));
    } finally {
      setBusy(null);
    }
  };

  // Función (no componente): así el selector no se vuelve a montar —y pierde el foco— en cada cambio
  const areaExceptions = (code: string) => {
    const mine = areaGrants(grants, code);
    const free = activeAreas.filter((a) => !mine.some((g) => g.area_id === a.id));
    return (
      <div className="space-y-2">
        {mine.length > 0 && (
          <ul className="flex flex-wrap gap-1.5">
            {mine.map((g) => (
              <li key={g.id} className="inline-flex items-center gap-1 rounded-md bg-claro py-0.5 pl-2 text-xs font-semibold text-carbon">
                {areaName(g.area_id)}
                <button type="button" className="inline-flex min-h-11 min-w-11 items-center justify-center rounded-md hover:bg-white" aria-label={t('permissions.remove_area').replace('{area}', areaName(g.area_id)).replace('{permission}', capLabel(code))}
                  onClick={() => setRevoking({ grant: g, label: `${capLabel(code)} · ${areaName(g.area_id)}` })}>
                  <X className="h-3.5 w-3.5" aria-hidden="true" />
                </button>
              </li>
            ))}
          </ul>
        )}
        {free.length > 0 && (
          <select className={INPUT} value="" disabled={busy === `${code}:area`} aria-label={t('permissions.area_add_label').replace('{permission}', capLabel(code))}
            onChange={(e) => void addArea(code, e.target.value)}>
            <option value="">{t('permissions.area_add')}</option>
            {free.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
          </select>
        )}
      </div>
    );
  };

  const history = historyEntries(grants, 30);

  return (
    <div className="space-y-5">
      <p className="text-sm text-gray-700">{t('permissions.subtitle')}</p>
      <p className="text-sm text-gray-700">{t('permissions.only_direction')}</p>
      {loadError && <p role="alert" className={ALERT}>{loadError}</p>}
      {error && <p role="alert" className={ALERT}>{error}</p>}
      {!caps && !loadError && <p className="text-sm text-gray-700">{t('team.loading')}</p>}

      {groups.map((group) => (
        <section key={group.id} aria-labelledby={`perm-${group.id}`} className="space-y-2">
          <h3 id={`perm-${group.id}`} className="text-sm font-bold uppercase tracking-wide text-gray-700">{t(`permissions.group_${group.id}`)}</h3>

          {/* Cuadrícula (pantalla ancha) */}
          <div className="hidden overflow-hidden rounded-2xl border border-gray-200 bg-white md:block">
            <table className="w-full text-left text-sm">
              <caption className="sr-only">{t(`permissions.group_${group.id}`)}</caption>
              <thead className="border-b border-gray-200 bg-gray-50 text-xs font-bold text-gray-700">
                <tr>
                  <th scope="col" className="px-4 py-3">{t('permissions.col_permission')}</th>
                  {ROLE_NAMES.map((r) => (
                    <th key={r} scope="col" className="px-2 py-3 text-center">
                      {t(`permissions.role_short.${r}`)}
                      {r === 'director' && <Lock className="mx-auto mt-0.5 h-3.5 w-3.5 text-gray-700" aria-label={t('permissions.locked_label')} />}
                    </th>
                  ))}
                  <th scope="col" className="px-4 py-3">{t('permissions.col_areas')}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {group.caps.map((c) => (
                  <tr key={c.code} className="align-top">
                    <th scope="row" className="px-4 py-3 font-semibold text-carbon">{c.description_es}</th>
                    {ROLE_NAMES.map((r) => {
                      const on = !!roleGrant(grants, c.code, r);
                      const locked = r === 'director';
                      return (
                        <td key={r} className="px-2 py-1 text-center">
                          <label className="inline-flex min-h-11 min-w-11 items-center justify-center">
                            <input type="checkbox" className="h-5 w-5 accent-turquesa" checked={on} disabled={locked || busy === `${c.code}:${r}`}
                              aria-label={t('permissions.check_label').replace('{permission}', c.description_es).replace('{role}', t(`roles.${r}.title`))}
                              onChange={() => void toggleRole(c.code, r)} />
                          </label>
                        </td>
                      );
                    })}
                    <td className="px-4 py-2">{areaExceptions(c.code)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Lista por permiso (pantalla chica) */}
          <ul className="space-y-3 md:hidden">
            {group.caps.map((c) => (
              <li key={c.code} className="rounded-2xl border border-gray-200 bg-white p-4">
                <fieldset>
                  <legend className="text-sm font-bold text-carbon">{c.description_es}</legend>
                  <div className="mt-1 divide-y divide-gray-100">
                    {ROLE_NAMES.map((r) => (
                      <label key={r} className="flex min-h-11 items-center gap-3 text-sm text-carbon">
                        <input type="checkbox" className="h-5 w-5 accent-turquesa" checked={!!roleGrant(grants, c.code, r)} disabled={r === 'director' || busy === `${c.code}:${r}`}
                          onChange={() => void toggleRole(c.code, r)} />
                        {t(`roles.${r}.title`)}
                        {r === 'director' && <Lock className="h-3.5 w-3.5 text-gray-700" aria-label={t('permissions.locked_label')} />}
                      </label>
                    ))}
                  </div>
                </fieldset>
                <p className="mb-1 mt-2 text-sm font-semibold text-gray-700">{t('permissions.col_areas')}</p>
                {areaExceptions(c.code)}
              </li>
            ))}
          </ul>
        </section>
      ))}

      <p className="text-sm text-gray-700">{t('permissions.locked_note')}</p>
      <p className="text-sm text-gray-700">{t('permissions.area_note')}</p>

      <details className="rounded-2xl border border-gray-200 bg-white p-5 text-sm text-gray-700">
        <summary className="cursor-pointer font-semibold text-carbon">{t('permissions.guarantees_title')}</summary>
        <p className="mt-2">{t('permissions.guarantees_intro')}</p>
        <ul className="mt-2 list-disc space-y-1 pl-5">
          {GUARANTEES.map((g) => <li key={g}>{t(`permissions.guarantee.${g}`)}</li>)}
        </ul>
      </details>

      {history.length > 0 && (
        <details className="rounded-2xl border border-gray-200 bg-white p-5 text-sm text-gray-700">
          <summary className="cursor-pointer font-semibold text-carbon">{t('permissions.history_title')} ({history.length})</summary>
          <ul className="mt-2 space-y-1.5">
            {history.map((g) => (
              <li key={g.id}>
                <span className="font-semibold">{capLabel(g.capability_code)}</span> · {subject(g)} · {formatDate(g.granted_at)} → {formatDate(g.revoked_at as string)}
                {g.revoke_reason && <span className="text-gray-700"> · {g.revoke_reason}</span>}
              </li>
            ))}
          </ul>
        </details>
      )}

      {revoking && (
        <RevokeModal
          title={t('permissions.remove_title')}
          hint={revoking.label}
          onSubmit={async (reason) => { await dataApi.revokeCapability(revoking.grant.id, reason); toast.success(t('permissions.removed')); await load(); }}
          onClose={() => setRevoking(null)}
        />
      )}
    </div>
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
        {error && <p role="alert" className={ALERT}>{error}</p>}
        <DisabledReason id={uid} reason={blocked} />
        <div className="flex items-center justify-end gap-3">
          <button type="button" className={BTN} onClick={onClose}>{t('common.cancel')}</button>
          <button type="submit" className={BTN_PRIMARY} disabled={!!blocked || busy} {...describedBy(uid, blocked)}>{busy ? t('case_extra.saving') : t('permissions.remove')}</button>
        </div>
      </form>
    </ModalShell>
  );
};
