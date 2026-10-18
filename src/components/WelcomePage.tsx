import React, { useEffect, useId, useState } from 'react';
import { KeyRound } from 'lucide-react';
import { t } from '../lib/i18n';
import { supabase } from '../lib/supabase';
import { DisabledReason, describedBy } from './DisabledReason';
import { VersionFooter } from './VersionFooter';

// Bienvenida (E16 fase C, ADR-0010): a donde lleva el enlace del correo de invitación (`/?bienvenida=1`). Supabase abre una
// sesión temporal con el enlace; aquí la persona elige su contraseña y, al terminar, esa sesión se cierra: para entrar usa su
// correo y su contraseña como cualquiera. Se muestra FUERA de la sesión normal a propósito: la persona aún no tiene ningún
// rol y la sesión normal la sacaría antes de poder elegir contraseña.
export const WELCOME_PARAM = 'bienvenida';
export const isWelcomeUrl = (search: string): boolean => new URLSearchParams(search).has(WELCOME_PARAM);

const MIN_LENGTH = 12;
const INPUT = 'min-h-11 w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-turquesa focus:outline-none';
const BTN_PRIMARY = 'inline-flex min-h-11 items-center gap-1.5 rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon shadow-sm hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50';

type Phase = 'checking' | 'ready' | 'expired' | 'done';

export const WelcomePage: React.FC = () => {
  const uid = useId();
  const [phase, setPhase] = useState<Phase>('checking');
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    // El cliente lee la sesión del enlace al iniciar; si no hay ninguna, el enlace venció o ya se usó.
    supabase.auth.getSession().then(({ data }) => {
      if (alive) setPhase(data.session ? 'ready' : 'expired');
    });
    return () => { alive = false; };
  }, []);

  const blocked = password.length < MIN_LENGTH ? t('welcome.too_short') : confirm !== password ? t('welcome.mismatch') : null;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (blocked || busy) return;
    setBusy(true);
    setError(null);
    const { error: err } = await supabase.auth.updateUser({ password });
    if (err) {
      setError(t('welcome.save_failed'));
      setBusy(false);
      return;
    }
    await supabase.auth.signOut();
    window.history.replaceState(null, '', window.location.pathname);
    setPhase('done');
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-50 p-4 font-sans text-carbon">
      <div className="w-full max-w-md">
        <div className="mb-6 flex items-center justify-center gap-3">
          <div className="flex h-12 w-12 items-center justify-center rounded bg-turquesa text-2xl font-bold text-carbon shadow">BV</div>
          <div>
            <h1 className="text-xl font-bold">{t('app.title')}</h1>
            <p className="text-xs text-gray-600">{t('app.tagline')}</p>
          </div>
        </div>

        {phase === 'checking' && <p className="text-center text-sm text-gray-600">{t('welcome.checking')}</p>}

        {phase === 'expired' && (
          <div className="space-y-3 rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
            <h2 className="text-base font-bold">{t('welcome.expired_title')}</h2>
            <p className="text-sm text-gray-700">{t('welcome.expired_body')}</p>
            <a className={BTN_PRIMARY} href="/">{t('welcome.go_login')}</a>
          </div>
        )}

        {phase === 'ready' && (
          <form onSubmit={submit} className="space-y-4 rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
            <h2 className="flex items-center gap-2 text-base font-bold">
              <KeyRound className="h-5 w-5 text-turquesa-dark" aria-hidden="true" />
              {t('welcome.title')}
            </h2>
            <p className="text-sm text-gray-700">{t('welcome.intro')}</p>
            <div>
              <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-p`}>{t('welcome.field_password')}</label>
              <input id={`${uid}-p`} name={`${uid}-p`} type="password" autoComplete="new-password" className={INPUT} value={password} onChange={(e) => setPassword(e.target.value)} />
              <p className="mt-1 text-xs text-gray-700">{t('welcome.rule')}</p>
            </div>
            <div>
              <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-c`}>{t('welcome.field_confirm')}</label>
              <input id={`${uid}-c`} name={`${uid}-c`} type="password" autoComplete="new-password" className={INPUT} value={confirm} onChange={(e) => setConfirm(e.target.value)} />
            </div>
            {error && <p role="alert" className="rounded-lg border border-alerta-dark/40 bg-alerta-bg/40 p-3 text-sm font-semibold text-alerta-dark">{error}</p>}
            <DisabledReason id={uid} reason={blocked} />
            <button type="submit" className={BTN_PRIMARY} disabled={!!blocked || busy} {...describedBy(uid, blocked)}>
              {busy ? t('welcome.saving') : t('welcome.submit')}
            </button>
          </form>
        )}

        {phase === 'done' && (
          <div className="space-y-3 rounded-xl border border-gray-200 bg-white p-6 shadow-sm">
            <h2 className="text-base font-bold">{t('welcome.done_title')}</h2>
            <p className="text-sm text-gray-700">{t('welcome.done_body')}</p>
            <a className={BTN_PRIMARY} href="/">{t('welcome.go_login')}</a>
          </div>
        )}
        <VersionFooter />
      </div>
    </div>
  );
};
