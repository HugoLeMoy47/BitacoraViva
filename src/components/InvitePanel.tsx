import React, { useCallback, useEffect, useState } from 'react';
import { MailPlus, Send } from 'lucide-react';
import { t } from '../lib/i18n';
import { friendlyError } from '../lib/errors';
import { supabase } from '../lib/supabase';
import { invitePerson } from '../lib/invitations';
import { useToast } from '../lib/toast';
import { formatDate } from '../lib/format';
import { DisabledReason, describedBy } from './DisabledReason';

// Invitar a una persona (E16 fase C, ADR-0010). La regla vive en la base (capacidad de gestionar el equipo, tope por hora,
// correo sin cuenta); la función de borde solo envía el correo. Invitar NO concede ningún rol: la persona entra sin rol y la
// dirección se lo otorga después, en la lista de abajo.
const INPUT = 'min-h-11 w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-turquesa focus:outline-none';
const BTN = 'inline-flex min-h-11 items-center gap-1.5 rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50';
const BTN_PRIMARY = 'inline-flex min-h-11 items-center gap-1.5 rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon shadow-sm hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50';

interface Invitation { id: string; email: string; full_name: string; invited_at: string }

export const InvitePanel: React.FC<{ onInvited: () => Promise<void> }> = ({ onInvited }) => {
  const toast = useToast();
  const [open, setOpen] = useState(false);
  const [list, setList] = useState<Invitation[] | null>(null);
  const [resending, setResending] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const { data } = await supabase
      .from('user_invitation')
      .select('id, email, full_name, invited_at')
      .order('invited_at', { ascending: false })
      .limit(20);
    setList((data ?? []) as Invitation[]);
  }, []);
  useEffect(() => { void load(); }, [load]);

  const resend = async (inv: Invitation) => {
    setResending(inv.id);
    setError(null);
    try {
      await invitePerson(inv.email, inv.full_name);
      toast.success(t('invite.resent'));
      await load();
    } catch (e) {
      setError(friendlyError(e));
    } finally {
      setResending(null);
    }
  };

  return (
    <section className="rounded-2xl border border-gray-200 bg-white p-5">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h3 className="text-base font-bold text-carbon">{t('invite.title')}</h3>
        <button type="button" className={BTN} aria-expanded={open} onClick={() => setOpen(!open)}>
          <MailPlus className="h-4 w-4" aria-hidden="true" />
          {t('invite.button')}
        </button>
      </div>
      {open && (
        <InviteForm
          onCancel={() => setOpen(false)}
          onDone={async () => { setOpen(false); await load(); await onInvited(); }}
        />
      )}
      {error && <p role="alert" className="mt-3 rounded-lg border border-alerta-dark/40 bg-alerta-bg/40 p-3 text-sm font-semibold text-alerta-dark">{error}</p>}
      <h4 className="mt-4 text-sm font-bold text-carbon">{t('invite.list_title')}</h4>
      {list && list.length === 0 && <p className="mt-1 text-sm text-gray-700">{t('invite.list_empty')}</p>}
      {list && list.length > 0 && (
        <>
          <ul className="mt-1 divide-y divide-gray-100">
            {list.map((inv) => (
              <li key={inv.id} className="flex flex-wrap items-center gap-2 py-2">
                <span className="min-w-0 flex-1 text-sm text-carbon">
                  <span className="font-semibold">{inv.full_name}</span> · {inv.email}
                  <span className="text-gray-600"> · {t('invite.sent_on')} {formatDate(inv.invited_at)}</span>
                </span>
                <button type="button" className={BTN} disabled={resending === inv.id} onClick={() => resend(inv)}>
                  <Send className="h-4 w-4" aria-hidden="true" />
                  {resending === inv.id ? t('invite.sending') : t('invite.resend')}
                </button>
              </li>
            ))}
          </ul>
          <p className="mt-2 text-xs text-gray-700">{t('invite.accepted_note')}</p>
        </>
      )}
    </section>
  );
};

const InviteForm: React.FC<{ onDone: () => Promise<void>; onCancel: () => void }> = ({ onDone, onCancel }) => {
  const uid = React.useId();
  const toast = useToast();
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const blocked = name.trim() === '' ? t('invite.reason_name') : email.trim() === '' ? t('invite.reason_email') : null;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (blocked || busy) return;
    setBusy(true);
    setError(null);
    try {
      const res = await invitePerson(email, name);
      toast.success(t(res.resend ? 'invite.resent' : 'invite.sent'));
      await onDone();
    } catch (err) {
      setError(friendlyError(err));
      setBusy(false);
    }
  };

  return (
    <form onSubmit={submit} className="mt-3 space-y-3 rounded-xl border border-gray-200 bg-gray-50 p-4">
      <p className="text-sm text-gray-700">{t('invite.hint')}</p>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <div>
          <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-n`}>{t('invite.field_name')}</label>
          <input id={`${uid}-n`} name={`${uid}-n`} autoComplete="off" className={INPUT} maxLength={120} value={name} onChange={(e) => setName(e.target.value)} />
        </div>
        <div>
          <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-e`}>{t('invite.field_email')}</label>
          <input id={`${uid}-e`} name={`${uid}-e`} type="email" autoComplete="off" className={INPUT} maxLength={254} value={email} onChange={(e) => setEmail(e.target.value)} />
        </div>
      </div>
      {error && <p role="alert" className="rounded-lg border border-alerta-dark/40 bg-alerta-bg/40 p-3 text-sm font-semibold text-alerta-dark">{error}</p>}
      <DisabledReason id={uid} reason={blocked} />
      <div className="flex flex-wrap gap-2">
        <button type="submit" className={BTN_PRIMARY} disabled={!!blocked || busy} {...describedBy(uid, blocked)}>{busy ? t('invite.sending') : t('invite.submit')}</button>
        <button type="button" className={BTN} onClick={onCancel}>{t('common.cancel')}</button>
      </div>
    </form>
  );
};
