import React, { useEffect, useRef } from 'react';
import { PartyPopper, Star } from 'lucide-react';
import { t } from '../lib/i18n';
import { launchConfetti } from '../lib/confetti';
import { ModalShell } from './ModalShell';

// Reconocimiento al cerrar una tarea. Usa el cascarón accesible de modal (foco atrapado, Escape),
// lanza una ráfaga sutil de confeti si la persona no pidió menos movimiento y se cierra sola para
// no estorbar a quien tiene las manos ocupadas; la última tarea de la jornada da más tiempo.

interface VictoryModalProps {
  taskName: string;
  message: string;
  isLast: boolean;
  onClose: () => void;
}

export const VictoryModal: React.FC<VictoryModalProps> = ({ taskName, message, isLast, onClose }) => {
  // El cierre se lee por referencia: si cambiara su identidad en cada render, la ráfaga de confeti
  // y el temporizador se reiniciarían con cualquier actualización de la pantalla de atrás
  const closeRef = useRef(onClose);
  closeRef.current = onClose;

  useEffect(() => {
    launchConfetti();
    const timer = window.setTimeout(() => closeRef.current(), isLast ? 8000 : 5000);
    return () => window.clearTimeout(timer);
  }, [isLast]);

  return (
    <ModalShell onClose={onClose} className="fixed inset-0 z-50 flex items-center justify-center bg-carbon/50 p-4 backdrop-blur-sm">
      <div className="w-full max-w-sm rounded-3xl border border-turquesa/40 bg-white p-6 text-center shadow-2xl">
        {isLast ? (
          <Star className="mx-auto mb-3 h-10 w-10 text-turquesa-dark" aria-hidden="true" />
        ) : (
          <PartyPopper className="mx-auto mb-3 h-10 w-10 text-turquesa-dark" aria-hidden="true" />
        )}
        <h3 className="text-lg font-bold leading-snug text-carbon">{t(isLast ? 'tasks.victory_title_last' : 'tasks.victory_title')}</h3>
        <p className="mt-1 line-clamp-2 break-words text-xs font-semibold text-turquesa-dark">{taskName}</p>
        <p className="mt-3 text-sm leading-relaxed text-carbon-muted">{message}</p>
        <button
          type="button"
          onClick={onClose}
          className="mt-5 min-h-11 w-full rounded-xl bg-turquesa px-6 text-sm font-semibold text-carbon hover:bg-turquesa-hover"
        >
          {t(isLast ? 'tasks.victory_last_button' : 'tasks.victory_continue')}
        </button>
      </div>
    </ModalShell>
  );
};
