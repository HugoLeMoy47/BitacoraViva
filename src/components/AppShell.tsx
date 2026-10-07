import React, { useRef } from 'react';
import {
  Bell,
  BarChart3,
  ChevronDown,
  FolderOpen,
  Gauge,
  History,
  Info,
  Layers,
  LogOut,
  MoreHorizontal,
  Scale,
  Settings,
} from 'lucide-react';
import { t } from '../lib/i18n';
import { SessionUser } from '../lib/session';
import { RouteId, navigate } from '../lib/router';
import { ADMIN_ROUTES, PRIMARY_ROUTES, ROUTE_LABEL_KEY } from '../lib/navigation';
import { DemoChip } from './DemoBanner';
import { Menu, MenuItem } from './Menu';
import { Tabs } from './Tabs';

// Armazón de la aplicación. Una sola fuente de navegación (los destinos permitidos por rol)
// alimenta la barra de pestañas en escritorio y la barra inferior en celular.
const ICON: Record<RouteId, React.ReactNode> = {
  operations: <Gauge className="h-4 w-4" aria-hidden="true" />,
  cases: <FolderOpen className="h-4 w-4" aria-hidden="true" />,
  indicators: <BarChart3 className="h-4 w-4" aria-hidden="true" />,
  areas: <Layers className="h-4 w-4" aria-hidden="true" />,
  audit: <History className="h-4 w-4" aria-hidden="true" />,
  authority: <Scale className="h-4 w-4" aria-hidden="true" />,
  about: <Info className="h-4 w-4" aria-hidden="true" />,
};

const initials = (name: string) =>
  name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase())
    .join('');

interface AppShellProps {
  user: SessionUser;
  organizationName: string;
  route: RouteId | null;
  allowed: RouteId[];
  caseCount: number;
  digestPending: number | null;
  onOpenDigest: () => void;
  onSignOut: () => void;
  children: React.ReactNode;
}

