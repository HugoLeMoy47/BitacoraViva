import { useEffect, useMemo, useState } from 'react';
import { Shield, Clock, AlertTriangle, ArrowRight, ArrowLeft, CheckCircle2 } from 'lucide-react';
import { t } from '../lib/i18n';
import { CaseWithDetails, JournalEntry, JournalEntryType } from '../types/database';
import { useCatalog } from '../lib/catalog';
import { useSession } from '../lib/session';
import { formatDate, formatDateTime } from '../lib/format';
import { DisabledReason, describedBy } from './DisabledReason';
import { TEMPLATES, composeBody, hasTemplate, ordinalLabelKey } from '../lib/journalTemplates';

// BV-4.1 · Nueva entrada de bitácora, como PÁGINA (no modal): es el flujo diario de quien trabaja con el sistema.
// El texto va primero; los datos de la entrada (tipo, área, cuándo, nota protegida) después. Se conserva la vista
// previa antes de asentar (el registro es inmutable). El texto se guarda en MEMORIA si se sale a mirar otra cosa y
// se regresa; no se guarda en el navegador: son datos de una persona atendida.

const INPUT = 'w-full min-h-11 rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-turquesa focus:outline-none';
const LABEL = 'block text-sm font-semibold text-gray-700 mb-1';
const ENTRY_TYPES: JournalEntryType[] = [
  'follow_up', 'intake_interview', 'diagnosis', 'integral_route', 'case_meeting', 'warning', 'referral', 'home_visit', 'incident', 'note',
];

interface Draft {
  entryType: JournalEntryType;
  areaId: string;
  occurredAt: string;
  isWorkNote: boolean;
  body: string;
  serviceLineId: string;
  sections: Record<string, string>;
  referralKind: '' | 'general' | 'priority';
}
const drafts = new Map<string, Draft>();

interface NewJournalEntryPageProps {
  caseData: CaseWithDetails;
  authorUserId: string;
  authorFullName: string;
  assignedAreaId?: string;
  /** Enlace «Volver al caso»: el borrador se conserva */
  onBack: () => void;
  /** Botón «Cancelar»: el borrador se borra */
  onCancel: () => void;
  onSubmit: (entry: JournalEntry) => void;
}

