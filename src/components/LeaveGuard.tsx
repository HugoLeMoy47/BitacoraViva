import { useEffect } from 'react';
import { t } from '../lib/i18n';

// Salir de un formulario con algo escrito: el navegador avisa antes de recargar o cerrar, y dentro de la
// aplicación se pide confirmación («Descartar y salir» / «Seguir»). Las páginas de captura lo comparten.
export function useBeforeUnloadGuard(dirty: boolean): void {
  useEffect(() => {
    if (!dirty) return;
    const guard = (e: BeforeUnloadEvent) => e.preventDefault();
    window.addEventListener('beforeunload', guard);
    return () => window.removeEventListener('beforeunload', guard);
  }, [dirty]);
}

export const DiscardConfirm: React.FC<{ onDiscard: () => void; onKeep: () => void }> = ({ onDiscard, onKeep }) => (
  <div role="alert" className="rounded-xl border border-alerta/30 bg-alerta-bg p-4 text-sm">
    <p className="font-bold text-alerta-dark">{t('common.discard_title')}</p>
    <p className="mt-1 text-carbon">{t('common.discard_body')}</p>
    <div className="mt-3 flex flex-wrap gap-2">
      <button type="button" onClick={onDiscard} className="min-h-11 rounded-lg bg-carbon px-4 text-sm font-semibold text-white hover:bg-black">
        {t('common.discard_confirm')}
      </button>
      <button type="button" onClick={onKeep} className="min-h-11 rounded-lg border border-gray-300 bg-white px-4 text-sm font-semibold text-gray-700 hover:bg-gray-50">
        {t('common.discard_keep')}
      </button>
    </div>
  </div>
);
