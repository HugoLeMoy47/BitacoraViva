import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Plus, UserCheck, UserX } from 'lucide-react';
import { t } from '../lib/i18n';
import { friendlyError } from '../lib/errors';
import { supabase } from '../lib/supabase';
import { dataApi } from '../lib/data';
import { useCatalog } from '../lib/catalog';
import { useToast } from '../lib/toast';
import { formatDate } from '../lib/format';
import { ROLE_NAMES } from '../lib/navigation';
import { groupTeam, TeamMember, TeamProfile, TeamRole } from '../lib/team';
import { ModalShell } from './ModalShell';
import { Tabs } from './Tabs';
import { PermissionsPanel } from './PermissionsPanel';
import { DisabledReason, describedBy } from './DisabledReason';

// Equipo (E16 fase A): la dirección ve a las personas de su organización y otorga, revoca y desactiva por funciones de la
// base (con motivo y auditoría). Rol y área son independientes: una persona puede tener varios roles, cada uno con su área o
// sin ella. Nadie se quita el acceso a sí mismo, y la organización nunca se queda sin dirección: la base lo impone.
const INPUT = 'min-h-11 w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-turquesa focus:outline-none';
const BTN = 'inline-flex min-h-11 items-center gap-1.5 rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50';
const BTN_PRIMARY = 'inline-flex min-h-11 items-center gap-1.5 rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon shadow-sm hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50';

type Action = { kind: 'revoke'; role: TeamRole; who: string } | { kind: 'active'; profile: TeamProfile; activate: boolean };