export const NewJournalEntryPage: React.FC<NewJournalEntryPageProps> = ({ caseData, authorUserId, authorFullName, assignedAreaId, onBack, onCancel, onSubmit }) => {
  const { areas: allAreas, catalogItems } = useCatalog();
  const serviceLines = catalogItems.filter((i) => i.catalog === 'service_line' && i.is_active);
  const { user } = useSession();
  // Escribir a nombre de un área exige ser de esa área; Dirección, de cualquiera. Sin área asignada
  // (ingreso) solo el área general. La base lo exige igual; aquí solo se ofrece lo que se puede hacer.
  const areas = user?.roles.includes('director')
    ? allAreas
    : user && user.areaIds.length > 0
      ? allAreas.filter((a) => user.areaIds.includes(a.id))
      : allAreas.filter((a) => a.is_general);

  const saved = drafts.get(caseData.id);
  const [step, setStep] = useState<'compose' | 'preview'>('compose');
  const [entryType, setEntryType] = useState<JournalEntryType>(saved?.entryType ?? 'follow_up');
  const [areaId, setAreaId] = useState<string>(
    saved?.areaId ||
      (assignedAreaId && areas.some((a) => a.id === assignedAreaId) ? assignedAreaId : '') ||
      areas.find((a) => a.is_default_intake)?.id ||
      areas[0]?.id ||
      ''
  );
  const [occurredAt, setOccurredAt] = useState<string>(
    saved?.occurredAt ?? new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 16)
  );
  const [isWorkNote, setIsWorkNote] = useState<boolean>(saved?.isWorkNote ?? false);
  const [freeBody, setFreeBody] = useState<string>(saved?.body ?? '');
  const [serviceLineId, setServiceLineId] = useState<string>(saved?.serviceLineId ?? '');
  const [sections, setSections] = useState<Record<string, string>>(saved?.sections ?? {});
  const [referralKind, setReferralKind] = useState<'' | 'general' | 'priority'>(saved?.referralKind ?? '');

  // Diagnóstico y reunión de casos se redactan por secciones; el resultado es el texto de la entrada. Una sección vacía no se escribe.
  const templated = hasTemplate(entryType);
  const sectionTitle = (key: string) => {
    const base = t(`journal.templates.${entryType}.${key}`);
    return entryType === 'case_meeting' && key === 'referred' && referralKind
      ? `${base} (${t(`journal.templates.referral_${referralKind}`)})`
      : base;
  };
  const body = templated
    ? composeBody(TEMPLATES[entryType].map((k) => ({ title: sectionTitle(k), text: sections[`${entryType}.${k}`] ?? '' })))
    : freeBody;

  useEffect(() => {
    drafts.set(caseData.id, { entryType, areaId, occurredAt, isWorkNote, body: freeBody, serviceLineId, sections, referralKind });
  }, [caseData.id, entryType, areaId, occurredAt, isWorkNote, freeBody, serviceLineId, sections, referralKind]);
  const dirty = body.trim().length > 0;
  useEffect(() => {
    if (!dirty) return;
    const guard = (e: BeforeUnloadEvent) => e.preventDefault();
    window.addEventListener('beforeunload', guard);
    return () => window.removeEventListener('beforeunload', guard);
  }, [dirty]);

  const currentArea = areas.find((a) => a.id === areaId) || areas[0] || allAreas[0];
  const bodyReason = body.trim() ? null : t('journal.new_modal.reason_body');

  // Las últimas entradas que esta persona ya puede ver en el caso: contexto para no repetir ni contradecir
  const recent = useMemo(
    () => [...(caseData.journal_entries ?? [])].sort((a, b) => b.occurred_at.localeCompare(a.occurred_at)).slice(0, 3),
    [caseData.journal_entries]
  );

  // 1.ª, 2.ª… llamada de atención: se deriva de las que esta persona ya puede ver en el expediente
  const nextWarning = useMemo(
    () => (caseData.journal_entries ?? []).filter((e) => e.entry_type_key === 'warning').length + 1,
    [caseData.journal_entries]
  );

  const finish = () => drafts.delete(caseData.id);

  const toPreview = (e: React.FormEvent) => {
    e.preventDefault();
    if (bodyReason) return;
    setStep('preview');
    window.scrollTo({ top: 0 });
  };

  const save = () => {
    if (!currentArea) return;
    const entry: JournalEntry = {
      id: crypto.randomUUID(),
      organization_id: currentArea.organization_id,
      case_id: caseData.id,
      case_number: caseData.case_number,
      area_id: currentArea.id,
      area_code: currentArea.code,
      area_name: currentArea.name,
      author_user_id: authorUserId,
      author_name: authorFullName,
      entry_type_key: entryType,
      body: body.trim(),
      is_work_note: isWorkNote,
      occurred_at: new Date(occurredAt).toISOString(),
      created_at: new Date().toISOString(),
      visibility: 'area_private',
      superseded_by_id: null,
      service_line_item_id: serviceLineId || null,
    };
    finish();
    onSubmit(entry);
  };

  const cancel = () => {
    finish();
    onCancel();
  };

  const person = caseData.person.preferred_name || `${caseData.person.given_name} ${caseData.person.paternal_family_name}`;

  return (
    <div className="mx-auto max-w-6xl space-y-5">
      <div>
        <button type="button" onClick={onBack} className="inline-flex min-h-11 items-center gap-1.5 text-sm font-semibold text-turquesa-dark hover:underline">
          <ArrowLeft className="h-4 w-4" aria-hidden="true" />
          {t('journal.new_page.back_to_case').replace('{folio}', caseData.case_number)}
        </button>
        <h2 className="font-title text-2xl font-bold text-carbon">{t('journal.new_modal.title')}</h2>
        <p className="mt-1 text-sm text-gray-600">{t('journal.new_modal.subtitle')}</p>
        <ol className="mt-3 flex text-sm font-medium" aria-label={t('journal.new_page.steps')}>
          <li aria-current={step === 'compose' ? 'step' : undefined} className={step === 'compose' ? 'font-bold text-turquesa-dark' : 'text-gray-600'}>
            {t('journal.new_modal.step_compose')}
          </li>
          <li className="mx-3 text-gray-300" aria-hidden="true">/</li>
          <li aria-current={step === 'preview' ? 'step' : undefined} className={step === 'preview' ? 'font-bold text-turquesa-dark' : 'text-gray-600'}>
            {t('journal.new_modal.step_preview')}
          </li>
        </ol>
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,1fr)_20rem]">
        {step === 'compose' ? (
          <form onSubmit={toPreview} className="min-w-0 space-y-5">
            <div className="rounded-2xl border border-gray-200 bg-white p-5">
              <label className={LABEL} htmlFor="bit-type">{t('journal.new_modal.field_type')}</label>
              <select id="bit-type" name="bit-type" autoComplete="off" value={entryType} onChange={(e) => setEntryType(e.target.value as JournalEntryType)} className={INPUT}>
                {ENTRY_TYPES.map((k) => (
                  <option key={k} value={k}>{t(`journal.types.${k}`)}</option>
                ))}
              </select>
              {entryType === 'warning' && (
                <p className="mt-2 rounded-lg bg-gray-50 p-3 text-sm text-gray-700">
                  {t('journal.warning_next').replace('{ordinal}', t(ordinalLabelKey(nextWarning)))}
                </p>
              )}
            </div>

            {templated ? (
              <div className="space-y-4 rounded-2xl border border-gray-200 bg-white p-5">
                <p className="text-sm text-gray-600">{t('journal.templates.hint')}</p>
                {TEMPLATES[entryType].map((k, i) => (
                  <div key={`${entryType}.${k}`}>
                    <label className="mb-1 block text-base font-bold text-carbon" htmlFor={`bit-sec-${k}`}>{sectionTitle(k)}</label>
                    <textarea
                      id={`bit-sec-${k}`}
                      name={`bit-sec-${k}`}
                      autoComplete="off"
                      autoFocus={i === 0}
                      rows={3}
                      value={sections[`${entryType}.${k}`] ?? ''}
                      onChange={(e) => setSections((s) => ({ ...s, [`${entryType}.${k}`]: e.target.value }))}
                      className="w-full rounded-lg border border-gray-300 p-3 text-sm focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa"
                    />
                    {entryType === 'case_meeting' && k === 'referred' && (
                      <fieldset className="mt-2">
                        <legend className="text-sm font-semibold text-gray-700">{t('journal.templates.referral_kind')}</legend>
                        <div className="mt-1 flex flex-wrap gap-4">
                          {(['', 'general', 'priority'] as const).map((v) => (
                            <label key={v || 'none'} className="flex min-h-11 items-center gap-2 text-sm text-carbon">
                              <input type="radio" name="bit-referral-kind" checked={referralKind === v} onChange={() => setReferralKind(v)} />
                              {v === '' ? t('journal.templates.referral_none') : t(`journal.templates.referral_${v}`)}
                            </label>
                          ))}
                        </div>
                      </fieldset>
                    )}
                  </div>
                ))}
              </div>
            ) : (
              <div className="rounded-2xl border border-gray-200 bg-white p-5">
                <label className="mb-1 block text-base font-bold text-carbon" htmlFor="bit-body">
                  {t('journal.new_modal.field_body')}
                </label>
                <textarea
                  id="bit-body"
                  name="bit-body"
                  autoComplete="off"
                  autoFocus
                  rows={9}
                  value={freeBody}
                  onChange={(e) => setFreeBody(e.target.value)}
                  placeholder={t('journal.new_modal.field_body_placeholder')}
                  className="w-full rounded-lg border border-gray-300 p-3 text-sm focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa"
                />
              </div>
            )}

            <fieldset className="space-y-4 rounded-2xl border border-gray-200 bg-white p-5">
              <legend className="px-1 text-base font-bold text-carbon">{t('journal.new_page.details')}</legend>
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                {serviceLines.length > 0 && (
                  <div>
                    <label className={LABEL} htmlFor="bit-line">{t('journal.service_line.label')}</label>
                    <select id="bit-line" name="bit-line" autoComplete="off" value={serviceLineId} onChange={(e) => setServiceLineId(e.target.value)} className={INPUT}>
                      <option value="">{t('journal.service_line.none')}</option>
                      {serviceLines.map((i) => (
                        <option key={i.id} value={i.id}>{i.label_es}</option>
                      ))}
                    </select>
                    <p className="mt-1 text-sm text-gray-600">{t('journal.service_line.help')}</p>
                  </div>
                )}
                <div>
                  {areas.length > 1 ? (
                    <>
                      <label className={LABEL} htmlFor="bit-area">{t('journal.new_modal.field_area')}</label>
                      <select id="bit-area" name="bit-area" autoComplete="off" value={areaId} onChange={(e) => setAreaId(e.target.value)} className={INPUT}>
                        {areas.map((a) => (
                          <option key={a.id} value={a.id}>{a.name}</option>
                        ))}
                      </select>
                    </>
                  ) : (
                    /* Una sola opción posible: no es una pregunta, es información */
                    <>
                      <span className={LABEL}>{t('journal.new_modal.field_area')}</span>
                      <p className="rounded-lg border border-gray-200 bg-gray-50 px-3 py-2 text-sm text-carbon">
                        <span className="block text-xs text-gray-600">
                          {user && user.areaIds.length > 0 ? t('journal.new_modal.area_fixed') : t('journal.new_modal.area_fixed_coordination')}
                        </span>
                        <strong>{currentArea?.name}</strong>
                      </p>
                    </>
                  )}
                </div>
              </div>
              <div>
                <label className={LABEL} htmlFor="bit-when">{t('journal.new_modal.field_occurred_at')}</label>
                <input id="bit-when" name="bit-when" autoComplete="off" type="datetime-local" value={occurredAt} onChange={(e) => setOccurredAt(e.target.value)} className={INPUT} />
                <p className="mt-1 text-sm text-gray-600">{t('journal.new_modal.field_occurred_help')}</p>
              </div>

              {/* Nota de trabajo protegida (Ethos E-02 / MD-04) */}
              <div className="rounded-lg border border-amber-200 bg-amber-50/60 p-3.5">
                <label className="flex min-h-11 cursor-pointer items-start gap-3">
                  <input
                    type="checkbox"
                    checked={isWorkNote}
                    onChange={(e) => setIsWorkNote(e.target.checked)}
                    className="mt-1 h-4 w-4 rounded border-gray-300 text-amber-600 focus:ring-amber-500"
                  />
                  <span>
                    <span className="flex items-center gap-1.5 text-sm font-bold text-amber-900">
                      <Shield className="h-4 w-4 text-amber-600" aria-hidden="true" />
                      {t('journal.new_modal.field_work_note')}
                    </span>
                    <span className="mt-0.5 block text-sm leading-relaxed text-amber-900">{t('journal.new_modal.field_work_note_help')}</span>
                  </span>
                </label>
              </div>
            </fieldset>

            {/* Barra de acciones: siempre a la vista; en celular queda sobre la barra de navegación */}
            <div className="sticky bottom-[calc(3.5rem+env(safe-area-inset-bottom))] z-30 -mx-4 border-t border-gray-200 bg-white/95 px-4 py-3 backdrop-blur md:bottom-0 md:mx-0 md:rounded-2xl md:border">
              <DisabledReason id="bit" reason={bodyReason} className="mb-2" />
              <div className="flex items-center justify-between gap-3">
                <button type="button" onClick={cancel} className="min-h-11 rounded-lg border border-gray-300 bg-white px-4 text-sm font-semibold text-gray-700 hover:bg-gray-50">
                  {t('common.cancel')}
                </button>
                <button
                  type="submit"
                  disabled={!!bodyReason}
                  {...describedBy('bit', bodyReason)}
                  className="inline-flex min-h-11 items-center gap-2 rounded-lg bg-turquesa px-5 text-sm font-semibold text-carbon shadow-sm hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  <span>{t('journal.new_modal.btn_to_preview')}</span>
                  <ArrowRight className="h-4 w-4" aria-hidden="true" />
                </button>
              </div>
            </div>
          </form>
        ) : (
          /* VISTA PREVIA: el registro es inmutable, se revisa antes de asentarlo */
          <div className="min-w-0 space-y-5">
            <div className="flex items-start gap-3 rounded-lg border border-blue-200 bg-blue-50/70 p-3.5 text-sm text-blue-900">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-blue-600" aria-hidden="true" />
              <div>
                <p className="font-bold">{t('journal.new_modal.preview_title')}</p>
                <p className="mt-0.5">{t('journal.new_modal.preview_warning')}</p>
              </div>
            </div>

            <div className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
              <div className="flex flex-wrap items-center justify-between gap-2 border-b border-gray-100 pb-3">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="rounded-md bg-gray-100 px-2.5 py-1 text-xs font-bold text-gray-700">{currentArea?.name}</span>
                  <span className="rounded-md bg-turquesa/10 px-2.5 py-1 text-xs font-semibold text-turquesa-dark">{t(`journal.types.${entryType}`)}</span>
                  {serviceLineId && (
                    <span className="rounded-md bg-gray-100 px-2.5 py-1 text-xs font-semibold text-gray-700">
                      {serviceLines.find((i) => i.id === serviceLineId)?.label_es}
                    </span>
                  )}
                  {isWorkNote && (
                    <span className="flex items-center gap-1 rounded-md bg-amber-100 px-2.5 py-1 text-xs font-bold text-amber-800">
                      <Shield className="h-3 w-3" aria-hidden="true" />
                      {t('journal.work_note_badge')}
                    </span>
                  )}
                </div>
                <div className="flex items-center gap-1.5 text-xs text-gray-600">
                  <Clock className="h-3.5 w-3.5" aria-hidden="true" />
                  <span>{t('journal.occurred_at')} {formatDateTime(occurredAt)}</span>
                </div>
              </div>
              <div className="mt-4 whitespace-pre-wrap text-sm leading-relaxed text-carbon">{body}</div>
              <div className="mt-4 border-t border-gray-100 pt-3 text-xs text-gray-600">
                <span>{t('journal.author_by')} {authorFullName}</span>
                <span className="mx-2">·</span>
                <span className="font-medium">{t('journal.visibility_area_private')}</span>
              </div>
            </div>

            <div className="sticky bottom-[calc(3.5rem+env(safe-area-inset-bottom))] z-30 -mx-4 flex items-center justify-between gap-3 border-t border-gray-200 bg-white/95 px-4 py-3 backdrop-blur md:bottom-0 md:mx-0 md:rounded-2xl md:border">
              <button type="button" onClick={() => setStep('compose')} className="inline-flex min-h-11 items-center gap-2 rounded-lg border border-gray-300 bg-white px-4 text-sm font-medium text-gray-700 hover:bg-gray-50">
                <ArrowLeft className="h-4 w-4" aria-hidden="true" />
                <span>{t('journal.new_modal.btn_back_edit')}</span>
              </button>
              <button type="button" onClick={save} className="inline-flex min-h-11 items-center gap-2 rounded-lg bg-carbon px-5 text-sm font-semibold text-white shadow-md hover:bg-gray-800">
                <CheckCircle2 className="h-4 w-4 text-turquesa" aria-hidden="true" />
                <span>{t('journal.new_modal.btn_save_entry')}</span>
              </button>
            </div>
          </div>
        )}

        {/* Contexto: el caso y lo ya escrito, a la vista mientras se redacta */}
        <aside aria-label={t('journal.new_page.context_title')} className="space-y-3 lg:sticky lg:top-20 lg:self-start">
          <section className="rounded-2xl border border-gray-200 bg-white p-5">
            <h3 className="text-base font-bold text-carbon">{t('journal.new_page.context_title')}</h3>
            <dl className="mt-3 space-y-3 text-sm">
              <div>
                <dt className="text-gray-600">{t('subfolio.context_folio')}</dt>
                <dd className="font-mono font-bold text-carbon">{caseData.case_number}</dd>
              </div>
              <div>
                <dt className="text-gray-600">{t('journal.new_page.context_person')}</dt>
                <dd className="font-semibold text-carbon">{person}</dd>
              </div>
              <div>
                <dt className="text-gray-600">{t('subfolio.context_status')}</dt>
                <dd className="font-semibold text-carbon">{caseData.statuses.engagement_status?.label}</dd>
              </div>
            </dl>
            <p className="mt-3 rounded-lg bg-gray-50 p-3 text-sm text-gray-700">{t('journal.new_page.privacy_reminder')}</p>
          </section>
          <section className="rounded-2xl border border-gray-200 bg-white p-5">
            <h3 className="text-base font-bold text-carbon">{t('journal.new_page.recent_title')}</h3>
            {recent.length === 0 ? (
              <p className="mt-2 text-sm text-gray-600">{t('journal.new_page.recent_none')}</p>
            ) : (
              <ul className="mt-3 space-y-3">
                {recent.map((e) => (
                  <li key={e.id} className="text-sm">
                    <p className="text-xs text-gray-600">
                      {formatDate(e.occurred_at)} · {e.area_name} · {t(`journal.types.${e.entry_type_key}`)}
                    </p>
                    <p className="mt-0.5 line-clamp-3 text-carbon">{e.body}</p>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </aside>
      </div>
    </div>
  );
};
