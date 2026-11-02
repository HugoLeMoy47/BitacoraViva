import React, { useMemo, useState } from 'react';
import { t } from '../lib/i18n';
import { friendlyError } from '../lib/errors';
import { dataApi } from '../lib/data';
import { useCatalog } from '../lib/catalog';
import { useSession } from '../lib/session';
import { useToast } from '../lib/toast';
import { defaultJournalAreaId, writableAreas } from '../lib/journalAreas';
import { DisabledReason, describedBy } from './DisabledReason';

// Captura rápida de bitácora (expediente a dos columnas): área, línea de servicio opcional y el texto, sin salir del expediente.
// Para lo que necesita más (tipo de entrada, fecha del hecho, nota de trabajo protegida, vista previa) sigue la página completa.
// Compartir con otras áreas es una acción de cada entrada de la línea de tiempo: necesita elegir áreas y la base lo valida.
const INPUT = 'min-h-11 w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm focus:border-turquesa focus:outline-none';

export const QuickJournalCapture: React.FC<{
  caseId: string;
  assignedAreaId?: string;
  isDirector: boolean;
  onSaved: () => Promise<void>;
  onOpenFullForm?: () => void;
}> = ({ caseId, assignedAreaId, isDirector, onSaved, onOpenFullForm }) => {
  const uid = React.useId();
  const toast = useToast();
  const { user } = useSession();
  const { areas, catalogItems } = useCatalog();
  const options = useMemo(() => writableAreas(areas, isDirector, user?.areaIds ?? []), [areas, isDirector, user?.areaIds]);
  const serviceLines = catalogItems.filter((i) => i.catalog === 'service_line' && i.is_active);
  const [areaId, setAreaId] = useState(() => defaultJournalAreaId(options, assignedAreaId));
  const [serviceLineId, setServiceLineId] = useState('');
  const [body, setBody] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const reason = options.length === 0 ? t('journal.quick.no_area') : body.trim() === '' ? t('journal.quick.reason_body') : null;

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (reason || busy) return;
    setBusy(true);
    setError(null);
    try {
      await dataApi.createJournalEntry({
        case_id: caseId,
        entry_type_key: 'follow_up',
        body: body.trim(),
        occurred_at: new Date().toISOString(),
        is_work_note: false,
        area_id: areaId || null,
        service_line_item_id: serviceLineId || null,
      });
      toast.success(t('toast.journal_created'));
      setBody('');
      setServiceLineId('');
      await onSaved();
    } catch (err) {
      setError(friendlyError(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <form onSubmit={submit} className="space-y-3 rounded-2xl border border-gray-200 bg-white p-4" aria-labelledby={`${uid}-t`}>
      <h3 id={`${uid}-t`} className="text-sm font-bold uppercase tracking-wider text-carbon">{t('journal.quick.title')}</h3>
      {options.length > 0 && (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div>
            <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-a`}>{t('journal.quick.area')}</label>
            <select id={`${uid}-a`} name={`${uid}-a`} autoComplete="off" className={INPUT} value={areaId} onChange={(e) => setAreaId(e.target.value)}>
              {options.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
            </select>
          </div>
          {serviceLines.length > 0 && (
            <div>
              <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-l`}>{t('journal.quick.service_line')}</label>
              <select id={`${uid}-l`} name={`${uid}-l`} autoComplete="off" className={INPUT} value={serviceLineId} onChange={(e) => setServiceLineId(e.target.value)}>
                <option value="">{t('common.not_recorded')}</option>
                {serviceLines.map((l) => <option key={l.id} value={l.id}>{l.label_es}</option>)}
              </select>
            </div>
          )}
        </div>
      )}
      <div>
        <label className="mb-1 block text-sm font-semibold text-gray-700" htmlFor={`${uid}-b`}>{t('journal.quick.body')}</label>
        <textarea id={`${uid}-b`} name={`${uid}-b`} autoComplete="off" rows={3} maxLength={5000} disabled={options.length === 0}
          className={`${INPUT} resize-y`} value={body} onChange={(e) => setBody(e.target.value)} />
      </div>
      {error && <p role="alert" className="rounded-lg border border-alerta-dark/40 bg-alerta-bg/40 p-3 text-sm font-semibold text-alerta-dark">{error}</p>}
      <DisabledReason id={uid} reason={reason} />
      <div className="flex flex-wrap items-center gap-3">
        <button type="submit" disabled={!!reason || busy} {...describedBy(uid, reason)}
          className="inline-flex min-h-11 items-center rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon shadow-sm hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50">
          {busy ? t('case_extra.saving') : t('journal.quick.save')}
        </button>
        {onOpenFullForm && (
          <button type="button" onClick={onOpenFullForm} className="inline-flex min-h-11 items-center text-sm font-semibold text-turquesa-dark underline underline-offset-2">
            {t('journal.quick.full_form')}
          </button>
        )}
      </div>
    </form>
  );
};
