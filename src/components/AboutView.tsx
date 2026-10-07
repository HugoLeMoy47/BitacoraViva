import React from 'react';
import { Building2, CheckCircle2, ShieldCheck, Users } from 'lucide-react';
import { t } from '../lib/i18n';
import { Organization } from '../types/database';
import { ROLE_NAMES, ROUTE_LABEL_KEY, routesOfRole } from '../lib/navigation';

// «Acerca de»: material de presentación de la demo (organización, protección de la información,
// qué ve cada rol y las reglas duras). Sólo existe en entorno demo (ver lib/navigation.ts).
export const AboutView: React.FC<{ organization: Organization | null; areasCount: number }> = ({
  organization,
  areasCount,
}) => (
  <div className="space-y-6">
    <div>
      <h2 className="text-lg font-bold text-carbon">{t('about.title')}</h2>
      <p className="text-sm text-gray-600">{t('about.subtitle')}</p>
    </div>

    <div className="grid grid-cols-1 gap-6 md:grid-cols-2">
      <section className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
        <div className="mb-4 flex items-center gap-3">
          <span className="rounded-lg bg-claro p-2 text-turquesa-dark" aria-hidden="true">
            <Building2 className="h-5 w-5" />
          </span>
          <h3 className="text-base font-bold text-carbon">{t('dashboard.organization_details')}</h3>
        </div>
        <dl className="space-y-3 text-sm">
          <div>
            <dt className="text-xs font-medium text-gray-500">{t('dashboard.org_display')}</dt>
            <dd className="text-lg font-semibold text-carbon">{organization?.display_name}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium text-gray-500">{t('dashboard.org_legal')}</dt>
            <dd className="text-carbon">{organization?.legal_name}</dd>
          </div>
          <div>
            <dt className="text-xs font-medium text-gray-500">{t('dashboard.org_slug')}</dt>
            <dd className="inline-block rounded bg-gray-100 p-1.5 font-mono text-xs text-gray-800">{organization?.slug}</dd>
          </div>
          <div className="flex items-center justify-between border-t border-gray-100 pt-2 text-xs">
            <span className="text-gray-500">{t('about.multi_tenant')}</span>
            <span className="rounded-full bg-green-100 px-2 py-0.5 font-medium text-green-800">{t('dashboard.active_badge')}</span>
          </div>
        </dl>
      </section>

      <section className="flex flex-col justify-between rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
        <div>
          <div className="mb-4 flex items-center gap-3">
            <span className="rounded-lg bg-claro p-2 text-turquesa-dark" aria-hidden="true">
              <ShieldCheck className="h-5 w-5" />
            </span>
            <h3 className="text-base font-bold text-carbon">{t('about.security_title')}</h3>
          </div>
          <p className="text-sm leading-relaxed text-carbon-muted">{t('dashboard.security_status_desc')}</p>
          <p className="mt-4 rounded-lg border border-alerta/20 bg-alerta-bg p-3 text-xs text-alerta">{t('about.audit_lock')}</p>
        </div>
        <dl className="mt-6 grid grid-cols-2 gap-4 border-t border-gray-100 pt-4 text-center">
          <div className="rounded-lg bg-gray-50 p-3">
            <dd className="text-2xl font-bold text-carbon">{areasCount}</dd>
            <dt className="text-xs text-gray-500">{t('dashboard.total_areas')}</dt>
          </div>
          <div className="rounded-lg bg-gray-50 p-3">
            <dd className="text-2xl font-bold text-turquesa-dark">{ROLE_NAMES.length}</dd>
            <dt className="text-xs text-gray-500">{t('dashboard.total_roles')}</dt>
          </div>
        </dl>
      </section>
    </div>

    <section className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
      <div className="mb-1 flex items-center gap-3">
        <span className="rounded-lg bg-claro p-2 text-turquesa-dark" aria-hidden="true">
          <Users className="h-5 w-5" />
        </span>
        <h3 className="text-base font-bold text-carbon">{t('about.roles_title')}</h3>
      </div>
      <p className="mb-4 text-xs text-gray-500">{t('about.roles_note')}</p>
      <ul className="grid grid-cols-1 gap-3 md:grid-cols-2">
        {ROLE_NAMES.map((role) => (
          <li key={role} className="rounded-lg border border-gray-200 bg-gray-50 p-4">
            <p className="text-sm font-bold text-carbon">{t(`roles.${role}.title`)}</p>
            <p className="mb-2 text-xs italic text-gray-500">{t(`roles.${role}.description`)}</p>
            <p className="text-xs text-gray-700">
              <span className="font-semibold">{t('about.sees')} </span>
              {routesOfRole(role)
                .map((r) => t(ROUTE_LABEL_KEY[r]))
                .join(' · ')}
            </p>
          </li>
        ))}
      </ul>
    </section>

    <section className="rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
      <h3 className="mb-1 text-base font-bold text-carbon">{t('about.rules_title')}</h3>
      <p className="mb-5 text-xs text-gray-500">{t('about.rules_intro')}</p>
      <ol className="grid grid-cols-1 gap-3 md:grid-cols-2">
        {Array.from({ length: 10 }).map((_, i) => (
          <li key={i} className="flex items-start gap-3 rounded-lg border border-gray-200 bg-gray-50 p-3">
            <CheckCircle2 className="mt-0.5 h-5 w-5 shrink-0 text-turquesa" aria-hidden="true" />
            <span className="text-xs font-medium text-carbon">{t(`rules_list.r${i + 1}`)}</span>
          </li>
        ))}
      </ol>
    </section>

    <p className="text-center text-xs text-gray-500">{t('about.tagline')}</p>
  </div>
);
