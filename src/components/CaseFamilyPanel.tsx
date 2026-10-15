import React, { useState } from 'react';
import { Users, X } from 'lucide-react';
import { t } from '../lib/i18n';
import { friendlyError } from '../lib/errors';
import { dataApi } from '../lib/data';
import { useCatalog } from '../lib/catalog';
import { useToast } from '../lib/toast';
import { CaseFamilyView } from '../types/database';
import { ModalShell } from './ModalShell';
import { DisabledReason, describedBy } from './DisabledReason';

// Familia del sistema de seguimiento paralelo (E14 fase 3). Es independiente del folio de caso y del subfolio. El tipo de
// familia solo informa. Mover o quitar a una persona se cierra con motivo; nada se borra. Cada modal pide a lo más tres campos.
interface PanelProps {
  caseId: string;
  family: CaseFamilyView | null | undefined;
  canEdit: boolean;
  onChanged: () => Promise<void>;
}

type Mode = 'assign' | 'create' | 'remove' | 'type' | null;

const BTN = 'mt-1 inline-flex min-h-11 items-center rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50';
const INPUT = 'mt-1 w-full rounded-lg border border-gray-300 p-3 text-base focus:border-turquesa focus:outline-none focus:ring-1 focus:ring-turquesa';
const LBL = 'block text-sm font-semibold text-gray-800';

// Un consecutivo vacío es válido («No registrado»); si se escribe, debe ser un entero positivo
const parseOrder = (raw: string): { ok: boolean; value: number | null } => {
  const v = raw.trim();
  if (v === '') return { ok: true, value: null };
  return /^[1-9][0-9]{0,5}$/.test(v) ? { ok: true, value: Number(v) } : { ok: false, value: null };
};

