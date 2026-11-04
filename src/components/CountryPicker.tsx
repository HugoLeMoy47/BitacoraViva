import React, { useId, useMemo, useState } from 'react';
import { t, useLocale } from '../lib/i18n';
import { continentKey, countriesInOrder, countryLabel, groupByContinent, searchCountries } from '../lib/countries';

// País por ISO 3166-1 con búsqueda predictiva y agrupado por continente; sin texto libre (ciclo «Ingreso y expediente»).
// Escribir filtra la lista; se elige de la lista, nunca se teclea un nombre propio.
const FIELD = 'w-full text-xs p-2.5 border rounded-lg border-gray-300 focus:outline-none focus:border-turquesa disabled:bg-gray-100 disabled:text-gray-600 disabled:cursor-not-allowed';

export const CountryPicker: React.FC<{
  value: string;
  onChange: (iso: string) => void;
  disabled?: boolean;
  label: string;
}> = ({ value, onChange, disabled, label }) => {
  const uid = useId();
  const [query, setQuery] = useState('');
  const locale = useLocale();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const matches = useMemo(() => searchCountries(query), [query, locale]);
  // El país ya elegido sigue en la lista aunque la búsqueda lo oculte (si no, el selector mostraría otro)
  const shown = useMemo(() => {
    const chosen = value && !matches.some((c) => c.iso === value) ? countriesInOrder().find((c) => c.iso === value) : undefined;
    return chosen ? [...matches, chosen] : matches;
  }, [matches, value]);
  const groups = useMemo(() => groupByContinent(shown), [shown]);
  const found = matches.length;

  return (
    <div>
      <label className="mb-1 block text-xs font-medium text-gray-700" htmlFor={`${uid}-q`}>{label}</label>
      <input
        id={`${uid}-q`}
        name={`${uid}-q`}
        type="search"
        autoComplete="off"
        disabled={disabled}
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder={t('countries.search_placeholder')}
        aria-describedby={`${uid}-n`}
        className={`${FIELD} mb-1.5`}
      />
      <select
        id={`${uid}-s`}
        name={`${uid}-s`}
        autoComplete="off"
        disabled={disabled}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        aria-label={label}
        className={FIELD}
      >
        <option value="">{t('common.not_recorded')}</option>
        {groups.map((g) => (
          <optgroup key={g.continent} label={t(continentKey(g.continent))}>
            {g.countries.map((c) => <option key={c.iso} value={c.iso}>{countryLabel(c)}</option>)}
          </optgroup>
        ))}
      </select>
      <p id={`${uid}-n`} className="mt-1 text-xs text-gray-700" aria-live="polite">
        {query.trim() === '' ? '' : found === 0 ? t('countries.none_found') : t('countries.n_found').replace('{n}', String(found))}
      </p>
    </div>
  );
};