export const AppShell: React.FC<AppShellProps> = ({
  user,
  organizationName,
  route,
  allowed,
  caseCount,
  digestPending,
  onOpenDigest,
  onSignOut,
  children,
}) => {
  const mainRef = useRef<HTMLElement>(null);
  const primary = PRIMARY_ROUTES.filter((r) => allowed.includes(r));
  const admin = ADMIN_ROUTES.filter((r) => allowed.includes(r));
  const hasAbout = allowed.includes('about');
  const inAdmin = !!route && admin.includes(route);

  const label = (id: RouteId) => t(ROUTE_LABEL_KEY[id]);
  const menuItem = (id: RouteId): MenuItem => ({
    id,
    label: label(id),
    icon: ICON[id],
    current: route === id,
    onSelect: () => navigate(id),
  });

  const accountItems: MenuItem[] = [
    ...(hasAbout ? [menuItem('about')] : []),
    {
      id: 'sign-out',
      label: t('session.sign_out'),
      icon: <LogOut className="h-4 w-4" aria-hidden="true" />,
      onSelect: onSignOut,
      danger: true,
    },
  ];

  const tabItems = primary.map((id) => ({
    id,
    label: label(id),
    icon: ICON[id],
    badge:
      id === 'cases' ? (
        <span className="rounded-full bg-gray-200 px-1.5 text-xs font-mono text-carbon" aria-label={`${caseCount}`}>
          {caseCount}
        </span>
      ) : undefined,
  }));

  return (
    <div className="flex min-h-screen flex-col bg-gray-50 font-sans text-carbon">
      <a
        href="#contenido"
        onClick={(e) => {
          e.preventDefault();
          mainRef.current?.focus();
        }}
        className="sr-only focus:not-sr-only focus:absolute focus:left-2 focus:top-2 focus:z-[70] focus:rounded-lg focus:bg-white focus:px-4 focus:py-2 focus:text-sm focus:font-semibold focus:shadow-lg"
      >
        {t('navigation.skip')}
      </a>

      <header className="sticky top-0 z-40 border-b-4 border-turquesa bg-carbon text-white">
        <div className="mx-auto flex h-14 max-w-7xl items-center gap-2 px-3 sm:gap-3 sm:px-6 lg:px-8">
          <div className="flex min-w-0 flex-1 items-center gap-2">
            <span
              className="flex h-8 w-8 shrink-0 items-center justify-center rounded bg-turquesa text-sm font-bold text-carbon"
              aria-hidden="true"
            >
              BV
            </span>
            <h1 className="truncate text-base font-bold tracking-tight">{t('app.title')}</h1>
            <DemoChip />
            <span className="hidden min-w-0 truncate text-sm text-gray-300 md:inline" translate="no">
              · {organizationName}
            </span>
          </div>

          {digestPending !== null && (
            <button
              type="button"
              onClick={onOpenDigest}
              aria-label={`${t('journal.director_digest.title')}: ${digestPending}`}
              className="relative flex h-11 w-11 shrink-0 items-center justify-center rounded-lg text-gray-200 hover:bg-white/10 hover:text-white"
            >
              <Bell className="h-5 w-5" aria-hidden="true" />
              {digestPending > 0 && (
                <span className="absolute right-1 top-1 flex h-4 min-w-4 items-center justify-center rounded-full bg-alerta-dark px-1 text-xs font-bold leading-none text-white">
                  {digestPending}
                </span>
              )}
            </button>
          )}

          <Menu
            ariaLabel={t('session.account')}
            triggerClassName="flex h-11 items-center gap-2 rounded-lg px-1.5 hover:bg-white/10"
            trigger={
              <>
                <span className="flex h-8 w-8 items-center justify-center rounded-full bg-turquesa text-xs font-bold text-carbon" aria-hidden="true">
                  {initials(user.profile.full_name)}
                </span>
                <span className="hidden max-w-[10rem] truncate text-sm font-medium sm:inline">{user.profile.full_name}</span>
                <ChevronDown className="h-4 w-4 text-gray-300" aria-hidden="true" />
              </>
            }
            header={
              <div className="space-y-1.5 text-xs">
                <p className="text-sm font-semibold text-carbon">{user.profile.full_name}</p>
                <p className="break-all text-gray-500">{user.profile.email}</p>
                <p>
                  <span className="rounded bg-gray-200 px-2 py-0.5 font-mono text-carbon">{t(`roles.${user.role}.badge`)}</span>
                </p>
                <p className="text-gray-500">
                  {t('session.assigned_area')} {user.assignedAreaName || t('session.transversal_role')}
                </p>
                <p className="italic text-gray-500">{t(`roles.${user.role}.description`)}</p>
              </div>
            }
            items={accountItems}
          />
        </div>
      </header>

      {/* Navegación de escritorio */}
      <nav aria-label={t('navigation.primary')} className="hidden border-b border-gray-200 bg-white md:block">
        <div className="mx-auto flex max-w-7xl items-end gap-1 px-6 lg:px-8">
          <Tabs
            bare
            ariaLabel={t('navigation.primary')}
            items={tabItems}
            value={route && primary.includes(route) ? route : ''}
            onChange={(id) => navigate(id as RouteId)}
            className="flex-1"
          />
          {admin.length > 0 && (
            <Menu
              placement="bottom-end"
              triggerClassName={`-mb-px flex shrink-0 items-center gap-2 whitespace-nowrap border-b-2 px-4 py-3 text-sm font-semibold transition ${
                inAdmin ? 'border-turquesa text-carbon' : 'border-transparent text-gray-500 hover:text-carbon'
              }`}
              trigger={
                <>
                  <Settings className="h-4 w-4" aria-hidden="true" />
                  <span>{inAdmin && route ? label(route) : t('navigation.admin')}</span>
                  <ChevronDown className="h-4 w-4" aria-hidden="true" />
                </>
              }
              items={admin.map(menuItem)}
            />
          )}
        </div>
      </nav>

      <main
        id="contenido"
        ref={mainRef}
        tabIndex={-1}
        className="mx-auto w-full max-w-7xl flex-1 px-4 py-5 pb-28 outline-none sm:px-6 md:pb-10 lg:px-8"
      >
        {children}
      </main>

      {/* Navegación de celular: destinos principales al alcance del pulgar */}
      <nav
        aria-label={t('navigation.primary')}
        className="fixed inset-x-0 bottom-0 z-40 border-t border-gray-200 bg-white pb-[env(safe-area-inset-bottom)] md:hidden"
      >
        <ul className="flex">
          {primary.map((id) => {
            const active = route === id;
            return (
              <li key={id} className="flex-1">
                <button
                  type="button"
                  aria-current={active ? 'page' : undefined}
                  onClick={() => navigate(id)}
                  className={`relative flex min-h-14 w-full flex-col items-center justify-center gap-0.5 px-1 py-1.5 text-xs font-semibold ${
                    active ? 'text-turquesa-dark' : 'text-gray-500'
                  }`}
                >
                  <span className={`rounded-full px-4 py-1 ${active ? 'bg-claro' : ''}`}>{ICON[id]}</span>
                  <span className="max-w-full truncate">{label(id)}</span>
                  {id === 'cases' && (
                    <span className="absolute right-[18%] top-1 rounded-full bg-gray-200 px-1.5 text-xs font-mono leading-4 text-carbon">
                      {caseCount}
                    </span>
                  )}
                </button>
              </li>
            );
          })}
          {(admin.length > 0 || hasAbout) && (
            <li className="flex-1">
              <Menu
                placement="top-end"
                triggerClassName={`flex min-h-14 w-full flex-col items-center justify-center gap-0.5 px-1 py-1.5 text-xs font-semibold ${
                  inAdmin || route === 'about' ? 'text-turquesa-dark' : 'text-gray-500'
                }`}
                trigger={
                  <>
                    <span className="rounded-full px-4 py-1">
                      <MoreHorizontal className="h-4 w-4" aria-hidden="true" />
                    </span>
                    <span>{t('navigation.more')}</span>
                  </>
                }
                items={[...admin.map(menuItem), ...(hasAbout ? [menuItem('about')] : [])]}
              />
            </li>
          )}
        </ul>
      </nav>
    </div>
  );
};
