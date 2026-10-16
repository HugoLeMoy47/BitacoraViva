import React, { useState } from 'react';
import { t } from '../lib/i18n';
import { friendlyError } from '../lib/errors';
import { dataApi } from '../lib/data';
import { useCatalog } from '../lib/catalog';
import { useToast } from '../lib/toast';
import { itemLabel } from '../lib/catalogs';
import { CaseWithDetails, CatalogItem } from '../types/database';
import { CatalogItemModal } from './CatalogItemModal';
import { SmallFieldModal } from './SmallFieldModal';
import { DisabledReason, describedBy } from './DisabledReason';

// Ficha complementaria de la persona (E15 fase 1): nivel de estudios, estado civil, ocupación en su lugar de origen,
// departamento de origen y número de referencia. Todo sale de diccionarios que editan dirección y Trabajo Social.
// El departamento es dato sensible (depende de la nacionalidad); lo demás no. Cambiar o quitar un valor pide motivo.
type Editing = null | 'education_level' | 'marital_status' | 'origin_department' | 'reference';
const MAX_OCCUPATIONS = 3;
const BTN = 'mt-1 inline-flex min-h-11 items-center rounded-lg border border-gray-300 bg-white px-3 text-sm font-semibold text-carbon hover:bg-gray-50';

interface Props {
  caseData: CaseWithDetails;
  canEdit: boolean;
  sensitiveOk: boolean;
  onChanged: () => Promise<void>;
}

export const PersonProfilePanel: React.FC<Props> = ({ caseData, canEdit, sensitiveOk, onChanged }) => {
  const { catalogItems } = useCatalog();
  const toast = useToast();
  const [editing, setEditing] = useState<Editing>(null);
  const person = caseData.person;
  const of = (catalog: CatalogItem['catalog']) => catalogItems.filter((i) => i.catalog === catalog);
  // Los departamentos que se ofrecen son los del país de la nacionalidad (más «no quiso responder»)
  const nationality = person.nationality_country_id ?? null;
  const departments = of('department').filter((i) => i.is_system || (nationality !== null && i.country_id === nationality));

  const saved = async () => {
    toast.success(t('case_extra.saved'));
    await onChanged();
  };

  const Row: React.FC<{ label: string; value: string | null; button?: React.ReactNode; note?: string | null }> = ({ label, value, button, note }) => (
    <div>
      <span className="block text-gray-500">{label}</span>
      <span className="text-sm font-semibold text-carbon">{value ?? t('common.not_recorded')}</span>
      {note && <p className="mt-1 text-sm text-gray-700">{note}</p>}
      {button}
    </div>
  );
  const change = (kind: Exclude<Editing, null>, has: boolean, registerKey: string) =>
    canEdit ? (
      <button type="button" onClick={() => setEditing(kind)} className={BTN}>
        {has ? t('case_extra.change') : t(registerKey)}
      </button>
    ) : undefined;

  const occupationLabels = (caseData.occupations ?? []).map((id) => itemLabel(catalogItems, id, null)).filter(Boolean).join(' · ');

  return (
    <div>
      <h3 className="mb-4 border-b pb-2 text-sm font-bold uppercase tracking-wider text-carbon">{t('profile.title')}</h3>
      <p className="mb-3 text-sm text-gray-600">{t('profile.subtitle')}</p>
      <div className="grid grid-cols-1 gap-4 text-xs md:grid-cols-2 lg:grid-cols-3">
        <Row
          label={t('profile.education')}
          value={itemLabel(catalogItems, person.education_level_item_id, null)}
          button={change('education_level', !!person.education_level_item_id, 'profile.register')}
        />
        <Row
          label={t('profile.marital')}
          value={itemLabel(catalogItems, person.marital_status_item_id, null)}
          button={change('marital_status', !!person.marital_status_item_id, 'profile.register')}
        />
        <Row
          label={t('profile.department')}
          value={itemLabel(catalogItems, person.origin_department_item_id, null)}
          note={canEdit && !sensitiveOk ? t('diccionarios.only_no_response') : canEdit && nationality === null && !person.origin_department_item_id ? t('profile.department_needs_nationality') : null}
          button={change('origin_department', !!person.origin_department_item_id, 'profile.register')}
        />
        <Row label={t('profile.reference')} value={caseData.reference_number ?? null} button={change('reference', !!caseData.reference_number, 'profile.register')} />
      </div>

      <OccupationChecklist
        personId={caseData.titular_person_id}
        items={of('occupation')}
        currentIds={caseData.occupations ?? []}
        summary={occupationLabels}
        canEdit={canEdit}
        onChanged={onChanged}
      />

      {editing && editing !== 'reference' && (
        <CatalogItemModal
          title={t(`profile.modal.${editing}`)}
          hint={t(`profile.hint.${editing}`)}
          items={editing === 'origin_department' ? departments : of(editing)}
          sensitiveOk={editing === 'origin_department' ? sensitiveOk : true}
          withDetail={false}
          initialItemId={(editing === 'education_level' ? person.education_level_item_id : editing === 'marital_status' ? person.marital_status_item_id : person.origin_department_item_id) ?? null}
          initialDetail=""
          onSubmit={async (itemId, _detail, reason) => {
            await dataApi.setPersonProfileItem(caseData.titular_person_id, editing, itemId, reason);
            await saved();
          }}
          onClose={() => setEditing(null)}
        />
      )}
      {editing === 'reference' && (
        <SmallFieldModal
          title={t('profile.modal.reference')}
          hint={t('profile.hint.reference')}
          label={t('profile.reference')}
          initialValue={caseData.reference_number ?? ''}
          maxLength={40}
          reasonWhenChanged={!!caseData.reference_number}
          allowClear
          onSubmit={async (value, reason) => {
            await dataApi.setCaseReferenceNumber(caseData.id, value, reason);
            await saved();
          }}
          onClose={() => setEditing(null)}
        />
      )}
    </div>
  );
};

