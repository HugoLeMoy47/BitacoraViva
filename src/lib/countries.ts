// Catálogo de países ISO 3166-1 (alfa-2) para la nacionalidad, sin texto libre (ciclo «Ingreso y expediente», decisión C3 del
// 01 nov 2026). Los nombres salen de `Intl.DisplayNames` en español; aquí solo se decide el continente de cada código.
//
// Compatibilidad: la base conserva `nationality_country_id` (Honduras 93, Guatemala 86 y «otro» 1) de la que dependen el
// diccionario de departamentos de origen y los indicadores; el código ISO se guarda aparte (`person.nationality_iso`).

import { getLocale, intlTag } from './i18n';

export const CONTINENTS = [
  'América del Norte y Central',
  'América del Sur',
  'Europa',
  'Asia',
  'África',
  'Oceanía',
  'Antártida y territorios australes',
] as const;
export type Continent = (typeof CONTINENTS)[number];

const CODES: Record<Continent, string> = {
  'América del Norte y Central':
    'AG AI AW BB BL BM BQ BS BZ CA CR CU CW DM DO GD GL GP GT HN HT JM KN KY LC MF MQ MS MX NI PA PM PR SV SX TC TT US VC VG VI',
  'América del Sur': 'AR BO BR CL CO EC FK GF GY PE PY SR UY VE',
  Europa: 'AD AL AT AX BA BE BG BY CH CZ DE DK EE ES FI FO FR GB GG GI GR HR HU IE IM IS IT JE LI LT LU LV MC MD ME MK MT NL NO PL PT RO RS RU SE SI SJ SK SM UA VA',
  Asia: 'AE AF AM AZ BD BH BN BT CC CN CX CY GE HK ID IL IN IO IQ IR JO JP KG KH KP KR KW KZ LA LB LK MM MN MO MV MY NP OM PH PK PS QA SA SG SY TH TJ TL TM TR TW UZ VN YE',
  África: 'AO BF BI BJ BW CD CF CG CI CM CV DJ DZ EG EH ER ET GA GH GM GN GQ GW KE KM LR LS LY MA MG ML MR MU MW MZ NA NE NG RE RW SC SD SH SL SN SO SS ST SZ TD TG TN TZ UG YT ZA ZM ZW',
  Oceanía: 'AS AU CK FJ FM GU KI MH MP NC NF NR NU NZ PF PG PN PW SB TK TO TV UM VU WF WS',
  'Antártida y territorios australes': 'AQ BV GS HM TF',
};

export interface Country {
  iso: string;
  name_es: string;
  continent: Continent;
}

const names = new Intl.DisplayNames(['es'], { type: 'region' });
const nameOf = (iso: string): string | null => {
  try {
    const n = names.of(iso);
    return n && n !== iso ? n : null;
  } catch {
    return null;
  }
};

const plain = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
const byName = (a: Country, b: Country) => a.name_es.localeCompare(b.name_es, 'es');

// Los nombres en español son los que se guardan (other_nationality) y los que ordenan el catálogo base. Para
// mostrar, cada idioma arma sus propios nombres con Intl.DisplayNames y su propio orden alfabético.
const displayCache = new Map<string, { names: Map<string, string>; list: Country[] }>();
function display(): { names: Map<string, string>; list: Country[] } {
  const loc = getLocale();
  let d = displayCache.get(loc);
  if (!d) {
    if (loc === 'es') {
      d = { names: new Map(COUNTRIES.map((c) => [c.iso, c.name_es])), list: COUNTRIES };
    } else {
      const dn = new Intl.DisplayNames([intlTag()], { type: 'region' });
      const names = new Map(COUNTRIES.map((c) => {
        let n: string | undefined;
        try { n = dn.of(c.iso); } catch { n = undefined; }
        return [c.iso, n && n !== c.iso ? n : c.name_es] as [string, string];
      }));
      const tag = intlTag();
      d = { names, list: [...COUNTRIES].sort((a, b) => (names.get(a.iso) as string).localeCompare(names.get(b.iso) as string, tag)) };
    }
    displayCache.set(loc, d);
  }
  return d;
}

/** Nombre del país en el idioma activo, para mostrar. */
export const countryLabel = (c: Country): string => display().names.get(c.iso) ?? c.name_es;

export const COUNTRIES: Country[] = (Object.entries(CODES) as [Continent, string][])
  .flatMap(([continent, list]) => list.split(' ').map((iso) => ({ iso, name_es: nameOf(iso) ?? iso, continent })))
  .sort(byName);

const BY_ISO = new Map(COUNTRIES.map((c) => [c.iso, c]));

/** Nombre en español de un código ISO, el que se guarda en la base; null si el código no existe (no se inventa un nombre). */
export const countryNameEs = (iso: string | null | undefined): string | null => (iso ? BY_ISO.get(iso)?.name_es ?? null : null);

/** Nombre de un código ISO en el idioma activo, para mostrar; null si el código no existe. */
export const countryName = (iso: string | null | undefined): string | null => {
  const c = iso ? BY_ISO.get(iso) : undefined;
  return c ? countryLabel(c) : null;
};

/** Los países en el orden alfabético del idioma activo. */
export const countriesInOrder = (): Country[] => display().list;

/** Búsqueda predictiva: por nombre (sin importar mayúsculas ni acentos) o por código ISO. Sin texto, todos por nombre. */
export function searchCountries(query: string): Country[] {
  const q = plain(query.trim());
  const list = display().list;
  if (!q) return list;
  return list.filter((c) => plain(c.name_es).includes(q) || plain(countryLabel(c)).includes(q) || c.iso.toLowerCase() === q);
}

/** Agrupa por continente, en el orden definido y sin los continentes vacíos. */
/** Clave de traducción del nombre de un continente. */
export const continentKey = (c: Continent): string => `countries.continents.c${CONTINENTS.indexOf(c) + 1}`;

export function groupByContinent(list: Country[]): { continent: Continent; countries: Country[] }[] {
  return CONTINENTS.map((continent) => ({ continent, countries: list.filter((c) => c.continent === continent) })).filter((g) => g.countries.length > 0);
}

/** Identificador del estándar que la base conserva: Honduras 93, Guatemala 86 y cualquier otro país «otro» (1). Sin país, no hay id. */
export function legacyCountryId(iso: string | null | undefined): number | null {
  if (!iso) return null;
  return iso === 'HN' ? 93 : iso === 'GT' ? 86 : 1;
}
