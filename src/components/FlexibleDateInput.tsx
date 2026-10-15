import React from 'react';
import { t } from '../lib/i18n';
import { DatePrecision } from '../lib/flexDate';

// Fecha que puede conocerse completa, solo con mes o solo con año (E14 fase 2). Dos controles juntos: cuánto se sabe
// (día, mes o año) y el valor. Cambiar la precisión limpia lo escrito: un «2026-03-15» no es un mes ni un año.
interface Props {
  id: string;
  label: string;
  precision: DatePrecision;
  value: string;
  onChange: (precision: DatePrecision, value: string) => void;
  /** Mensaje de error del campo, dicho junto al campo */
  problem?: string | null;
}

const CONTROL = 'w-full min-h-11 text-sm p-2.5 border rounded-lg border-gray-300 bg-white focus:outline-none focus:border-turquesa';

export const FlexibleDateInput: React.FC<Props> = ({ id, label, precision, value, onChange, problem }) => (
  <fieldset className="min-w-0">
    <legend className="mb-1 block text-sm font-medium text-gray-700">{label}</legend>
    <div className="grid grid-cols-3 gap-2">
      <div className="col-span-1">
        <label className="sr-only" htmlFor={`${id}-p`}>{t('dates.precision_label')}</label>
        <select id={`${id}-p`} className={CONTROL} value={precision} onChange={(e) => onChange(e.target.value as DatePrecision, '')}>
          <option value="day">{t('dates.precision_day')}</option>
          <option value="month">{t('dates.precision_month')}</option>
          <option value="year">{t('dates.precision_year')}</option>
        </select>
      </div>
      <div className="col-span-2">
        <label className="sr-only" htmlFor={`${id}-v`}>{label}</label>
        {precision === 'day' && (
          <input id={`${id}-v`} type="date" className={CONTROL} value={value} max={new Date().toISOString().slice(0, 10)}
            onChange={(e) => onChange(precision, e.target.value)} aria-invalid={problem ? true : undefined} />
        )}
        {precision === 'month' && (
          <input id={`${id}-v`} type="month" className={CONTROL} value={value} max={new Date().toISOString().slice(0, 7)}
            onChange={(e) => onChange(precision, e.target.value)} aria-invalid={problem ? true : undefined} />
        )}
        {precision === 'year' && (
          <input id={`${id}-v`} type="number" inputMode="numeric" className={CONTROL} value={value} min={1900} max={new Date().getFullYear()}
            placeholder={t('dates.year_placeholder')} onChange={(e) => onChange(precision, e.target.value)} aria-invalid={problem ? true : undefined} />
        )}
      </div>
    </div>
    {problem && <p role="alert" className="mt-1 text-sm font-semibold text-alerta-dark">{problem}</p>}
  </fieldset>
);