export const TeamView: React.FC<{ currentUserId: string; canEditPermissions: boolean }> = ({ currentUserId, canEditPermissions }) => {
  const [tab, setTab] = useState<'team' | 'permissions'>('team');
  const { areas } = useCatalog();
  const toast = useToast();
  const [team, setTeam] = useState<TeamMember[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [granting, setGranting] = useState<string | null>(null);
  const [action, setAction] = useState<Action | null>(null);

  const load = useCallback(async () => {
    try {
      const [p, r] = await Promise.all([
        supabase.from('user_profile').select('id, full_name, email, active'),
        supabase.from('user_role').select('id, user_id, role_name, area_id, granted_by, granted_at, revoked_by, revoked_at, grant_reason, revoke_reason'),
      ]);
      if (p.error) throw p.error;
      if (r.error) throw r.error;
      setTeam(groupTeam((p.data ?? []) as TeamProfile[], (r.data ?? []) as TeamRole[]));
      setLoadError(null);
    } catch (e) {
      setLoadError(friendlyError(e));
    }
  }, []);
  useEffect(() => { void load(); }, [load]);

  const areaName = (id: string | null) => (id ? areas.find((a) => a.id === id)?.name ?? '—' : t('team.no_area'));
  const nameOf = (id: string | null) => (id ? team?.find((m) => m.profile.id === id)?.profile.full_name ?? '—' : '—');
  const done = async (okKey: string) => { toast.success(t(okKey)); await load(); };

  return (
    <div className="mx-auto max-w-4xl space-y-5">
      <div>
        <h2 className="font-title text-2xl font-bold text-carbon">{t('team.title')}</h2>
        {tab === 'team' && (
          <>
            <p className="mt-1 text-sm text-gray-600">{t('team.subtitle')}</p>
            <p className="mt-1 text-sm text-gray-600">{t('team.rules')}</p>
          </>
        )}
      </div>
      {canEditPermissions && (
        <Tabs ariaLabel={t('team.tabs')} value={tab} onChange={(id) => setTab(id as 'team' | 'permissions')}
          items={[{ id: 'team', label: t('team.tab_team') }, { id: 'permissions', label: t('team.tab_permissions') }]} />
      )}
      {tab === 'permissions' && canEditPermissions && <PermissionsPanel />}
      {loadError && tab === 'team' && <p role="alert" className="rounded-lg border border-alerta-dark/40 bg-alerta-bg/40 p-3 text-sm font-semibold text-alerta-dark">{loadError}</p>}
      {!team && !loadError && tab === 'team' && <p className="text-sm text-gray-600">{t('team.loading')}</p>}
      <ul className={`space-y-4 ${tab === 'team' ? '' : 'hidden'}`}>
        {(team ?? []).map((m) => {
          const self = m.profile.id === currentUserId;
          return (
            <li key={m.profile.id} className="rounded-2xl border border-gray-200 bg-white p-5">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div>
                  <h3 className="text-base font-bold text-carbon">
                    {m.profile.full_name} {self && <span className="text-sm font-normal text-turquesa-dark">({t('team.you')})</span>}
                  </h3>
                  <p className="text-sm text-gray-600">{m.profile.email}</p>
                </div>
                <span className={`rounded-md px-2.5 py-1 text-xs font-bold ${m.profile.active ? 'bg-green-100 text-green-800' : 'bg-amber-100 text-amber-800'}`}>
                  {m.profile.active ? t('team.active') : t('team.inactive')}
                </span>
              </div>

              <h4 className="mt-4 text-sm font-bold text-carbon">{t('team.roles')}</h4>
              {m.active.length === 0 ? (
                <p className="mt-1 text-sm text-gray-600">{t('team.no_roles')}</p>
              ) : (
                <ul className="mt-1 divide-y divide-gray-100">
                  {m.active.map((r) => (
                    <li key={r.id} className="flex flex-wrap items-center gap-2 py-2">
                      <span className="min-w-0 flex-1 text-sm text-carbon">
                        <span className="font-semibold">{t(`roles.${r.role_name}.title`)}</span> · {areaName(r.area_id)}
                        <span className="text-gray-600"> · {t('team.since')} {formatDate(r.granted_at)}</span>
                        {r.grant_reason && <span className="block text-xs text-gray-600">{r.grant_reason}</span>}
                      </span>
                      {!self && (
                        <button type="button" className={BTN} onClick={() => setAction({ kind: 'revoke', role: r, who: m.profile.full_name })}>{t('team.revoke')}</button>
                      )}
                    </li>
                  ))}
                </ul>
              )}
              {self && <p className="mt-1 text-sm text-gray-600">{t('team.self_note')}</p>}

              <div className="mt-3 flex flex-wrap gap-2">
                <button type="button" className={BTN} aria-expanded={granting === m.profile.id} onClick={() => setGranting(granting === m.profile.id ? null : m.profile.id)}>
                  <Plus className="h-4 w-4" aria-hidden="true" />
                  {t('team.grant')}
                </button>
                {m.profile.active && !self && (
                  <button type="button" className={BTN} onClick={() => setAction({ kind: 'active', profile: m.profile, activate: false })}>
                    <UserX className="h-4 w-4" aria-hidden="true" />
                    {t('team.deactivate')}
                  </button>
                )}
                {!m.profile.active && (
                  <button type="button" className={BTN} onClick={() => setAction({ kind: 'active', profile: m.profile, activate: true })}>
                    <UserCheck className="h-4 w-4" aria-hidden="true" />
                    {t('team.reactivate')}
                  </button>
                )}
              </div>

              {granting === m.profile.id && (
                <GrantForm
                  userId={m.profile.id}
                  onDone={async () => { setGranting(null); await done('team.granted'); }}
                  onCancel={() => setGranting(null)}
                />
              )}

              {m.history.length > 0 && (
                <details className="mt-3 text-sm text-gray-700">
                  <summary className="cursor-pointer font-semibold">{t('team.history')} ({m.history.length})</summary>
                  <ul className="mt-2 space-y-1.5">
                    {m.history.map((r) => (
                      <li key={r.id}>
                        <span className="font-semibold">{t(`roles.${r.role_name}.title`)}</span> · {areaName(r.area_id)} · {formatDate(r.granted_at)} → {formatDate(r.revoked_at as string)}
                        {r.revoke_reason && <span className="text-gray-600"> · {r.revoke_reason}</span>}
                        <span className="text-gray-600"> · {t('team.revoked_by')} {nameOf(r.revoked_by)}</span>
                      </li>
                    ))}
                  </ul>
                </details>
              )}
            </li>
          );
        })}
      </ul>

      {action && (
        <ReasonModal
          title={action.kind === 'revoke' ? t('team.revoke_title').replace('{who}', action.who) : t(action.activate ? 'team.reactivate_title' : 'team.deactivate_title').replace('{who}', action.profile.full_name)}
          hint={action.kind === 'revoke' ? `${t(`roles.${action.role.role_name}.title`)} · ${areaName(action.role.area_id)}` : t(action.activate ? 'team.reactivate_hint' : 'team.deactivate_hint')}
          submitLabel={action.kind === 'revoke' ? t('team.revoke') : action.activate ? t('team.reactivate') : t('team.deactivate')}
          onSubmit={async (reason) => {
            if (action.kind === 'revoke') await dataApi.revokeRole(action.role.id, reason);
            else await dataApi.setUserActive(action.profile.id, action.activate, reason);
            await done(action.kind === 'revoke' ? 'team.revoked' : action.activate ? 'team.reactivated' : 'team.deactivated');
          }}
          onClose={() => setAction(null)}
        />
      )}
    </div>
  );
};

// Otorgar un rol: rol, área (o sin área) y un motivo opcional. Rol y área son independientes.
const GrantForm: React.FC<{ userId: string; onDone: () => Promise<void>; onCancel: () => void }> = ({ userId, onDone, onCancel }) => {
  const uid = React.useId();
  const { areas } = useCatalog();
  const [role, setRole] = useState('');
  const [area, setArea] = useState('');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const activeAreas = useMemo(() => areas.filter((a) => a.active), [areas]);
  const blocked = role === '' ? t('team.reason_role') : null;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (blocked || busy) return;
    setBusy(true);
    setError(null);
    try {
      await dataApi.grantRole(userId, role, area || null, reason);
      await onDone();
    } catch (err) {
      setError(friendlyError(err));
      setBusy(false);
    }
  };

  return (
    <form onSubmit={submit} className="mt-3 space-y-3 rounded-xl border border-gray-200 bg-gray-50 p-4">
      <p className="text-sm text-gray-700">{t('team.grant_hint')}</p>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <div>
          <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-r`}>{t('team.field_role')}</label>
          <select id={`${uid}-r`} name={`${uid}-r`} autoComplete="off" className={INPUT} value={role} onChange={(e) => setRole(e.target.value)}>
            <option value="">{t('team.choose_role')}</option>
            {ROLE_NAMES.map((r) => <option key={r} value={r}>{t(`roles.${r}.title`)}</option>)}
          </select>
        </div>
        <div>
          <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-a`}>{t('team.field_area')}</label>
          <select id={`${uid}-a`} name={`${uid}-a`} autoComplete="off" className={INPUT} value={area} onChange={(e) => setArea(e.target.value)}>
            <option value="">{t('team.no_area')}</option>
            {activeAreas.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
          </select>
        </div>
      </div>
      <div>
        <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-m`}>{t('team.field_reason_optional')}</label>
        <input id={`${uid}-m`} name={`${uid}-m`} autoComplete="off" className={INPUT} maxLength={300} value={reason} onChange={(e) => setReason(e.target.value)} />
      </div>
      {error && <p role="alert" className="rounded-lg border border-alerta-dark/40 bg-alerta-bg/40 p-3 text-sm font-semibold text-alerta-dark">{error}</p>}
      <DisabledReason id={uid} reason={blocked} />
      <div className="flex flex-wrap gap-2">
        <button type="submit" className={BTN_PRIMARY} disabled={!!blocked || busy} {...describedBy(uid, blocked)}>{busy ? t('case_extra.saving') : t('team.grant_submit')}</button>
        <button type="button" className={BTN} onClick={onCancel}>{t('common.cancel')}</button>
      </div>
    </form>
  );
};

// Modal corto: un solo campo, el motivo (obligatorio)
const ReasonModal: React.FC<{ title: string; hint: string; submitLabel: string; onSubmit: (reason: string) => Promise<void>; onClose: () => void }> = ({ title, hint, submitLabel, onSubmit, onClose }) => {
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
          <button type="submit" className={BTN_PRIMARY} disabled={!!blocked || busy} {...describedBy(uid, blocked)}>{busy ? t('case_extra.saving') : submitLabel}</button>
        </div>
      </form>
    </ModalShell>
  );
};
