import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { ArrowLeft, ChevronRight, Plus, Send, UserCheck, UserX } from 'lucide-react';
import { t } from '../lib/i18n';
import { friendlyError } from '../lib/errors';
import { supabase } from '../lib/supabase';
import { dataApi } from '../lib/data';
import { useCatalog } from '../lib/catalog';
import { useToast } from '../lib/toast';
import { formatDate } from '../lib/format';
import { invitePerson } from '../lib/invitations';
import { ROLE_NAMES } from '../lib/navigation';
import {
  filterTeam, grantPreview, groupTeam, memberStatus, roleUsesArea,
  MemberStatus, TeamAccess, TeamCapability, TeamFilter, TeamGrantLite, TeamMember, TeamProfile, TeamRole,
} from '../lib/team';
import { ModalShell } from './ModalShell';
import { Tabs } from './Tabs';
import { PermissionsPanel } from './PermissionsPanel';
import { InvitePanel } from './InvitePanel';
import { DisabledReason, describedBy } from './DisabledReason';

// Equipo (E16 fase A, rediseñado en E17 fase 1): una TABLA de personas con filtros y un panel lateral con todo de la persona
// elegida (roles, «qué puede hacer», dar un rol, desactivar). Rol y área siguen siendo independientes en la base: una persona
// puede tener varios roles, cada uno con su área o sin ella; la pantalla solo pregunta el área cuando importa. Nadie se quita
// el acceso a sí mismo y la organización nunca se queda sin dirección: la base lo impone.
const INPUT = 'min-h-11 w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-turquesa focus:outline-none';
const BTN = 'inline-flex min-h-11 items-center gap-1.5 rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50';
const BTN_PRIMARY = 'inline-flex min-h-11 items-center gap-1.5 rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon shadow-sm hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50';
const ALERT = 'rounded-lg border border-alerta-dark/40 bg-alerta-bg/40 p-3 text-sm font-semibold text-alerta-dark';

type Action = { kind: 'revoke'; role: TeamRole; who: string } | { kind: 'active'; profile: TeamProfile; activate: boolean };
interface UserCap { capability_code: string; source_kind: 'role' | 'area' | 'safeguard'; role_name: string | null; area_id: string | null }

const STATUS_STYLE: Record<MemberStatus, string> = {
  active: 'bg-green-100 text-green-800',
  inactive: 'bg-amber-100 text-amber-800',
  pending: 'bg-blue-100 text-blue-800',
  no_role: 'bg-gray-100 text-gray-800',
};
const StatusBadge: React.FC<{ status: MemberStatus }> = ({ status }) => (
  <span className={`inline-block whitespace-nowrap rounded-md px-2.5 py-1 text-xs font-bold ${STATUS_STYLE[status]}`}>{t(`team.status_${status}`)}</span>
);

