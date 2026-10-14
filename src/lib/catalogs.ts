import { VulnerabilityMarkerCode } from '../types/database';
import { t } from './i18n';

// Catálogo cerrado MAP-OIM v3 (13 marcadores). Es parte del estándar, no dato de la organización.
export const VULNERABILITY_CATALOG: Record<VulnerabilityMarkerCode, { label: string; description: string }> = {
  unaccompanied_child: { label: 'Niñez No Acompañada', description: 'Menor de 18 años que viaja sin persona adulta responsable.' },
  separated_child: { label: 'Niñez Separada', description: 'Menor de 18 años separado de sus padres pero con parientes.' },
  pregnant_or_lactating: { label: 'Embarazo o Lactancia', description: 'Mujer en estado de gestación o con infante lactante.' },
  victim_of_violence: { label: 'Sobreviviente de Violencia', description: 'Víctima de violencia física, extorsión, trata o delito grave.' },
  medical_condition: { label: 'Condición de Salud Crónica', description: 'Requiere atención médica continua o medicamento controlado.' },
  disability: { label: 'Discapacidad', description: 'Discapacidad física, sensorial, intelectual o psicosocial.' },
  lgbtiq: { label: 'Población LGBTIQ+', description: 'Vulnerabilidad por orientación sexual o identidad de género.' },
  indigenous_language_speaker: { label: 'Lengua Indígena / Intérprete', description: 'Requiere facilitación lingüística cultural.' },
  stateless_or_at_risk: { label: 'Apatridia o Riesgo', description: 'Sin nacionalidad reconocida por ningún Estado.' },
  survivor_torture_trauma: { label: 'Trauma o Tortura', description: 'Afectación psicosocial severa por tortura o persecución.' },
  international_protection_need: { label: 'Necesidad Protección Internacional', description: 'Riesgo manifiesto a la vida en caso de retorno forzado.' },
  older_person_at_risk: { label: 'Persona Adulta Mayor en Riesgo', description: 'Mayor de 60 años en condición de desamparo o fragilidad.' },
  other_vulnerability: { label: 'Otra Situación de Riesgo', description: 'Circunstancia especial identificada por profesional.' },
};

// Países del estándar con identificador propio; cualquier otro va como «otro» (id 1) más texto libre.
const COUNTRY_KEY: Record<number, string> = { 93: 'catalogs.country.93', 86: 'catalogs.country.86' };

/** Texto libre recortado; null si falta, para que la pantalla muestre `cases.not_specified`. */
export function freeTextOrNull(value?: string | null): string | null {
  const v = value?.trim();
  return v ? v : null;
}

/** País de nacionalidad: catálogo por id; si es «otro», el texto escrito; si no hay dato, null. */
export function countryLabel(id?: number | null, other?: string | null): string | null {
  const key = id != null ? COUNTRY_KEY[id] : undefined;
  return key ? t(key) : freeTextOrNull(other);
}

/** Idioma principal: no hay catálogo de idiomas en la base (id 1 es «otro»); se muestra el texto escrito. */
export function languageLabel(_id?: number | null, other?: string | null): string | null {
  return freeTextOrNull(other);
}
