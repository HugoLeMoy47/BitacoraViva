import React, { useEffect, useState } from 'react';
import { t } from '../lib/i18n';
import { dataApi } from '../lib/data';

// Nombre del municipio a partir de su clave del INEGI (5 dígitos). Si no se registró, lo dice: nunca inventa uno.
export const MunicipalityName: React.FC<{ municipalityKey?: string | null }> = ({ municipalityKey }) => {
  const [name, setName] = useState<string | null>(null);
  useEffect(() => {
    setName(null);
    if (!municipalityKey) return;
    let cancelled = false;
    dataApi.listMunicipalities(municipalityKey.slice(0, 2))
      .then((list) => { if (!cancelled) setName(list.find((m) => m.cvegeo === municipalityKey)?.name ?? null); })
      .catch(() => { /* sin nombre: se muestra la clave */ });
    return () => { cancelled = true; };
  }, [municipalityKey]);
  if (!municipalityKey) return <>{t('common.not_recorded')}</>;
  return <>{name ?? municipalityKey}</>;
};
