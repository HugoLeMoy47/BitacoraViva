import { useSyncExternalStore } from 'react';

// Por debajo de 640 px (el corte `sm:` de Tailwind) el tablero de tareas cambia de FORMA, no se
// estrecha: una columna a la vez y el avance por botón. El tablero de tres columnas ocupa ~692 px;
// en un Android de 360 no queda ni una zona de destino completa a la vista, así que arrastrar no
// tiene a dónde llegar. Se lee en el primer render para no parpadear la disposición equivocada.
const QUERY = '(max-width: 639px)';

function subscribe(callback: () => void): () => void {
  const mql = window.matchMedia(QUERY);
  mql.addEventListener('change', callback);
  return () => mql.removeEventListener('change', callback);
}

export function usePhoneScreen(): boolean {
  return useSyncExternalStore(
    subscribe,
    () => window.matchMedia(QUERY).matches,
    () => false
  );
}
