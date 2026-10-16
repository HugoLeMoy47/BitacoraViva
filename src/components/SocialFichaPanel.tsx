import React, { useMemo, useState } from 'react';
import { t } from '../lib/i18n';
import { friendlyError } from '../lib/errors';
import { dataApi } from '../lib/data';
import { useCatalog } from '../lib/catalog';
import { useToast } from '../lib/toast';
import { CaseWithDetails, SocialQuestion } from '../types/database';
import { Draft, buildPayload, draftOf, formatAnswer } from '../lib/socialAnswers';
import { FlexibleDateInput } from './FlexibleDateInput';
import { DisabledReason, describedBy } from './DisabledReason';

// Ficha social (E15 fase 2): las preguntas de contexto migratorio y de situaciones sensibles de Trabajo Social. Las preguntas las
// administran dirección y Trabajo Social en «Diccionarios». Cada respuesta es informativa (el marcador de vulnerabilidad manda)
// y versionada: cambiar o quitar una respuesta ya registrada pide motivo y la anterior queda en el historial.
// Lo que hay que CONTAR (relatos, hechos, terceros) no va aquí: va a la bitácora de Trabajo Social.
const SECTIONS: SocialQuestion['section'][] = ['migration', 'sensitive'];
const CONTROL = 'w-full min-h-11 rounded-lg border border-gray-300 bg-white p-2.5 text-sm focus:border-turquesa focus:outline-none';
const BTN = 'inline-flex min-h-11 items-center rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50';

interface Props {
  caseData: CaseWithDetails;
  canEdit: boolean;
  sensitiveOk: boolean;
  onChanged: () => Promise<void>;
}

export const SocialFichaPanel: React.FC<Props> = ({ caseData, canEdit, sensitiveOk, onChanged }) => {
  const { socialQuestions } = useCatalog();
  const answers = caseData.social_answers ?? [];
  const labels = { yes: t('social.yes'), no: t('social.no'), no_response: t('social.no_response') };

  return (
    <div>
      <h3 className="mb-4 border-b pb-2 text-sm font-bold uppercase tracking-wider text-carbon">{t('social.title')}</h3>
      <p className="mb-1 text-sm text-gray-600">{t('social.subtitle')}</p>
      <p className="mb-4 text-sm text-gray-600">{t('social.narrative_note')}</p>
      <div className="space-y-6">
        {SECTIONS.map((section) => {
          const questions = socialQuestions
            .filter((q) => q.section === section && (q.is_active || answers.some((a) => a.question_id === q.id)))
            .sort((a, b) => a.sort_order - b.sort_order);
          if (questions.length === 0) return null;
          return (
            <SectionBlock
              key={section}
              section={section}
              caseId={caseData.id}
              questions={questions}
              answers={answers}
              labels={labels}
              canEdit={canEdit}
              sensitiveOk={sensitiveOk}
              onChanged={onChanged}
            />
          );
        })}
      </div>
    </div>
  );
};

