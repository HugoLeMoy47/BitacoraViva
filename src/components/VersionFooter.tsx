import React from 'react';
import { t } from '../lib/i18n';

// Pie con la versión en ejecución: permite comprobar que lo publicado en la URL es lo esperado.
const { version, commit, built } = __BUILD_INFO__;

export const VersionFooter: React.FC<{ className?: string }> = ({ className = '' }) => {
  const date = new Date(built).toLocaleString('es-MX', { dateStyle: 'medium', timeStyle: 'short' });
  return (
    <footer className={`text-center text-xs text-gray-600 ${className}`}>
      <p translate="no">
        {t('app.version_label')} {version} · <span className="font-mono">{commit}</span> · {date}
      </p>
    </footer>
  );
};