// Ocupación en su lugar de origen: hasta 3 casillas, o «La persona no quiso responder» sola. Siempre hay una (obligatoria).
const OccupationChecklist: React.FC<{
  personId: string;
  items: CatalogItem[];
  currentIds: string[];
  summary: string;
  canEdit: boolean;
  onChanged: () => Promise<void>;
}> = ({ personId, items, currentIds, summary, canEdit, onChanged }) => {
  const uid = React.useId();
  const toast = useToast();
  const active = items.filter((i) => i.is_active || currentIds.includes(i.id));
  const noResponse = active.find((i) => i.key === 'no_response');
  const [selected, setSelected] = useState<string[]>(currentIds);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const removed = currentIds.filter((id) => !selected.includes(id));
  const changed = removed.length > 0 || selected.some((id) => !currentIds.includes(id));
  const blocked: string | null = !changed
    ? t('case_extra.unchanged')
    : selected.length === 0
      ? t('profile.occupation_required')
      : removed.length > 0 && reason.trim() === ''
        ? t('profile.occupation_reason')
        : null;

  const toggle = (item: CatalogItem) =>
    setSelected((prev) => {
      if (prev.includes(item.id)) return prev.filter((x) => x !== item.id);
      if (item.key === 'no_response') return [item.id];
      return [...prev.filter((x) => x !== noResponse?.id), item.id];
    });

  const save = async () => {
    if (blocked || busy) return;
    setBusy(true);
    setError(null);
    try {
      await dataApi.setPersonOccupations(personId, selected, reason);
      toast.success(t('case_extra.saved'));
      await onChanged();
      setReason('');
    } catch (e) {
      setError(friendlyError(e));
    }
    setBusy(false);
  };

  return (
    <div className="mt-5">
      <span className="block text-xs text-gray-500">{t('profile.occupation')}</span>
      {!canEdit ? (
        <span className="text-sm font-semibold text-carbon">{summary || t('common.not_recorded')}</span>
      ) : (
        <>
          <p className="mb-2 text-sm text-gray-600">{t('profile.occupation_hint')}</p>
          <fieldset>
            <legend className="sr-only">{t('profile.occupation')}</legend>
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
              {active.map((i) => {
                const checked = selected.includes(i.id);
                const full = !checked && i.key !== 'no_response' && selected.filter((x) => x !== noResponse?.id).length >= MAX_OCCUPATIONS;
                return (
                  <label key={i.id} className={`flex min-h-11 items-center gap-3 rounded-xl border p-3 text-sm ${checked ? 'border-turquesa bg-claro font-semibold text-carbon' : 'border-gray-200 text-gray-700'} ${full ? 'opacity-50' : ''}`}>
                    <input type="checkbox" className="h-4 w-4 rounded border-gray-300 text-turquesa" checked={checked} disabled={full} onChange={() => toggle(i)} />
                    <span>{i.label_es}</span>
                  </label>
                );
              })}
            </div>
          </fieldset>
          {removed.length > 0 && (
            <div className="mt-3">
              <label className="block text-sm font-semibold text-gray-800" htmlFor={`${uid}-r`}>{t('case_extra.reason_label')}</label>
              <input id={`${uid}-r`} name={`${uid}-r`} autoComplete="off" className="mt-1 w-full rounded-lg border border-gray-300 p-3 text-base focus:border-turquesa focus:outline-none"
                value={reason} onChange={(e) => setReason(e.target.value)} />
            </div>
          )}
          {error && <p role="alert" className="mt-3 rounded-lg border border-alerta-dark/40 bg-alerta-bg/40 p-3 text-sm font-semibold text-alerta-dark">{error}</p>}
          <div className="mt-3">
            <DisabledReason id={uid} reason={blocked} className="mb-2" />
            <button type="button" onClick={() => void save()} disabled={!!blocked || busy} {...describedBy(uid, blocked)}
              className="min-h-11 rounded-lg bg-carbon px-5 text-sm font-bold text-white hover:bg-black disabled:cursor-not-allowed disabled:opacity-50">
              {busy ? t('case_extra.saving') : t('profile.occupation_save')}
            </button>
          </div>
        </>
      )}
    </div>
  );
};