export const CaseFamilyPanel: React.FC<PanelProps> = ({ caseId, family, canEdit, onChanged }) => {
  const [mode, setMode] = useState<Mode>(null);
  return (
    <div>
      <h3 className="mb-4 border-b pb-2 text-sm font-bold uppercase tracking-wider text-carbon">{t('family.title')}</h3>
      <p className="mb-3 text-sm text-gray-600">{t('family.subtitle')}</p>

      {!family ? (
        <>
          <p className="rounded-xl border border-dashed border-gray-300 p-4 text-center text-sm text-gray-600">{t('family.none')}</p>
          {canEdit && (
            <div className="mt-2 flex flex-wrap gap-2">
              <button type="button" onClick={() => setMode('assign')} className={BTN}><Users className="mr-1.5 h-4 w-4" aria-hidden="true" />{t('family.assign')}</button>
              <button type="button" onClick={() => setMode('create')} className={BTN}>{t('family.create')}</button>
            </div>
          )}
        </>
      ) : (
        <>
          <div className="grid grid-cols-1 gap-4 text-xs md:grid-cols-3">
            <div>
              <span className="block text-gray-500">{t('family.number')}</span>
              <span className="font-mono text-sm font-semibold text-carbon">{family.unit.family_number}</span>
            </div>
            <div>
              <span className="block text-gray-500">{t('family.type')}</span>
              <span className="text-sm font-semibold text-carbon">{family.typeLabel ?? t('common.not_recorded')}</span>
            </div>
            <div>
              <span className="block text-gray-500">{t('family.order')}</span>
              <span className="text-sm font-semibold text-carbon">{family.order ?? t('common.not_recorded')}</span>
            </div>
          </div>
          <p className="mt-2 text-sm text-gray-600">{t('family.type_note')}</p>

          <h4 className="mt-4 text-sm font-bold text-carbon">{t('family.members')} ({family.members.length})</h4>
          <ul className="mt-1 space-y-1 text-sm">
            {family.members.map((m) => (
              <li key={m.caseId} className="rounded-lg border border-gray-200 p-2">
                <span className="font-mono font-semibold">{m.caseNumber}</span> · {m.personName}
                {m.order != null && <span className="text-gray-600"> · #{m.order}</span>}
                {m.caseId === caseId && <span className="font-semibold text-turquesa-dark"> ({t('family.you')})</span>}
              </li>
            ))}
          </ul>

          {canEdit && (
            <div className="mt-2 flex flex-wrap gap-2">
              <button type="button" onClick={() => setMode('assign')} className={BTN}>{t('family.change')}</button>
              <button type="button" onClick={() => setMode('type')} className={BTN}>{t('family.change_type')}</button>
              <button type="button" onClick={() => setMode('remove')} className={BTN}>{t('family.remove')}</button>
            </div>
          )}
        </>
      )}
      {!family && canEdit && <p className="mt-1 text-sm text-gray-600">{t('family.create_hint')}</p>}

      {mode === 'assign' && <AssignModal caseId={caseId} family={family} onClose={() => setMode(null)} onChanged={onChanged} />}
      {mode === 'create' && <CreateModal caseId={caseId} onClose={() => setMode(null)} onChanged={onChanged} />}
      {mode === 'remove' && family && <RemoveModal caseId={caseId} onClose={() => setMode(null)} onChanged={onChanged} />}
      {mode === 'type' && family && <TypeModal family={family} onClose={() => setMode(null)} onChanged={onChanged} />}
    </div>
  );
};

// Marco común de los modales: encabezado, error junto al botón y motivo visible si no se puede guardar
const Frame: React.FC<{
  title: string;
  uid: string;
  blocked: string | null;
  busy: boolean;
  error: string | null;
  submitLabel: string;
  onClose: () => void;
  onSubmit: () => void;
  children: React.ReactNode;
}> = ({ title, uid, blocked, busy, error, submitLabel, onClose, onSubmit, children }) => (
  <ModalShell onClose={onClose} className="fixed inset-0 z-50 flex items-center justify-center bg-carbon/60 p-4 backdrop-blur-sm">
    <div className="flex max-h-[90vh] w-full max-w-lg flex-col rounded-xl bg-white shadow-2xl">
      <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4">
        <h3 className="font-title text-base font-bold text-carbon">{title}</h3>
        <button type="button" onClick={onClose} className="rounded-lg p-1.5 text-gray-500 hover:bg-gray-100" aria-label={t('common.close')}>
          <X className="h-5 w-5" aria-hidden="true" />
        </button>
      </div>
      <form onSubmit={(e) => { e.preventDefault(); if (!blocked && !busy) onSubmit(); }} className="space-y-4 overflow-y-auto px-6 py-5">
        {children}
        {error && <p role="alert" className="rounded-lg border border-alerta-dark/40 bg-alerta-bg/40 p-3 text-sm font-semibold text-alerta-dark">{error}</p>}
        <div className="border-t border-gray-100 pt-3">
          <DisabledReason id={uid} reason={blocked} className="mb-2" />
          <div className="flex items-center justify-end gap-3">
            <button type="button" onClick={onClose} className="min-h-11 rounded-lg border border-gray-300 px-4 text-sm font-semibold text-gray-700 hover:bg-gray-50">{t('common.cancel')}</button>
            <button type="submit" disabled={!!blocked || busy} {...describedBy(uid, blocked)}
              className="min-h-11 rounded-lg bg-carbon px-5 text-sm font-bold text-white hover:bg-black disabled:cursor-not-allowed disabled:opacity-50">
              {busy ? t('case_extra.saving') : submitLabel}
            </button>
          </div>
        </div>
      </form>
    </div>
  </ModalShell>
);

// Ejecuta la operación, avisa, vuelve a leer y cierra; si falla, el error se dice en el modal
function useRun(onChanged: () => Promise<void>, onClose: () => void) {
  const toast = useToast();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const run = async (action: () => Promise<unknown>, doneKey: string) => {
    setBusy(true);
    setError(null);
    try {
      await action();
      toast.success(t(doneKey));
      await onChanged();
      onClose();
    } catch (e) {
      setError(friendlyError(e));
      setBusy(false);
    }
  };
  return { busy, error, run };
}

interface ModalProps { onClose: () => void; onChanged: () => Promise<void> }

// Asignar a una familia que ya existe, o cambiar de familia o de consecutivo (folio, consecutivo y, si ya tenía familia, motivo)
const AssignModal: React.FC<ModalProps & { caseId: string; family: CaseFamilyView | null | undefined }> = ({ caseId, family, onClose, onChanged }) => {
  const uid = React.useId();
  const { familyUnits } = useCatalog();
  const { busy, error, run } = useRun(onChanged, onClose);
  const [number, setNumber] = useState(family?.unit.family_number ?? '');
  const [orderRaw, setOrderRaw] = useState(family?.order != null ? String(family.order) : '');
  const [reason, setReason] = useState('');
  const unit = familyUnits.find((u) => u.family_number.trim().toLowerCase() === number.trim().toLowerCase());
  const order = parseOrder(orderRaw);
  const unchanged = !!family && !!unit && unit.id === family.unit.id && order.value === (family.order ?? null);
  const blocked: string | null = number.trim() === ''
    ? t('family.reason_missing_number')
    : !unit
      ? t('family.reason_unknown_number')
      : !order.ok
        ? t('family.reason_bad_order')
        : unchanged
          ? t('family.reason_unchanged')
          : family && reason.trim() === ''
            ? t('family.reason_missing_reason')
            : null;
  return (
    <Frame title={t('family.modal_assign')} uid={uid} blocked={blocked} busy={busy} error={error} submitLabel={t('case_extra.save')} onClose={onClose}
      onSubmit={() => void run(() => dataApi.setCaseFamily(caseId, unit!.id, order.value, reason), 'family.saved')}>
      <div>
        <label className={LBL} htmlFor={`${uid}-n`}>{t('family.field_number')}</label>
        <p className="text-sm text-gray-600">{t('family.field_number_hint')}</p>
        <input id={`${uid}-n`} list={`${uid}-dl`} className={INPUT} maxLength={60} value={number} onChange={(e) => setNumber(e.target.value)} autoComplete="off" />
        <datalist id={`${uid}-dl`}>{familyUnits.map((u) => <option key={u.id} value={u.family_number} />)}</datalist>
      </div>
      <div>
        <label className={LBL} htmlFor={`${uid}-o`}>{t('family.field_order')}</label>
        <p className="text-sm text-gray-600">{t('family.order_hint')}</p>
        <input id={`${uid}-o`} inputMode="numeric" className={INPUT} value={orderRaw} onChange={(e) => setOrderRaw(e.target.value)} />
      </div>
      {family && (
        <div>
          <label className={LBL} htmlFor={`${uid}-r`}>{t('case_extra.reason_label')}</label>
          <p className="text-sm text-gray-600">{t('case_extra.reason_hint')}</p>
          <input id={`${uid}-r`} className={INPUT} value={reason} onChange={(e) => setReason(e.target.value)} />
        </div>
      )}
    </Frame>
  );
};

// Crear la familia y asignar a la persona en un solo paso (solo si todavía no tiene familia)
const CreateModal: React.FC<ModalProps & { caseId: string }> = ({ caseId, onClose, onChanged }) => {
  const uid = React.useId();
  const { familyTypes } = useCatalog();
  const { busy, error, run } = useRun(onChanged, onClose);
  const [number, setNumber] = useState('');
  const [typeId, setTypeId] = useState('');
  const [orderRaw, setOrderRaw] = useState('');
  const order = parseOrder(orderRaw);
  const blocked: string | null = number.trim() === '' ? t('family.reason_missing_number') : !order.ok ? t('family.reason_bad_order') : null;
  return (
    <Frame title={t('family.modal_create')} uid={uid} blocked={blocked} busy={busy} error={error} submitLabel={t('case_extra.save')} onClose={onClose}
      onSubmit={() => void run(() => dataApi.setCaseFamily(caseId, null, order.value, undefined, number, typeId || null), 'family.saved')}>
      <p className="text-sm text-gray-700">{t('family.create_hint')}</p>
      <div>
        <label className={LBL} htmlFor={`${uid}-n`}>{t('family.field_number')}</label>
        <input id={`${uid}-n`} className={INPUT} maxLength={60} value={number} onChange={(e) => setNumber(e.target.value)} autoComplete="off" />
      </div>
      <div>
        <label className={LBL} htmlFor={`${uid}-t`}>{t('family.field_type')}</label>
        <select id={`${uid}-t`} className={INPUT} value={typeId} onChange={(e) => setTypeId(e.target.value)}>
          <option value="">{t('family.field_type_none')}</option>
          {familyTypes.filter((x) => x.is_active).map((x) => <option key={x.id} value={x.id}>{x.label_es}</option>)}
        </select>
      </div>
      <div>
        <label className={LBL} htmlFor={`${uid}-o`}>{t('family.field_order')}</label>
        <input id={`${uid}-o`} inputMode="numeric" className={INPUT} value={orderRaw} onChange={(e) => setOrderRaw(e.target.value)} />
      </div>
    </Frame>
  );
};

const RemoveModal: React.FC<ModalProps & { caseId: string }> = ({ caseId, onClose, onChanged }) => {
  const uid = React.useId();
  const { busy, error, run } = useRun(onChanged, onClose);
  const [reason, setReason] = useState('');
  const blocked = reason.trim() === '' ? t('family.reason_missing_reason') : null;
  return (
    <Frame title={t('family.modal_remove')} uid={uid} blocked={blocked} busy={busy} error={error} submitLabel={t('family.remove')} onClose={onClose}
      onSubmit={() => void run(() => dataApi.setCaseFamily(caseId, null, null, reason), 'family.removed')}>
      <p className="text-sm text-gray-700">{t('family.remove_hint')}</p>
      <div>
        <label className={LBL} htmlFor={`${uid}-r`}>{t('case_extra.reason_label')}</label>
        <input id={`${uid}-r`} className={INPUT} value={reason} onChange={(e) => setReason(e.target.value)} />
      </div>
    </Frame>
  );
};

const TypeModal: React.FC<ModalProps & { family: CaseFamilyView }> = ({ family, onClose, onChanged }) => {
  const uid = React.useId();
  const { familyTypes } = useCatalog();
  const { busy, error, run } = useRun(onChanged, onClose);
  const [typeId, setTypeId] = useState(family.unit.family_type_id ?? '');
  const [reason, setReason] = useState('');
  const hadType = !!family.unit.family_type_id;
  const unchanged = typeId === (family.unit.family_type_id ?? '');
  const blocked: string | null = unchanged ? t('family.reason_unchanged') : hadType && reason.trim() === '' ? t('family.reason_missing_reason') : null;
  return (
    <Frame title={t('family.modal_type')} uid={uid} blocked={blocked} busy={busy} error={error} submitLabel={t('case_extra.save')} onClose={onClose}
      onSubmit={() => void run(() => dataApi.setFamilyType(family.unit.id, typeId || null, reason), 'family.type_saved')}>
      <p className="text-sm text-gray-700">{t('family.type_note')}</p>
      <div>
        <label className={LBL} htmlFor={`${uid}-t`}>{t('family.field_type')}</label>
        <select id={`${uid}-t`} className={INPUT} value={typeId} onChange={(e) => setTypeId(e.target.value)}>
          <option value="">{t('family.field_type_none')}</option>
          {familyTypes.filter((x) => x.is_active || x.id === family.unit.family_type_id).map((x) => <option key={x.id} value={x.id}>{x.label_es}</option>)}
        </select>
      </div>
      {hadType && (
        <div>
          <label className={LBL} htmlFor={`${uid}-r`}>{t('case_extra.reason_label')}</label>
          <input id={`${uid}-r`} className={INPUT} value={reason} onChange={(e) => setReason(e.target.value)} />
        </div>
      )}
    </Frame>
  );
};
