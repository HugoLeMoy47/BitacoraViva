import React, { useState } from 'react';
import { LogIn, ShieldCheck, Zap } from 'lucide-react';
import { t } from '../lib/i18n';
import { useSession } from '../lib/session';
import { useEnvironment } from '../lib/environment';
import { RoleName } from '../types/database';

// Cuentas semilla de demostración (supabase/seed.sql). Sólo se ofrecen en modo demo.
const DEMO_PASSWORD = 'albergue2026!';
const DEMO_ACCOUNTS: { role: RoleName; email: string }[] = [
  { role: 'director', email: 'director@alberguesantafe.org' },
  { role: 'caseworker', email: 'caseworker@alberguesantafe.org' },
  { role: 'intake_officer', email: 'intake@alberguesantafe.org' },
  { role: 'viewer', email: 'viewer@alberguesantafe.org' },
];

export const LoginView: React.FC = () => {
  const { signIn, notice } = useSession();
  const { isDemo, allowDemoAccounts } = useEnvironment();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async (e: React.FormEvent, em = email, pw = password) => {
    e.preventDefault();
    setBusy(true);
    await signIn(em, pw);
    setBusy(false);
  };

  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center p-4 text-carbon font-sans">
      <div className="w-full max-w-md">
        <div className="flex items-center justify-center gap-3 mb-6">
          <div className="w-12 h-12 rounded bg-turquesa text-carbon flex items-center justify-center font-bold text-2xl shadow">
            BV
          </div>
          <div>
            <h1 className="text-xl font-bold">{t('app.title')}</h1>
            <p className="text-xs text-gray-500">{t('app.tagline')}</p>
          </div>
        </div>

        <form
          onSubmit={submit}
          className="bg-white rounded-xl border border-gray-200 shadow-sm p-6 space-y-4"
        >
          <h2 className="text-base font-bold flex items-center gap-2">
            <ShieldCheck className="w-5 h-5 text-turquesa-dark" />
            {t('login.title')}
          </h2>

          {isDemo && (
            <p className="bg-amber-50 border border-amber-300 text-amber-900 text-xs rounded-lg p-3">
              {t('demo.login_notice')}
            </p>
          )}

          {notice && (
            <div role="alert" className="bg-alerta-bg border border-alerta/20 text-alerta-dark text-xs rounded-lg p-3">
              {t(notice)}
            </div>
          )}

          <label className="block text-xs font-semibold text-gray-600">
            {t('login.email')}
            <input
              type="email"
              autoComplete="username"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-turquesa"
            />
          </label>
          <label className="block text-xs font-semibold text-gray-600">
            {t('login.password')}
            <input
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-turquesa"
            />
          </label>

          <button
            type="submit"
            disabled={busy}
            className="w-full flex items-center justify-center gap-2 rounded-lg bg-carbon text-white text-sm font-semibold py-2.5 hover:bg-carbon-light disabled:opacity-60"
          >
            <LogIn className="w-4 h-4" />
            {busy ? t('login.signing_in') : t('login.submit')}
          </button>
        </form>

        {allowDemoAccounts && (
        <div className="mt-4 bg-white rounded-xl border border-gray-200 shadow-sm p-4">
          <p className="text-xs font-bold text-gray-600 flex items-center gap-1.5 mb-1">
            <Zap className="w-3.5 h-3.5 text-turquesa-dark" />
            {t('login.demo_title')}
          </p>
          <p className="text-xs text-gray-500 mb-3">{t('login.demo_hint')}</p>
          <div className="grid grid-cols-2 gap-2">
            {DEMO_ACCOUNTS.map((a) => (
              <button
                key={a.role}
                type="button"
                disabled={busy}
                onClick={(e) => submit(e, a.email, DEMO_PASSWORD)}
                className="px-3 py-2 text-xs font-semibold rounded-lg border border-gray-200 bg-white text-gray-700 hover:bg-claro hover:border-turquesa text-left disabled:opacity-60"
              >
                {t(`roles.${a.role}.title`)}
              </button>
            ))}
          </div>
        </div>
        )}
      </div>
    </div>
  );
};
