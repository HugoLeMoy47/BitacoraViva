import { ArcoRequest } from '../types/database';

/**
 * Calcula la fecha límite en días hábiles (lunes a viernes) a partir de una fecha base.
 * De acuerdo con la LFPDPPP / normatividad mexicana, los plazos de respuesta ARCO
 * se computan en días hábiles (20 días hábiles por defecto).
 */
export function computeBusinessDaysDeadline(receivedAtStr: string, days = 20): string {
  const d = new Date(receivedAtStr);
  let added = 0;
  while (added < days) {
    d.setDate(d.getDate() + 1);
    const day = d.getDay();
    if (day !== 0 && day !== 6) {
      added++;
    }
  }
  return d.toISOString();
}

/**
 * Genera el número de expediente / folio formal ARCO con formato:
 * ARCO-{ORG_PREFIX}-{AÑO}-{4_DIGITOS_HEX_DE_ID}
 */
export function computeArcoDocket(req: Pick<ArcoRequest, 'id' | 'received_at'>, orgPrefix = 'BV'): string {
  const d = new Date(req.received_at);
  const year = isNaN(d.getTime()) ? new Date().getUTCFullYear() : d.getUTCFullYear();
  const shortId = req.id ? req.id.replace(/-/g, '').slice(0, 4).toUpperCase() : '0001';
  return `ARCO-${(orgPrefix || 'BV').toUpperCase()}-${year}-${shortId}`;
}
