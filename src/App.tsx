import React, { useState } from 'react';
import { 
  ShieldCheck, 
  Layers, 
  Users, 
  CheckCircle2, 
  AlertTriangle, 
  Building2, 
  Lock, 
  Database,
  History
} from 'lucide-react';
import { t } from './lib/i18n';
import { RoleName } from './types/database';
import { 
  DEMO_ORGANIZATION, 
  DEMO_ROLES, 
  DEMO_AREAS, 
  DEMO_USERS, 
  DEMO_AUDIT_EVENTS 
} from './lib/mockData';

export const App: React.FC = () => {
  const [activeRole, setActiveRole] = useState<RoleName>('director');
  const [activeTab, setActiveTab] = useState<'overview' | 'areas' | 'audit' | 'rules'>('overview');

  const currentUser = DEMO_USERS[activeRole];

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col text-carbon font-sans">
      {/* Header Superior con Branding Freejolitos */}
      <header className="bg-carbon text-white border-b-4 border-turquesa sticky top-0 z-50">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-3 flex flex-wrap items-center justify-between gap-4">
          <div className="flex items-center space-x-3">
            <div className="w-10 h-10 rounded bg-turquesa text-carbon flex items-center justify-center font-bold text-xl shadow">
              BV
            </div>
            <div>
              <div className="flex items-center space-x-2">
                <h1 className="text-xl font-bold tracking-tight text-white">{t('app.title')}</h1>
                <span className="bg-turquesa/20 text-turquesa-light text-xs font-semibold px-2 py-0.5 rounded border border-turquesa/30">
                  {t('app.badge_poc')}
                </span>
              </div>
              <p className="text-xs text-gray-400">{t('app.tagline')}</p>
            </div>
          </div>

          <div className="flex items-center gap-3">
            <div className="hidden md:flex items-center bg-carbon-light px-3 py-1.5 rounded-full border border-gray-700 text-xs text-turquesa-light">
              <ShieldCheck className="w-4 h-4 mr-1.5 text-turquesa" />
              {t('app.ethos_commitment')}
            </div>
            <div className="flex items-center bg-gray-800 text-xs text-gray-300 px-3 py-1 rounded border border-gray-700">
              <Database className="w-3.5 h-3.5 mr-1.5 text-turquesa" />
              {t('session.mode_emulation')}
            </div>
          </div>
        </div>
      </header>

      {/* Barra de simulación de roles (Switch de 4 roles) */}
      <div className="bg-white border-b border-gray-200 shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-3">
          <div className="flex flex-col md:flex-row items-start md:items-center justify-between gap-3">
            <div className="flex items-center space-x-2">
              <Users className="w-4 h-4 text-turquesa-dark" />
              <span className="text-xs font-bold text-carbon-muted uppercase tracking-wider">
                {t('session.switch_role')}
              </span>
            </div>

            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 w-full md:w-auto">
              {DEMO_ROLES.map((r) => {
                const isSelected = activeRole === r.name;
                return (
                  <button
                    key={r.name}
                    onClick={() => setActiveRole(r.name)}
                    className={`px-3 py-2 text-xs font-semibold rounded-lg border transition-all text-left flex items-center justify-between ${
                      isSelected
                        ? 'bg-claro border-turquesa text-carbon shadow-sm'
                        : 'bg-white border-gray-200 text-gray-600 hover:bg-gray-50'
                    }`}
                  >
                    <span>{t(`roles.${r.name}.title`)}</span>
                    {isSelected && <span className="w-2 h-2 rounded-full bg-turquesa ml-2" />}
                  </button>
                );
              })}
            </div>
          </div>

          {/* Banner de contexto del usuario simulado */}
          <div className="mt-3 bg-gray-50 rounded-lg p-3 border border-gray-200 flex flex-col sm:flex-row sm:items-center justify-between text-xs gap-2">
            <div className="flex items-center space-x-2">
              <span className="font-semibold text-carbon">{currentUser.profile.full_name}</span>
              <span className="text-gray-400">({currentUser.profile.email})</span>
              <span className="bg-gray-200 text-carbon px-2 py-0.5 rounded font-mono text-[11px]">
                {t(`roles.${activeRole}.badge`)}
              </span>
            </div>
            <p className="text-carbon-muted italic text-[11px]">
              {t(`roles.${activeRole}.description`)}
            </p>
          </div>
        </div>
      </div>

      {/* Contenedor Principal */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6 flex-1 w-full">
        {/* Pestañas de Navegación */}
        <div className="flex space-x-2 border-b border-gray-200 mb-6">
          <button
            onClick={() => setActiveTab('overview')}
            className={`pb-3 px-4 text-sm font-semibold border-b-2 flex items-center gap-2 ${
              activeTab === 'overview'
                ? 'border-turquesa text-carbon'
                : 'border-transparent text-gray-500 hover:text-carbon'
            }`}
          >
            <Building2 className="w-4 h-4" />
            {t('navigation.overview')}
          </button>
          <button
            onClick={() => setActiveTab('areas')}
            className={`pb-3 px-4 text-sm font-semibold border-b-2 flex items-center gap-2 ${
              activeTab === 'areas'
                ? 'border-turquesa text-carbon'
                : 'border-transparent text-gray-500 hover:text-carbon'
            }`}
          >
            <Layers className="w-4 h-4" />
            {t('navigation.areas')}
          </button>
          <button
            onClick={() => setActiveTab('audit')}
            className={`pb-3 px-4 text-sm font-semibold border-b-2 flex items-center gap-2 ${
              activeTab === 'audit'
                ? 'border-turquesa text-carbon'
                : 'border-transparent text-gray-500 hover:text-carbon'
            }`}
          >
            <History className="w-4 h-4" />
            {t('navigation.audit_trail')}
          </button>
          <button
            onClick={() => setActiveTab('rules')}
            className={`pb-3 px-4 text-sm font-semibold border-b-2 flex items-center gap-2 ${
              activeTab === 'rules'
                ? 'border-turquesa text-carbon'
                : 'border-transparent text-gray-500 hover:text-carbon'
            }`}
          >
            <Lock className="w-4 h-4" />
            {t('navigation.rules')}
          </button>
        </div>

        {/* Tab 1: Resumen de Tenancy y Seguridad */}
        {activeTab === 'overview' && (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div className="bg-white p-6 rounded-xl border border-gray-200 shadow-sm">
              <div className="flex items-center space-x-3 mb-4">
                <div className="p-2 bg-claro rounded-lg text-turquesa-dark">
                  <Building2 className="w-5 h-5" />
                </div>
                <h2 className="text-base font-bold text-carbon">{t('dashboard.organization_details')}</h2>
              </div>
              <dl className="space-y-3 text-sm">
                <div>
                  <dt className="text-gray-500 text-xs font-medium">{t('dashboard.org_display')}</dt>
                  <dd className="font-semibold text-carbon text-lg">{DEMO_ORGANIZATION.display_name}</dd>
                </div>
                <div>
                  <dt className="text-gray-500 text-xs font-medium">{t('dashboard.org_legal')}</dt>
                  <dd className="text-carbon">{DEMO_ORGANIZATION.legal_name}</dd>
                </div>
                <div>
                  <dt className="text-gray-500 text-xs font-medium">{t('dashboard.org_slug')}</dt>
                  <dd className="font-mono text-xs bg-gray-100 p-1.5 rounded inline-block text-gray-800">
                    {DEMO_ORGANIZATION.slug}
                  </dd>
                </div>
                <div className="pt-2 border-t border-gray-100 flex items-center justify-between text-xs">
                  <span className="text-gray-500">Estado Multi-Tenant:</span>
                  <span className="bg-green-100 text-green-800 px-2 py-0.5 rounded-full font-medium">
                    {t('dashboard.active_badge')}
                  </span>
                </div>
              </dl>
            </div>

            <div className="bg-white p-6 rounded-xl border border-gray-200 shadow-sm flex flex-col justify-between">
              <div>
                <div className="flex items-center space-x-3 mb-4">
                  <div className="p-2 bg-claro rounded-lg text-turquesa-dark">
                    <ShieldCheck className="w-5 h-5" />
                  </div>
                  <h2 className="text-base font-bold text-carbon">{t('dashboard.security_status')}</h2>
                </div>
                <p className="text-sm text-carbon-muted leading-relaxed">
                  {t('dashboard.security_status_desc')}
                </p>
                <div className="mt-4 bg-alerta-bg border border-alerta/20 p-3 rounded-lg text-xs text-alerta flex items-start space-x-2">
                  <AlertTriangle className="w-4 h-4 flex-shrink-0 mt-0.5" />
                  <span>
                    El motor de base de datos tiene activo el disparador <code>trg_prevent_audit_tampering</code>: ningún usuario, ni siquiera un director, puede alterar o eliminar registros de auditoría.
                  </span>
                </div>
              </div>

              <div className="mt-6 pt-4 border-t border-gray-100 grid grid-cols-2 gap-4 text-center">
                <div className="bg-gray-50 p-3 rounded-lg">
                  <span className="block text-2xl font-bold text-carbon">{DEMO_AREAS.length}</span>
                  <span className="text-[11px] text-gray-500">{t('dashboard.total_areas')}</span>
                </div>
                <div className="bg-gray-50 p-3 rounded-lg">
                  <span className="block text-2xl font-bold text-turquesa-dark">{DEMO_ROLES.length}</span>
                  <span className="text-[11px] text-gray-500">{t('dashboard.total_roles')}</span>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Tab 2: Áreas del Albergue */}
        {activeTab === 'areas' && (
          <div className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden">
            <div className="px-6 py-4 border-b border-gray-200">
              <h2 className="text-base font-bold text-carbon">{t('dashboard.areas_title')}</h2>
            </div>
            <div className="divide-y divide-gray-100">
              {DEMO_AREAS.map((area) => (
                <div key={area.id} className="p-4 sm:px-6 flex items-center justify-between hover:bg-gray-50 transition-colors">
                  <div className="flex items-center space-x-3">
                    <div className="w-8 h-8 rounded-full bg-claro text-turquesa-dark flex items-center justify-center font-bold text-xs">
                      {area.code.substring(0, 2).toUpperCase()}
                    </div>
                    <div>
                      <h3 className="text-sm font-semibold text-carbon">{area.name}</h3>
                      <p className="text-xs text-gray-400 font-mono">code: {area.code}</p>
                    </div>
                  </div>
                  <span className="bg-green-100 text-green-800 text-xs px-2.5 py-0.5 rounded-full font-medium">
                    {t('dashboard.active_badge')}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Tab 3: Registro de Auditoría Inmutable */}
        {activeTab === 'audit' && (
          <div className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden">
            <div className="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
              <div>
                <h2 className="text-base font-bold text-carbon">{t('dashboard.audit_title')}</h2>
                <p className="text-xs text-gray-500">Gobernanza C4: Append-only estricto por trigger en PostgreSQL</p>
              </div>
              <span className="text-xs font-mono bg-claro text-carbon px-2 py-1 rounded border border-turquesa/30">
                {DEMO_AUDIT_EVENTS.length} eventos
              </span>
            </div>
            <div className="overflow-x-auto">
              <table className="min-w-full divide-y divide-gray-200 text-xs">
                <thead className="bg-gray-50 text-gray-500 font-medium uppercase">
                  <tr>
                    <th className="px-6 py-3 text-left">{t('dashboard.table_column_action')}</th>
                    <th className="px-6 py-3 text-left">{t('dashboard.table_column_table')}</th>
                    <th className="px-6 py-3 text-left">{t('dashboard.table_column_record')}</th>
                    <th className="px-6 py-3 text-left">{t('dashboard.table_column_timestamp')}</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100 bg-white">
                  {DEMO_AUDIT_EVENTS.map((event) => (
                    <tr key={event.id} className="hover:bg-gray-50 font-mono">
                      <td className="px-6 py-3 whitespace-nowrap">
                        <span className="px-2 py-0.5 bg-gray-100 text-carbon font-bold rounded text-[11px] border border-gray-300">
                          {event.action}
                        </span>
                      </td>
                      <td className="px-6 py-3 text-carbon font-semibold">{event.table_name}</td>
                      <td className="px-6 py-3 text-gray-500 truncate max-w-xs">{event.record_id}</td>
                      <td className="px-6 py-3 text-gray-400">{event.created_at}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {/* Tab 4: 10 Reglas Duras */}
        {activeTab === 'rules' && (
          <div className="bg-white p-6 rounded-xl border border-gray-200 shadow-sm">
            <h2 className="text-base font-bold text-carbon mb-2">Las 10 Reglas Duras de Supabase</h2>
            <p className="text-xs text-gray-500 mb-6">
              Contrato de handoff inmutable. Violarlas constituye un defecto estructural, no una diferencia de criterio.
            </p>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              {Array.from({ length: 10 }).map((_, i) => {
                const key = `r${i + 1}`;
                return (
                  <div key={key} className="flex items-start space-x-3 p-3 rounded-lg bg-gray-50 border border-gray-200">
                    <CheckCircle2 className="w-5 h-5 text-turquesa flex-shrink-0 mt-0.5" />
                    <span className="text-xs text-carbon font-medium">
                      {t(`rules_list.${key}`)}
                    </span>
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </main>

      {/* Footer */}
      <footer className="bg-white border-t border-gray-200 py-4 text-center text-xs text-gray-500">
        <p>Bitácora Viva · Plataforma libre para la dignidad y soberanía informativa de la sociedad civil.</p>
      </footer>
    </div>
  );
};

export default App;