const SectionBlock: React.FC<{
  section: SocialQuestion['section'];
  caseId: string;
  questions: SocialQuestion[];
  answers: NonNullable<CaseWithDetails['social_answers']>;
  labels: { yes: string; no: string; no_response: string };
  canEdit: boolean;
  sensitiveOk: boolean;
  onChanged: () => Promise<void>;
}> = ({ section, caseId, questions, answers, labels, canEdit, sensitiveOk, onChanged }) => {
  const uid = React.useId();
  const toast = useToast();
  const [editing, setEditing] = useState(false);
  const initial = useMemo(() => Object.fromEntries(questions.map((q) => [q.key, draftOf(q, answers.find((a) => a.question_id === q.id))])), [questions, answers]);
  const [drafts, setDrafts] = useState<Record<string, Draft>>(initial);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const { payload, needsReason, invalid } = buildPayload(questions, drafts, answers);
  const blocked: string | null =
    invalid.length > 0 ? t('social.invalid') : payload.length === 0 ? t('case_extra.unchanged') : needsReason && reason.trim() === '' ? t('social.reason_missing') : null;

  const set = (key: string, patch: Partial<Draft>) => setDrafts((d) => ({ ...d, [key]: { ...d[key], ...patch } }));
  const open = () => { setDrafts(initial); setReason(''); setError(null); setEditing(true); };

  const save = async () => {
    if (blocked || busy) return;
    setBusy(true);
    setError(null);
    try {
      await dataApi.setSocialAnswers(caseId, payload, reason);
      toast.success(t('social.saved'));
      await onChanged();
      setEditing(false);
    } catch (e) {
      setError(friendlyError(e));
    }
    setBusy(false);
  };

  return (
    <section aria-labelledby={`${uid}-h`}>
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h4 id={`${uid}-h`} className="text-sm font-bold text-carbon">{t(`social.section.${section}`)}</h4>
        {canEdit && !editing && <button type="button" onClick={open} className={BTN}>{t('social.edit')}</button>}
      </div>
      {section === 'sensitive' && (
        <p className="mt-1 text-sm text-gray-700">{sensitiveOk ? t('social.sensitive_note') : t('social.sensitive_blocked')}</p>
      )}

      {!editing ? (
        <dl className="mt-3 grid grid-cols-1 gap-3 text-xs md:grid-cols-2">
          {questions.map((q) => (
            <div key={q.id}>
              <dt className="text-gray-500">{q.label_es}{!q.is_active && ` (${t('social.retired')})`}</dt>
              <dd className="text-sm font-semibold text-carbon">{formatAnswer(q, answers.find((a) => a.question_id === q.id), labels) ?? t('common.not_recorded')}</dd>
            </div>
          ))}
        </dl>
      ) : (
        <div className="mt-3 space-y-4">
          {questions.filter((q) => q.is_active).map((q) => {
            const d = drafts[q.key];
            const onlyNoResponse = q.is_sensitive && !sensitiveOk;
            const id = `${uid}-${q.key}`;
            return (
              <div key={q.id}>
                {q.answer_type === 'yes_no' && (
                  <fieldset>
                    <legend className="mb-1 block text-sm font-medium text-gray-800">{q.label_es}</legend>
                    <div className="flex flex-wrap gap-x-5 gap-y-1">
                      {(['', 'yes', 'no', 'no_response'] as const).map((c) => {
                        const off = onlyNoResponse && (c === 'yes' || c === 'no');
                        return (
                          <label key={c || 'none'} className={`flex min-h-11 items-center gap-2 text-sm ${off ? 'text-gray-400' : 'text-carbon'}`}>
                            <input type="radio" name={id} checked={d.choice === c} disabled={off} onChange={() => set(q.key, { choice: c })} />
                            {c === '' ? t('social.unanswered') : labels[c]}
                          </label>
                        );
                      })}
                    </div>
                    {q.has_detail && (d.choice === 'yes' || d.choice === 'no') && (
                      <div className="mt-1">
                        <label className="sr-only" htmlFor={`${id}-d`}>{t('social.detail')}</label>
                        <input id={`${id}-d`} name={`${id}-d`} autoComplete="off" className={CONTROL} maxLength={120} placeholder={t('social.detail')} value={d.detail} onChange={(e) => set(q.key, { detail: e.target.value })} />
                      </div>
                    )}
                  </fieldset>
                )}
                {q.answer_type === 'number' && (
                  <div>
                    <label className="mb-1 block text-sm font-medium text-gray-800" htmlFor={id}>{q.label_es}</label>
                    <input id={id} name={id} autoComplete="off" inputMode="numeric" className={`${CONTROL} max-w-[8rem]`} maxLength={3} disabled={onlyNoResponse} value={d.number} onChange={(e) => set(q.key, { number: e.target.value })} />
                    {invalid.includes(q.key) && <p role="alert" className="mt-1 text-sm font-semibold text-alerta-dark">{t('social.invalid_number')}</p>}
                  </div>
                )}
                {q.answer_type === 'text' && (
                  <div>
                    <label className="mb-1 block text-sm font-medium text-gray-800" htmlFor={id}>{q.label_es}</label>
                    <input id={id} name={id} autoComplete="off" className={CONTROL} maxLength={120} disabled={onlyNoResponse} value={d.text} onChange={(e) => set(q.key, { text: e.target.value })} />
                  </div>
                )}
                {q.answer_type === 'date' && (
                  <FlexibleDateInput id={id} label={q.label_es} precision={d.precision} value={d.date} onChange={(precision, date) => set(q.key, { precision, date })} problem={invalid.includes(q.key) ? t('social.invalid_date') : null} />
                )}
                {onlyNoResponse && q.answer_type !== 'yes_no' && <p className="mt-1 text-sm text-gray-700">{t('social.blocked_field')}</p>}
              </div>
            );
          })}

          {needsReason && (
            <div>
              <label className="block text-sm font-semibold text-gray-800" htmlFor={`${uid}-r`}>{t('case_extra.reason_label')}</label>
              <p className="text-sm text-gray-600">{t('social.reason_hint')}</p>
              <input id={`${uid}-r`} name={`${uid}-r`} autoComplete="off" className={`${CONTROL} mt-1`} value={reason} onChange={(e) => setReason(e.target.value)} />
            </div>
          )}
          {error && <p role="alert" className="rounded-lg border border-alerta-dark/40 bg-alerta-bg/40 p-3 text-sm font-semibold text-alerta-dark">{error}</p>}
          <div>
            <DisabledReason id={uid} reason={blocked} className="mb-2" />
            <div className="flex flex-wrap items-center gap-3">
              <button type="button" onClick={() => void save()} disabled={!!blocked || busy} {...describedBy(uid, blocked)}
                className="min-h-11 rounded-lg bg-carbon px-5 text-sm font-bold text-white hover:bg-black disabled:cursor-not-allowed disabled:opacity-50">
                {busy ? t('case_extra.saving') : t('social.save')}
              </button>
              <button type="button" onClick={() => setEditing(false)} className={BTN}>{t('common.cancel')}</button>
            </div>
          </div>
        </div>
      )}
    </section>
  );
};
