import React, { useState } from 'react';
import { FlaskConical, X } from 'lucide-react';
import { t } from '../lib/i18n';
import { useEnvironment } from '../lib/environment';

const KEY = 'bv.demo-banner.dismissed';
const read = () => {
  try {
    return sessionStorage.getItem(KEY) === '1';
  } catch {
    return false;
  }
};

// Franja de una línea mientras el entorno no sea producción. Se puede descartar para la sesión
// (el chip «DEMO» del encabezado nunca desaparece) y desplegar para leer el detalle.
export const DemoBanner: React.FC = () => {
  const { isDemo } = useEnvironment();
  const [dismissed, setDismissed] = useState(read);
  const [expanded, setExpanded] = useState(false);
  if (!isDemo || dismissed) return null;

  return (
    <div role="note" className="border-b border-amber-600 bg-amber-400 text-carbon">
      <div className="mx-auto flex max-w-7xl items-start gap-2 px-3 py-1.5 text-xs sm:px-6 lg:px-8">
        <FlaskConical className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
        <p className="min-w-0 flex-1">
          <strong className="font-bold uppercase tracking-wide">{t('demo.banner_title')}</strong> {t('demo.banner_short')}
          {expanded && <span className="block pt-1">{t('demo.banner_more')}</span>}
        </p>
        <button
          type="button"
          onClick={() => setExpanded((v) => !v)}
          aria-expanded={expanded}
          className="inline-flex min-h-8 min-w-8 shrink-0 items-center justify-center rounded px-2 font-semibold underline"
        >
          {expanded ? t('demo.less') : t('demo.more')}
        </button>
        <button
          type="button"
          onClick={() => {
            try {
              sessionStorage.setItem(KEY, '1');
            } catch {
              /* sin almacenamiento: se descarta sólo en memoria */
            }
            setDismissed(true);
          }}
          aria-label={t('common.close')}
          className="inline-flex min-h-8 min-w-8 shrink-0 items-center justify-center rounded hover:bg-black/10"
        >
          <X className="h-4 w-4" aria-hidden="true" />
        </button>
      </div>
    </div>
  );
};

// Etiqueta compacta que acompaña al encabezado fijo.
export const DemoChip: React.FC = () => {
  const { isDemo } = useEnvironment();
  if (!isDemo) return null;
  return (
    <span className="shrink-0 rounded bg-amber-400 px-2 py-0.5 text-xs font-bold uppercase tracking-wider text-carbon">
      {t('demo.chip')}
    </span>
  );
};
