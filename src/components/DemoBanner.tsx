import React from 'react';
import { FlaskConical } from 'lucide-react';
import { t } from '../lib/i18n';
import { useEnvironment } from '../lib/environment';

// Franja visible en todas las pantallas mientras el entorno no sea producción.
export const DemoBanner: React.FC = () => {
  const { isDemo } = useEnvironment();
  if (!isDemo) return null;

  return (
    <div role="note" className="bg-amber-400 text-carbon border-b border-amber-600">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-1.5 flex items-start gap-2 text-xs">
        <FlaskConical className="w-4 h-4 mt-px shrink-0" />
        <p>
          <strong className="font-bold uppercase tracking-wide">{t('demo.banner_title')}</strong>{' '}
          {t('demo.banner_text')}
        </p>
      </div>
    </div>
  );
};

// Etiqueta compacta que acompaña al encabezado fijo.
export const DemoChip: React.FC = () => {
  const { isDemo } = useEnvironment();
  if (!isDemo) return null;
  return (
    <span className="bg-amber-400 text-carbon text-[10px] font-bold uppercase tracking-wider px-2 py-0.5 rounded">
      {t('demo.chip')}
    </span>
  );
};
