import React from 'react';
import { t } from '../lib/i18n';
import { useCatalog } from '../lib/catalog';
import { ageYears, bandFor, birthdayMonth, stayDays } from '../lib/derived';
import { CaseWithDetails } from '../types/database';

// Datos derivados (E14 fase 5): se calculan al mostrarlos y no se guardan. Si falta un dato o no es exacto no se
// supone nada: se dice por qué no se puede calcular. El grupo por edad es SOLO por edad (el sexo es un dato sensible).
export const CaseDerivedPanel: React.FC<{ caseData: CaseWithDetails }> = ({ caseData }) => {
  const { ageBands } = useCatalog();
  const today = new Date();
  const person = caseData.person;
  const age = ageYears(person.birth_date, today);
  const band = bandFor(ageBands, age);
  const month = birthdayMonth(person.birth_date, person.birth_date_is_estimated);
  const dates = (caseData.dates ?? []).filter((d) => !d.valid_to);
  const days = stayDays(
    dates.find((d) => d.kind === 'shelter_entry'),
    dates.find((d) => d.kind === 'shelter_exit'),
    caseData.statuses.shelter_status?.valueCode === 'sheltered',
    today
  );
  const monthName = month ? new Date(2000, month - 1, 1).toLocaleDateString('es-MX', { month: 'long' }) : null;

  const Item: React.FC<{ label: string; value: string | null; why: string }> = ({ label, value, why }) => (
    <div>
      <span className="block text-gray-500">{label}</span>
      <span className="text-sm font-semibold text-carbon">{value ?? <span className="font-normal text-gray-600">{why}</span>}</span>
    </div>
  );

  return (
    <div>
      <h3 className="mb-4 border-b pb-2 text-sm font-bold uppercase tracking-wider text-carbon">{t('derived.title')}</h3>
      <p className="mb-3 text-sm text-gray-600">{t('derived.subtitle')}</p>
      <div className="grid grid-cols-1 gap-4 text-xs md:grid-cols-2 lg:grid-cols-4">
        <Item
          label={t('derived.age')}
          value={age === null ? null : `${age} ${t('derived.years')}${person.birth_date_is_estimated ? ` (${t('derived.approx')})` : ''}`}
          why={t('derived.why_age')}
        />
        <Item
          label={t('derived.age_group')}
          value={band?.label_es ?? null}
          why={age === null ? t('derived.why_age') : t('derived.why_no_bands')}
        />
        <Item label={t('derived.birthday_month')} value={monthName} why={person.birth_date_is_estimated ? t('derived.why_estimated') : t('derived.why_age')} />
        <Item
          label={t('derived.stay_days')}
          value={days === null ? null : `${days} ${t('derived.days')}`}
          why={t('derived.why_stay')}
        />
      </div>
    </div>
  );
};
