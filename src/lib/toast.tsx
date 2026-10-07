import React, { createContext, useCallback, useContext, useRef, useState } from 'react';
import { CheckCircle2, AlertTriangle, X } from 'lucide-react';
import { t } from './i18n';

// Avisos breves y accesibles (aria-live) para confirmar o explicar el resultado de una acción.
type ToastKind = 'success' | 'error';
interface ToastItem {
  id: number;
  kind: ToastKind;
  message: string;
}

interface ToastApi {
  success: (message: string) => void;
  error: (message: string) => void;
}

const ToastContext = createContext<ToastApi>({ success: () => {}, error: () => {} });

export const ToastProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [items, setItems] = useState<ToastItem[]>([]);
  const seq = useRef(0);

  const dismiss = useCallback((id: number) => setItems((prev) => prev.filter((x) => x.id !== id)), []);

  const push = useCallback(
    (kind: ToastKind, message: string) => {
      const id = ++seq.current;
      setItems((prev) => [...prev.slice(-2), { id, kind, message }]);
      // Los errores permanecen más tiempo: hay que poder leerlos y actuar
      window.setTimeout(() => dismiss(id), kind === 'error' ? 9000 : 4500);
    },
    [dismiss]
  );

  const api = React.useMemo<ToastApi>(
    () => ({ success: (m) => push('success', m), error: (m) => push('error', m) }),
    [push]
  );

  return (
    <ToastContext.Provider value={api}>
      {children}
      <div
        aria-live="polite"
        className="fixed z-[60] inset-x-0 bottom-0 flex flex-col items-center gap-2 px-4 pb-[calc(env(safe-area-inset-bottom)+5.5rem)] md:pb-6 pointer-events-none"
      >
        {items.map((x) => (
          <div
            key={x.id}
            role={x.kind === 'error' ? 'alert' : 'status'}
            className={`pointer-events-auto flex w-full max-w-md items-start gap-2 rounded-xl border px-4 py-3 text-sm shadow-lg ${
              x.kind === 'error' ? 'border-alerta/30 bg-alerta-bg text-alerta' : 'border-turquesa/40 bg-white text-carbon'
            }`}
          >
            {x.kind === 'error' ? (
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
            ) : (
              <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-turquesa-dark" aria-hidden="true" />
            )}
            <span className="flex-1 break-words">{x.message}</span>
            <button type="button" onClick={() => dismiss(x.id)} aria-label={t('common.close')} className="shrink-0 rounded p-1 hover:bg-black/5">
              <X className="h-4 w-4" aria-hidden="true" />
            </button>
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
};

export function useToast(): ToastApi {
  return useContext(ToastContext);
}
