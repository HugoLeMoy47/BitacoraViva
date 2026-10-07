import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Building2, FileText, ShieldCheck } from 'lucide-react';
import { t } from '../lib/i18n';
import { formatDate } from '../lib/format';
import { listConsentTexts, listPrivacyNotices, OrganizationIdentityInput } from '../lib/data';
import { ConsentText, ConsentType, Organization, PrivacyNotice } from '../types/database';
import { Tabs } from './Tabs';

// Configuración de la organización (E9). La plataforma ofrece el mecanismo (versionado, bloqueo,
// auditoría); cada asociación declara su contenido y responde por él. Solo Dirección entra aquí
// y la base lo vuelve a exigir.
type Result = Promise<{ ok: boolean }>;

interface Props {
  organization: Organization | null;
  busy: boolean;
  onSaveIdentity: (input: OrganizationIdentityInput) => Result;
  onPublishNotice: (title: string, summary: string, fullText: string) => Result;
  onPublishConsentText: (type: ConsentType, title: string, description: string, required: boolean) => Result;
}

// Consentimientos que se configuran. «internal_sharing» no se pide por separado (lo cubre el aviso general).
const CONFIGURABLE: ConsentType[] = ['general_care', 'sensitive_data', 'secondary_use_research'];

const FIELD =
  'mt-1 w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-turquesa focus:border-turquesa';
const LABEL = 'block text-xs font-semibold text-gray-600';
const HINT = 'mt-1 text-xs text-gray-500';
const BTN =
  'rounded-lg bg-turquesa px-5 py-2 text-sm font-semibold text-carbon shadow-sm hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50';

type TabId = 'identity' | 'notice' | 'consents';

export const ConfigurationView: React.FC<Props> = ({ organization, busy, onSaveIdentity, onPublishNotice, onPublishConsentText }) => {
  const [tab, setTab] = useState<TabId>('identity');
  const [notices, setNotices] = useState<PrivacyNotice[] | null>(null);
  const [texts, setTexts] = useState<ConsentText[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);

  const loadVersions = useCallback(async () => {
    try {
      const [n, c] = await Promise.all([listPrivacyNotices(), listConsentTexts()]);
      setNotices(n);
      setTexts(c);
      setLoadError(null);
    } catch (e) {
      setLoadError(e instanceof Error ? e.message : String(e));
    }
  }, []);

  useEffect(() => {
    void loadVersions();
  }, [loadVersions]);

  // Tras publicar, vuelve a leer el historial
  const after = async (r: Result) => {
    const res = await r;
    if (res.ok) await loadVersions();
    return res;
  };

  return (
    <section className="space-y-4">
      <div>
        <h2 className="text-lg font-bold text-carbon">{t('config.title')}</h2>
        <p className="text-xs text-gray-500">{t('config.subtitle')}</p>
      </div>

      <div className="rounded-xl border border-gray-200 bg-white shadow-sm">
        <Tabs
          bare
          ariaLabel={t('config.tabs_label')}
          value={tab}
          onChange={(id) => setTab(id as TabId)}
          items={[
            { id: 'identity', label: t('config.tab_identity'), icon: <Building2 className="h-4 w-4" aria-hidden="true" /> },
            { id: 'notice', label: t('config.tab_notice'), icon: <FileText className="h-4 w-4" aria-hidden="true" /> },
            { id: 'consents', label: t('config.tab_consents'), icon: <ShieldCheck className="h-4 w-4" aria-hidden="true" /> },
          ]}
          className="border-b border-gray-200 px-2"
        />
        <div className="p-4 sm:p-5" role="tabpanel">
          {loadError && (
            <p role="alert" className="mb-3 text-xs text-alerta-dark">{loadError}</p>
          )}
          {tab === 'identity' && <IdentityForm organization={organization} busy={busy} onSave={onSaveIdentity} />}
          {tab === 'notice' && (
            <NoticeForm
              notices={notices}
              busy={busy}
              onPublish={(ti, su, fu) => after(onPublishNotice(ti, su, fu))}
            />
          )}
          {tab === 'consents' && (
            <div className="space-y-4">
              <p className="text-xs text-gray-600">{t('config.consents.intro')}</p>
              {CONFIGURABLE.map((type) => (
                <ConsentCard
                  key={type}
                  type={type}
                  versions={(texts ?? []).filter((x) => x.consent_type === type)}
                  busy={busy}
                  onPublish={(ti, de, re) => after(onPublishConsentText(type, ti, de, re))}
                />
              ))}
            </div>
          )}
        </div>
      </div>
    </section>
  );
};

