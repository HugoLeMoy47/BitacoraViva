import React, { useEffect } from 'react';
import { enterCaptureMode } from '../lib/captureMode';

// Barra de acciones de un formulario o asistente: siempre a la vista al pie. En celular ocupa el lugar de la navegación
// inferior (que se oculta mientras la barra esté en pantalla) para no apilar tres barras fijas sobre el contenido.
export const ActionBar: React.FC<{ className?: string; children: React.ReactNode }> = ({ className = '', children }) => {
  useEffect(() => enterCaptureMode(), []);
  return (
    <div
      data-action-bar
      className={`sticky bottom-0 z-30 -mx-4 border-t border-gray-200 bg-white/95 px-4 pb-[calc(0.75rem+env(safe-area-inset-bottom))] pt-3 backdrop-blur md:mx-0 md:rounded-2xl md:border md:pb-3 ${className}`}
    >
      {children}
    </div>
  );
};
