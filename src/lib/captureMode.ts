import { useSyncExternalStore } from 'react';

// «Modo captura»: mientras haya una barra de acciones en pantalla (formularios y asistentes), la navegación inferior
// del celular se oculta. Cada barra pide el modo al montarse y lo suelta al desmontarse; mientras quede una, sigue encendido.
let active = 0;
const listeners = new Set<() => void>();
const emit = () => listeners.forEach((l) => l());

export function enterCaptureMode(): () => void {
  active += 1;
  emit();
  let released = false;
  return () => {
    if (released) return;
    released = true;
    active -= 1;
    emit();
  };
}

export const isCaptureMode = () => active > 0;

export function subscribeCaptureMode(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export const useCaptureMode = () => useSyncExternalStore(subscribeCaptureMode, isCaptureMode, () => false);