// ---------------------------------------------------------------- Identidad
const IdentityForm: React.FC<{
  organization: Organization | null;
  busy: boolean;
  onSave: (input: OrganizationIdentityInput) => Result;
}> = ({ organization, busy, onSave }) => {
  const initial = useMemo<OrganizationIdentityInput>(
    () => ({
      display_name: organization?.display_name ?? '',
      legal_name: organization?.legal_name ?? '',
      folio_prefix: organization?.folio_prefix ?? '',
      about_text: organization?.about_text ?? '',
      responsible_name: organization?.responsible_name ?? '',
      responsible_address: organization?.responsible_address ?? '',
      responsible_contact: organization?.responsible_contact ?? '',
      arco_contact: organization?.arco_contact ?? '',
    }),
    [organization]
  );
  const [form, setForm] = useState<OrganizationIdentityInput>(initial);
  useEffect(() => setForm(initial), [initial]);

  const set = (k: keyof OrganizationIdentityInput) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
    setForm((f) => ({ ...f, [k]: e.target.value }));

  const prefixOk = form.folio_prefix === '' || /^[A-Za-z]{2,5}$/.test(form.folio_prefix);
  const valid = form.display_name.trim() !== '' && form.legal_name.trim() !== '' && prefixOk;
  const dirty = JSON.stringify(form) !== JSON.stringify(initial);
  const nextFolio = `${(form.folio_prefix || organization?.slug?.slice(0, 3) || 'BV').toUpperCase()}-${new Date().getFullYear()}-0001`;

  return (
    <form
      className="space-y-4"
      onSubmit={(e) => {
        e.preventDefault();
        if (valid && dirty && !busy) void onSave({ ...form, folio_prefix: form.folio_prefix.toUpperCase() });
      }}
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <label className={LABEL}>
          {t('config.identity.display_name')}
          <input className={FIELD} value={form.display_name} onChange={set('display_name')} required autoComplete="off" />
          <span className={HINT}>{t('config.identity.display_name_hint')}</span>
        </label>
        <label className={LABEL}>
          {t('config.identity.legal_name')}
          <input className={FIELD} value={form.legal_name} onChange={set('legal_name')} required autoComplete="off" />
          <span className={HINT}>{t('config.identity.legal_name_hint')}</span>
        </label>
        <label className={LABEL}>
          {t('config.identity.folio_prefix')}
          <input
            className={`${FIELD} uppercase`}
            value={form.folio_prefix}
            onChange={set('folio_prefix')}
            maxLength={5}
            autoComplete="off"
            placeholder={t('config.identity.folio_prefix_placeholder')}
            aria-invalid={!prefixOk}
          />
          <span className={prefixOk ? HINT : 'mt-1 block text-xs text-alerta-dark'}>
            {prefixOk ? t('config.identity.folio_prefix_hint').replace('{folio}', nextFolio) : t('config.identity.folio_prefix_error')}
          </span>
        </label>
        <label className={LABEL}>
          {t('config.identity.responsible_name')}
          <input className={FIELD} value={form.responsible_name} onChange={set('responsible_name')} autoComplete="off" />
        </label>
        <label className={LABEL}>
          {t('config.identity.responsible_address')}
          <input className={FIELD} value={form.responsible_address} onChange={set('responsible_address')} autoComplete="off" />
        </label>
        <label className={LABEL}>
          {t('config.identity.responsible_contact')}
          <input className={FIELD} value={form.responsible_contact} onChange={set('responsible_contact')} autoComplete="off" />
        </label>
        <label className={`${LABEL} sm:col-span-2`}>
          {t('config.identity.arco_contact')}
          <input className={FIELD} value={form.arco_contact} onChange={set('arco_contact')} autoComplete="off" />
          <span className={HINT}>{t('config.identity.arco_contact_hint')}</span>
        </label>
        <label className={`${LABEL} sm:col-span-2`}>
          {t('config.identity.about')}
          <textarea className={FIELD} rows={3} value={form.about_text} onChange={set('about_text')} />
        </label>
      </div>
      <div className="flex justify-end">
        <button type="submit" disabled={!valid || !dirty || busy} className={BTN}>
          {t('config.identity.save')}
        </button>
      </div>
    </form>
  );
};