export const TeamView: React.FC<{ currentUserId: string; canEditPermissions: boolean }> = ({ currentUserId, canEditPermissions }) => {
  const [tab, setTab] = useState<'team' | 'permissions'>('team');
  const { areas } = useCatalog();
  const toast = useToast();
  const [team, setTeam] = useState<TeamMember[] | null>(null);
  const [access, setAccess] = useState<Map<string, TeamAccess>>(new Map());
  const [caps, setCaps] = useState<TeamCapability[]>([]);
  const [grants, setGrants] = useState<TeamGrantLite[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [filter, setFilter] = useState<TeamFilter>({ text: '', role: '', area: '', status: '' });
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [action, setAction] = useState<Action | null>(null);

  const load = useCallback(async () => {
    try {
      const [p, r, a, c, g] = await Promise.all([
        supabase.from('user_profile').select('id, full_name, email, active'),
        supabase.from('user_role').select('id, user_id, role_name, area_id, granted_by, granted_at, revoked_by, revoked_at, grant_reason, revoke_reason'),
        supabase.rpc('fn_team_access'),
        supabase.from('capability').select('code, description_es, sort_order').order('sort_order'),
        supabase.from('capability_grant').select('capability_code, role_name, area_id, revoked_at'),
      ]);
      if (p.error) throw p.error;
      if (r.error) throw r.error;
      if (a.error) throw a.error;
      setTeam(groupTeam((p.data ?? []) as TeamProfile[], (r.data ?? []) as TeamRole[]));
      setAccess(new Map(((a.data ?? []) as TeamAccess[]).map((x) => [x.user_id, x])));
      setCaps((c.data ?? []) as TeamCapability[]);
      setGrants((g.data ?? []) as TeamGrantLite[]);
      setLoadError(null);
    } catch (e) {
      setLoadError(friendlyError(e));
    }
  }, []);
  useEffect(() => { void load(); }, [load]);

  const areaName = useCallback((id: string | null) => (id ? areas.find((x) => x.id === id)?.name ?? '—' : t('team.no_area')), [areas]);
  const nameOf = (id: string | null) => (id ? team?.find((m) => m.profile.id === id)?.profile.full_name ?? '—' : '—');
  const done = async (okKey: string) => { toast.success(t(okKey)); await load(); };

  const shown = useMemo(() => filterTeam(team ?? [], access, filter), [team, access, filter]);
  const selected = team?.find((m) => m.profile.id === selectedId) ?? null;
  const filtering = filter.text !== '' || filter.role !== '' || filter.area !== '' || filter.status !== '';
  const set = (patch: Partial<TeamFilter>) => setFilter((f) => ({ ...f, ...patch }));

  return (
    <div className="mx-auto max-w-6xl space-y-5">
      <div>
        <h2 className="font-title text-2xl font-bold text-carbon">{t('team.title')}</h2>
        {tab === 'team' && <p className="mt-1 text-sm text-gray-700">{t('team.subtitle')}</p>}
      </div>
      {canEditPermissions && (
        <Tabs ariaLabel={t('team.tabs')} value={tab} onChange={(id) => setTab(id as 'team' | 'permissions')}
          items={[{ id: 'team', label: t('team.tab_team') }, { id: 'permissions', label: t('team.tab_permissions') }]} />
      )}
      {tab === 'permissions' && canEditPermissions && <PermissionsPanel />}

      {tab === 'team' && (
        <>
          <InvitePanel onInvited={load} />
          {loadError && <p role="alert" className={ALERT}>{loadError}</p>}
          {!team && !loadError && <p className="text-sm text-gray-700">{t('team.loading')}</p>}

          {team && (
            <div className={`grid gap-5 ${selected ? 'lg:grid-cols-[minmax(0,1fr)_26rem]' : ''}`}>
              {/* En pantalla chica, el panel de la persona reemplaza a la lista */}
              <div className={`min-w-0 space-y-3 ${selected ? 'hidden lg:block' : ''}`}>
                <Filters filter={filter} set={set} areas={areas.filter((x) => x.active)} />
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <p className="text-sm text-gray-700" aria-live="polite">{t('team.count').replace('{n}', String(shown.length)).replace('{total}', String(team.length))}</p>
                  {filtering && <button type="button" className={BTN} onClick={() => setFilter({ text: '', role: '', area: '', status: '' })}>{t('team.clear_filters')}</button>}
                </div>
                {shown.length === 0 ? (
                  <p className="rounded-2xl border border-gray-200 bg-white p-5 text-sm text-gray-700">{t('team.empty')}</p>
                ) : (
                  <TeamTable members={shown} access={access} areaName={areaName} currentUserId={currentUserId} selectedId={selectedId} onSelect={setSelectedId} />
                )}
              </div>

              {selected && (
                <PersonPanel
                  key={selected.profile.id}
                  member={selected}
                  self={selected.profile.id === currentUserId}
                  status={memberStatus(selected, access.get(selected.profile.id))}
                  access={access.get(selected.profile.id)}
                  caps={caps}
                  grants={grants}
                  areaName={areaName}
                  nameOf={nameOf}
                  onClose={() => setSelectedId(null)}
                  onAction={setAction}
                  onChanged={load}
                  done={done}
                />
              )}
            </div>
          )}
        </>
      )}

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

// ---------------------------------------------------------------- Filtros
const Filters: React.FC<{ filter: TeamFilter; set: (p: Partial<TeamFilter>) => void; areas: { id: string; name: string }[] }> = ({ filter, set, areas }) => {
  const uid = React.useId();
  const statuses: MemberStatus[] = ['active', 'pending', 'no_role', 'inactive'];
  return (
    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
      <div>
        <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-q`}>{t('team.filter_search')}</label>
        <input id={`${uid}-q`} name={`${uid}-q`} type="search" autoComplete="off" className={INPUT} value={filter.text} onChange={(e) => set({ text: e.target.value })} />
      </div>
      <div>
        <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-r`}>{t('team.filter_role')}</label>
        <select id={`${uid}-r`} name={`${uid}-r`} autoComplete="off" className={INPUT} value={filter.role} onChange={(e) => set({ role: e.target.value })}>
          <option value="">{t('team.all_roles')}</option>
          {ROLE_NAMES.map((r) => <option key={r} value={r}>{t(`roles.${r}.title`)}</option>)}
        </select>
      </div>
      <div>
        <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-a`}>{t('team.filter_area')}</label>
        <select id={`${uid}-a`} name={`${uid}-a`} autoComplete="off" className={INPUT} value={filter.area} onChange={(e) => set({ area: e.target.value })}>
          <option value="">{t('team.all_areas')}</option>
          {areas.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
        </select>
      </div>
      <div>
        <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-s`}>{t('team.filter_status')}</label>
        <select id={`${uid}-s`} name={`${uid}-s`} autoComplete="off" className={INPUT} value={filter.status} onChange={(e) => set({ status: e.target.value as TeamFilter['status'] })}>
          <option value="">{t('team.all_statuses')}</option>
          {statuses.map((s) => <option key={s} value={s}>{t(`team.status_${s}`)}</option>)}
        </select>
      </div>
    </div>
  );
};

// ---------------------------------------------------------------- Tabla (y lista en pantalla chica)
const TeamTable: React.FC<{
  members: TeamMember[]; access: Map<string, TeamAccess>; areaName: (id: string | null) => string;
  currentUserId: string; selectedId: string | null; onSelect: (id: string) => void;
}> = ({ members, access, areaName, currentUserId, selectedId, onSelect }) => {
  const chips = (m: TeamMember) => m.active.length === 0
    ? <span className="text-sm text-gray-700">{t('team.no_roles_short')}</span>
    : (
      <ul className="flex flex-wrap gap-1.5">
        {m.active.map((r) => (
          <li key={r.id} className="rounded-md bg-claro px-2 py-0.5 text-xs font-semibold text-carbon">
            {t(`roles.${r.role_name}.title`)}{r.area_id ? ` · ${areaName(r.area_id)}` : ''}
          </li>
        ))}
      </ul>
    );
  return (
    <>
      <div className="hidden overflow-hidden rounded-2xl border border-gray-200 bg-white md:block">
        <table className="w-full text-left text-sm">
          <caption className="sr-only">{t('team.title')}</caption>
          <thead className="border-b border-gray-200 bg-gray-50 text-xs font-bold uppercase tracking-wide text-gray-700">
            <tr>
              <th scope="col" className="px-4 py-3">{t('team.col_person')}</th>
              <th scope="col" className="px-4 py-3">{t('team.col_roles')}</th>
              <th scope="col" className="px-4 py-3">{t('team.col_status')}</th>
              <th scope="col" className="w-10 px-2 py-3"><span className="sr-only">{t('team.col_open')}</span></th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {members.map((m) => (
              <tr key={m.profile.id} className={selectedId === m.profile.id ? 'bg-claro/60' : 'hover:bg-gray-50'}>
                <td className="px-4 py-3">
                  <button type="button" className="min-h-11 text-left" aria-current={selectedId === m.profile.id} onClick={() => onSelect(m.profile.id)}>
                    <span className="block font-bold text-carbon">
                      {m.profile.full_name} {m.profile.id === currentUserId && <span className="font-normal text-turquesa-dark">({t('team.you')})</span>}
                    </span>
                    <span className="block text-gray-700">{m.profile.email}</span>
                  </button>
                </td>
                <td className="px-4 py-3">{chips(m)}</td>
                <td className="px-4 py-3"><StatusBadge status={memberStatus(m, access.get(m.profile.id))} /></td>
                <td className="px-2 py-3 text-gray-700"><ChevronRight className="h-4 w-4" aria-hidden="true" /></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <ul className="space-y-2 md:hidden">
        {members.map((m) => (
          <li key={m.profile.id} className="rounded-2xl border border-gray-200 bg-white p-4">
            <button type="button" className="block min-h-11 w-full text-left" onClick={() => onSelect(m.profile.id)}>
              <span className="flex flex-wrap items-center justify-between gap-2">
                <span className="font-bold text-carbon">{m.profile.full_name} {m.profile.id === currentUserId && <span className="font-normal text-turquesa-dark">({t('team.you')})</span>}</span>
                <StatusBadge status={memberStatus(m, access.get(m.profile.id))} />
              </span>
              <span className="block text-sm text-gray-700">{m.profile.email}</span>
            </button>
            <div className="mt-2">{chips(m)}</div>
          </li>
        ))}
      </ul>
    </>
  );
};

// ---------------------------------------------------------------- Panel de la persona
const PersonPanel: React.FC<{
  member: TeamMember; self: boolean; status: MemberStatus; access: TeamAccess | undefined;
  caps: TeamCapability[]; grants: TeamGrantLite[]; areaName: (id: string | null) => string; nameOf: (id: string | null) => string;
  onClose: () => void; onAction: (a: Action) => void; onChanged: () => Promise<void>; done: (okKey: string) => Promise<void>;
}> = ({ member: m, self, status, access, caps, grants, areaName, nameOf, onClose, onAction, onChanged, done }) => {
  const toast = useToast();
  const [granting, setGranting] = useState(false);
  const [userCaps, setUserCaps] = useState<UserCap[] | null>(null);
  const [capsError, setCapsError] = useState<string | null>(null);
  const [resending, setResending] = useState(false);
  const [resendError, setResendError] = useState<string | null>(null);

  const loadCaps = useCallback(async () => {
    const { data, error } = await supabase.rpc('fn_user_capabilities', { p_user_id: m.profile.id });
    if (error) { setCapsError(friendlyError(error)); return; }
    setUserCaps((data ?? []) as UserCap[]);
    setCapsError(null);
  }, [m.profile.id]);
  // Se vuelve a calcular cuando cambian sus roles o su estado
  const rolesKey = m.active.map((r) => r.id).join(',') + (m.profile.active ? 'a' : 'i');
  useEffect(() => { void loadCaps(); }, [loadCaps, rolesKey]);

  const resend = async () => {
    setResending(true);
    setResendError(null);
    try {
      await invitePerson(m.profile.email, m.profile.full_name);
      toast.success(t('invite.resent'));
      await onChanged();
    } catch (e) {
      setResendError(friendlyError(e));
    } finally {
      setResending(false);
    }
  };

  const capDescription = (code: string) => caps.find((c) => c.code === code)?.description_es ?? code;
  const via = (c: UserCap) =>
    c.source_kind === 'area' ? t('team.via_area').replace('{area}', areaName(c.area_id))
    : c.source_kind === 'safeguard' ? t('team.via_safeguard')
    : t('team.via_role').replace('{role}', t(`roles.${c.role_name}.title`));
  const orderedCaps = (userCaps ?? []).slice().sort((a, b) => (caps.find((x) => x.code === a.capability_code)?.sort_order ?? 0) - (caps.find((x) => x.code === b.capability_code)?.sort_order ?? 0));

  return (
    <aside aria-label={m.profile.full_name} className="min-w-0 space-y-5 rounded-2xl border border-gray-200 bg-white p-5">
      <button type="button" className={`${BTN} lg:hidden`} onClick={onClose}>
        <ArrowLeft className="h-4 w-4" aria-hidden="true" />
        {t('team.back_to_list')}
      </button>
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <h3 className="break-words text-lg font-bold text-carbon">{m.profile.full_name} {self && <span className="text-sm font-normal text-turquesa-dark">({t('team.you')})</span>}</h3>
          <p className="break-all text-sm text-gray-700">{m.profile.email}</p>
        </div>
        <StatusBadge status={status} />
      </div>
      <button type="button" className={`${BTN} hidden lg:inline-flex`} onClick={onClose}>{t('team.close_panel')}</button>

      {status === 'pending' && (
        <div className="space-y-2 rounded-xl border border-blue-200 bg-blue-50 p-3">
          <p className="text-sm text-blue-900">{t('team.pending_note')}</p>
          <button type="button" className={BTN} disabled={resending} onClick={resend}>
            <Send className="h-4 w-4" aria-hidden="true" />
            {resending ? t('invite.sending') : t('team.resend')}
          </button>
          {resendError && <p role="alert" className={ALERT}>{resendError}</p>}
        </div>
      )}
      {access?.last_sign_in_at && <p className="text-sm text-gray-700">{t('team.last_access')} {formatDate(access.last_sign_in_at)}</p>}

      <section>
        <h4 className="text-sm font-bold text-carbon">{t('team.roles')}</h4>
        {m.active.length === 0 ? (
          <p className="mt-1 text-sm text-gray-700">{t('team.no_roles')}</p>
        ) : (
          <ul className="mt-1 divide-y divide-gray-100">
            {m.active.map((r) => (
              <li key={r.id} className="flex flex-wrap items-center gap-2 py-2">
                <span className="min-w-0 flex-1 text-sm text-carbon">
                  <span className="font-semibold">{t(`roles.${r.role_name}.title`)}</span> · {areaName(r.area_id)}
                  <span className="text-gray-700"> · {t('team.since')} {formatDate(r.granted_at)}</span>
                  {r.grant_reason && <span className="block text-xs text-gray-700">{r.grant_reason}</span>}
                </span>
                {!self && <button type="button" className={BTN} onClick={() => onAction({ kind: 'revoke', role: r, who: m.profile.full_name })}>{t('team.revoke')}</button>}
              </li>
            ))}
          </ul>
        )}
        {self && <p className="mt-1 text-sm text-gray-700">{t('team.self_note')}</p>}
        <div className="mt-3">
          <button type="button" className={BTN} aria-expanded={granting} onClick={() => setGranting(!granting)}>
            <Plus className="h-4 w-4" aria-hidden="true" />
            {t('team.grant')}
          </button>
        </div>
        {granting && (
          <GrantForm
            userId={m.profile.id}
            grants={grants}
            caps={caps}
            onDone={async () => { setGranting(false); await done('team.granted'); }}
            onCancel={() => setGranting(false)}
          />
        )}
      </section>

      <section>
        <h4 className="text-sm font-bold text-carbon">{t('team.caps_title')}</h4>
        {capsError && <p role="alert" className={`mt-1 ${ALERT}`}>{capsError}</p>}
        {!m.profile.active && <p className="mt-1 text-sm text-gray-700">{t('team.caps_inactive')}</p>}
        {m.profile.active && userCaps && orderedCaps.length === 0 && <p className="mt-1 text-sm text-gray-700">{t('team.caps_none')}</p>}
        {m.profile.active && orderedCaps.length > 0 && (
          <ul className="mt-1 divide-y divide-gray-100">
            {orderedCaps.map((c) => (
              <li key={`${c.capability_code}-${c.source_kind}-${c.role_name ?? c.area_id}`} className="py-1.5 text-sm text-carbon">
                {capDescription(c.capability_code)}
                <span className="block text-xs text-gray-700">{via(c)}</span>
              </li>
            ))}
          </ul>
        )}
      </section>

      <div className="flex flex-wrap gap-2 border-t border-gray-100 pt-4">
        {m.profile.active && !self && (
          <button type="button" className={BTN} onClick={() => onAction({ kind: 'active', profile: m.profile, activate: false })}>
            <UserX className="h-4 w-4" aria-hidden="true" />
            {t('team.deactivate')}
          </button>
        )}
        {!m.profile.active && (
          <button type="button" className={BTN} onClick={() => onAction({ kind: 'active', profile: m.profile, activate: true })}>
            <UserCheck className="h-4 w-4" aria-hidden="true" />
            {t('team.reactivate')}
          </button>
        )}
      </div>

      {m.history.length > 0 && (
        <details className="text-sm text-gray-700">
          <summary className="cursor-pointer font-semibold">{t('team.history')} ({m.history.length})</summary>
          <ul className="mt-2 space-y-1.5">
            {m.history.map((r) => (
              <li key={r.id}>
                <span className="font-semibold">{t(`roles.${r.role_name}.title`)}</span> · {areaName(r.area_id)} · {formatDate(r.granted_at)} → {formatDate(r.revoked_at as string)}
                {r.revoke_reason && <span className="text-gray-700"> · {r.revoke_reason}</span>}
                <span className="text-gray-700"> · {t('team.revoked_by')} {nameOf(r.revoked_by)}</span>
              </li>
            ))}
          </ul>
        </details>
      )}
    </aside>
  );
};

// Dar un rol, en un paso que se adapta: el rol lleva una frase de lo que permite; el área solo se pregunta a ingreso y atención;
// el motivo es opcional (al quitar un rol sí es obligatorio). Antes de confirmar se dice lo que la persona podrá hacer.
const GrantForm: React.FC<{ userId: string; grants: TeamGrantLite[]; caps: TeamCapability[]; onDone: () => Promise<void>; onCancel: () => void }> = ({ userId, grants, caps, onDone, onCancel }) => {
  const uid = React.useId();
  const { areas } = useCatalog();
  const [role, setRole] = useState('');
  const [area, setArea] = useState('');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const activeAreas = useMemo(() => areas.filter((a) => a.active), [areas]);
  const blocked = role === '' ? t('team.reason_role') : null;
  const asksArea = role !== '' && roleUsesArea(role);
  const preview = role === '' ? [] : grantPreview(role, asksArea && area ? area : null, grants, caps);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (blocked || busy) return;
    setBusy(true);
    setError(null);
    try {
      await dataApi.grantRole(userId, role, asksArea && area ? area : null, reason);
      await onDone();
    } catch (err) {
      setError(friendlyError(err));
      setBusy(false);
    }
  };

  return (
    <form onSubmit={submit} className="mt-3 space-y-3 rounded-xl border border-gray-200 bg-gray-50 p-4">
      <div>
        <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-r`}>{t('team.field_role')}</label>
        <select id={`${uid}-r`} name={`${uid}-r`} autoComplete="off" className={INPUT} value={role} onChange={(e) => { setRole(e.target.value); setArea(''); }}>
          <option value="">{t('team.choose_role')}</option>
          {ROLE_NAMES.map((r) => <option key={r} value={r}>{t(`roles.${r}.title`)}</option>)}
        </select>
        {role !== '' && <p className="mt-1 text-sm text-gray-700">{t(`team.role_hint.${role}`)}</p>}
      </div>
      {asksArea && (
        <div>
          <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-a`}>{t('team.field_area')}</label>
          <select id={`${uid}-a`} name={`${uid}-a`} autoComplete="off" className={INPUT} value={area} onChange={(e) => setArea(e.target.value)}>
            <option value="">{t('team.no_area')}</option>
            {activeAreas.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
          </select>
          <p className="mt-1 text-sm text-gray-700">{t('team.area_hint')}</p>
        </div>
      )}
      {role === 'director' && <p className="text-sm text-gray-700">{t('team.director_areas')}</p>}
      {role !== '' && (
        <div className="rounded-lg border border-gray-200 bg-white p-3">
          <p className="text-sm font-semibold text-carbon">{t('team.preview_title')}</p>
          {preview.length === 0
            ? <p className="text-sm text-gray-700">{t('team.preview_none')}</p>
            : <ul className="mt-1 list-disc space-y-0.5 pl-5 text-sm text-gray-700">{preview.map((p) => <li key={p}>{p}</li>)}</ul>}
        </div>
      )}
      <div>
        <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-m`}>{t('team.field_reason_optional')}</label>
        <input id={`${uid}-m`} name={`${uid}-m`} autoComplete="off" className={INPUT} maxLength={300} value={reason} onChange={(e) => setReason(e.target.value)} />
      </div>
      {error && <p role="alert" className={ALERT}>{error}</p>}
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
        {error && <p role="alert" className={ALERT}>{error}</p>}
        <DisabledReason id={uid} reason={blocked} />
        <div className="flex items-center justify-end gap-3">
          <button type="button" className={BTN} onClick={onClose}>{t('common.cancel')}</button>
          <button type="submit" className={BTN_PRIMARY} disabled={!!blocked || busy} {...describedBy(uid, blocked)}>{busy ? t('case_extra.saving') : submitLabel}</button>
        </div>
      </form>
    </ModalShell>
  );
};
