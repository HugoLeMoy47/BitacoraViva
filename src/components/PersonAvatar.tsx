import React from 'react';
import { t } from '../lib/i18n';

/**
 * Lugar de la fotografía de identificación visual: una silueta genérica. Mientras la lectura de fotografías (URL firmada con
 * auditoría) no exista, es lo único que se dibuja, haya o no autorización firmada; no usa ningún dato de la persona.
 */
export const PersonAvatar: React.FC<{ size?: number; photoConsent?: boolean | null }> = ({ size = 72, photoConsent }) => {
  const caption =
    photoConsent === true ? t('cases.sheet.photo_authorized')
    : photoConsent === false ? t('cases.sheet.photo_not_authorized')
    : t('cases.sheet.photo_not_recorded');
  return (
    <figure className="flex items-center gap-3">
      <svg role="img" aria-label={t('cases.sheet.photo_alt')} width={size} height={size} viewBox="0 0 72 72" className="shrink-0 rounded-2xl bg-claro">
        <circle cx="36" cy="27" r="12" fill="#9CA3AF" />
        <path d="M12 66c0-13.3 10.7-22 24-22s24 8.7 24 22v6H12z" fill="#9CA3AF" />
      </svg>
      <figcaption className="text-xs text-gray-700">
        <span className="block font-semibold text-carbon">{t('cases.sheet.photo_title')}</span>
        {caption}
      </figcaption>
    </figure>
  );
};