// ---------------------------------------------------------------- Aviso de privacidad
const NoticeForm: React.FC<{
  notices: PrivacyNotice[] | null;
  busy: boolean;
  onPublish: (title: string, summary: string, fullText: string) => Result;
}> = ({ notices, busy, onPublish }) => {
  const current = notices?.find((n) => n.active) ?? null;
  const [title, setTitle] = useState('');
  const [summary, setSummary] = useState('');
  const [fullText, setFullText] = useState('');
  const [confirm, setConfirm] = useState(false);

  // El borrador parte del aviso vigente: se edita y se publica como versión nueva
  useEffect(() => {
    if (current) {
      setTitle(current.title);
      setSummary(current.summary);
      setFullText(current.full_text);
    }
  }, [current?.id]);

  const valid = title.trim() !== '' && summary.trim() !== '' && fullText.trim() !== '';
  const changed = !current || title !== current.title || summary !== current.summary || fullText !== current.full_text;

  return (
    <div className="space-y-5">
      <p className="text-xs text-gray-600">{t('config.notice.intro')}</p>

      <div className="rounded-lg border border-gray-200 bg-gray-50 p-3 text-xs text-gray-700">
        {notices === null ? (
          t('session.loading')
        ) : current ? (
          <>
            <strong className="text-carbon">{t('config.notice.current')}</strong>{' '}
            {t('intake.consent.version_label')} {current.version} · {t('config.notice.since').replace('{date}', formatDate(current.effective_date))}
          </>
        ) : (
          <span className="text-alerta-dark">{t('config.notice.none')}</span>
        )}
      </div>

      <form
        className="space-y-3"
        onSubmit={(e) => {
          e.preventDefault();
          if (valid && changed && confirm && !busy) {
            void onPublish(title, summary, fullText).then((r) => r.ok && setConfirm(false));
          }
        }}
      >
        <label className={LABEL}>
          {t('config.notice.field_title')}
          <input className={FIELD} value={title} onChange={(e) => setTitle(e.target.value)} required autoComplete="off" />
        </label>
        <label className={LABEL}>
          {t('config.notice.field_summary')}
          <textarea className={FIELD} rows={2} value={summary} onChange={(e) => setSummary(e.target.value)} required />
          <span className={HINT}>{t('config.notice.field_summary_hint')}</span>
        </label>
        <label className={LABEL}>
          {t('config.notice.field_full')}
          <textarea className={FIELD} rows={8} value={fullText} onChange={(e) => setFullText(e.target.value)} required />
          <span className={HINT}>{t('config.notice.field_full_hint')}</span>
        </label>
        <label className="flex min-h-9 items-start gap-2 text-xs text-gray-700">
          <input type="checkbox" checked={confirm} onChange={(e) => setConfirm(e.target.checked)} className="mt-0.5 rounded border-gray-300 text-turquesa" />
          <span>{t('config.notice.confirm')}</span>
        </label>
        <div className="flex justify-end">
          <button type="submit" disabled={!valid || !changed || !confirm || busy} className={BTN}>
            {t('config.notice.publish')}
          </button>
        </div>
      </form>

      {notices && notices.length > 0 && (
        <div>
          <h3 className="mb-2 text-sm font-bold text-carbon">{t('config.history')}</h3>
          <ul className="space-y-2">
            {notices.map((n) => (
              <li key={n.id}>
                <details className="rounded-lg border border-gray-200 bg-white">
                  <summary className="flex cursor-pointer flex-wrap items-center gap-x-2 px-3 py-2 text-xs font-semibold text-carbon">
                    <span>{t('intake.consent.version_label')} {n.version}</span>
                    <span className="font-normal text-gray-500">{formatDate(n.effective_date)}</span>
                    {n.active && <span className="rounded bg-claro px-1.5 font-normal text-turquesa-dark">{t('cases.history.current')}</span>}
                  </summary>
                  <div className="space-y-2 border-t border-gray-200 px-3 py-3 text-xs text-gray-700">
                    <p className="font-semibold text-carbon">{n.title}</p>
                    <p>{n.summary}</p>
                    <p className="max-h-40 overflow-y-auto whitespace-pre-line rounded bg-gray-50 p-2">{n.full_text}</p>
                  </div>
                </details>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
};

// ---------------------------------------------------------------- Consentimientos
const ConsentCard: React.FC<{
  type: ConsentType;
  versions: ConsentText[];
  busy: boolean;
  onPublish: (title: string, description: string, required: boolean) => Result;
}> = ({ type, versions, busy, onPublish }) => {
  const current = versions.find((v) => v.active) ?? null;
  const alwaysRequired = type === 'general_care';
  // Sin versión publicada, el borrador parte del texto base de la plataforma (ejemplo, no asesoría legal)
  const baseTitle = t(`arco.consent_types.${type}`);
  const baseDescription = t(`intake.consent.desc.${type}`);
  const [title, setTitle] = useState(current?.title ?? baseTitle);
  const [description, setDescription] = useState(current?.description ?? baseDescription);
  const [required, setRequired] = useState(alwaysRequired || (current?.required ?? false));

  useEffect(() => {
    setTitle(current?.title ?? baseTitle);
    setDescription(current?.description ?? baseDescription);
    setRequired(alwaysRequired || (current?.required ?? false));
  }, [current?.id]);

  const valid = title.trim() !== '' && description.trim() !== '';
  const changed = !current || title !== current.title || description !== current.description || required !== current.required;

  return (
    <form
      className="space-y-3 rounded-xl border border-gray-200 p-4"
      onSubmit={(e) => {
        e.preventDefault();
        if (valid && changed && !busy) void onPublish(title, description, alwaysRequired || required);
      }}
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h3 className="text-sm font-bold text-carbon">{baseTitle}</h3>
        <span className="text-xs text-gray-500">
          {current ? `${t('config.consents.version')} ${current.version}` : t('config.consents.base')}
        </span>
      </div>
      <label className={LABEL}>
        {t('config.consents.field_title')}
        <input className={FIELD} value={title} onChange={(e) => setTitle(e.target.value)} required autoComplete="off" />
      </label>
      <label className={LABEL}>
        {t('config.consents.field_description')}
        <textarea className={FIELD} rows={3} value={description} onChange={(e) => setDescription(e.target.value)} required />
      </label>
      <label className="flex min-h-9 items-start gap-2 text-xs text-gray-700">
        <input
          type="checkbox"
          checked={alwaysRequired || required}
          disabled={alwaysRequired}
          onChange={(e) => setRequired(e.target.checked)}
          className="mt-0.5 rounded border-gray-300 text-turquesa"
        />
        <span>{alwaysRequired ? t('config.consents.always_required') : t('config.consents.required')}</span>
      </label>
      <div className="flex justify-end">
        <button type="submit" disabled={!valid || !changed || busy} className={BTN}>
          {t('config.consents.publish')}
        </button>
      </div>
      {versions.length > 1 && (
        <details className="rounded-lg border border-gray-200 bg-gray-50">
          <summary className="cursor-pointer px-3 py-2 text-xs font-semibold text-carbon">
            {t('config.history')} ({versions.length})
          </summary>
          <ul className="space-y-2 border-t border-gray-200 px-3 py-3 text-xs text-gray-700">
            {versions.map((v) => (
              <li key={v.id}>
                <strong className="text-carbon">{t('config.consents.version')} {v.version}</strong>
                {v.active && <span className="ml-2 rounded bg-claro px-1.5 text-turquesa-dark">{t('cases.history.current')}</span>}
                <span className="ml-2 text-gray-500">{formatDate(v.created_at)}</span>
                <p>{v.title}</p>
                <p className="text-gray-600">{v.description}</p>
              </li>
            ))}
          </ul>
        </details>
      )}
    </form>
  );
};
