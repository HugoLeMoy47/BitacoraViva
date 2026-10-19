import React, { useState } from 'react';
import { MailPlus } from 'lucide-react';
import { t } from '../lib/i18n';
import { friendlyError } from '../lib/errors';
import { invitePerson } from '../lib/invitations';
import { useToast } from '../lib/toast';
import { DisabledReason, describedBy } from './DisabledReason';

// Invitar a una persona (E16 fase C, ADR-0010). La regla vive en la base (capacidad de gestionar el equipo, tope por hora,
// correo sin cuenta); la función de borde solo envía el correo. Invitar NO concede ningún rol: la persona entra sin rol y la
// dirección se lo otorga después, desde su panel en la tabla de «Equipo» (donde también aparece como «Invitación enviada»).
const INPUT = 'min-h-11 w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-turquesa focus:outline-none';
const BTN = 'inline-flex min-h-11 items-center gap-1.5 rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50';
const BTN_PRIMARY = 'inline-flex min-h-11 items-center gap-1.5 rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon shadow-sm hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50';

export const InvitePanel: React.FC<{ onInvited: () => Promise<void> }> = ({ onInvited }) => {
  const [open, setOpen] = useState(false);
  return (
    <section>
      <button type="button" className={BTN} aria-expanded={open} onClick={() => setOpen(!open)}>
        <MailPlus className="h-4 w-4" aria-hidden="true" />
        {t('invite.button')}
      </button>
      {open && (
        <InviteForm
          onCancel={() => setOpen(false)}
          onDone={async () => { setOpen(false); await onInvited(); }}
        />
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
