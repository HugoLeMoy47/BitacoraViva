import React, { createContext, useContext, useEffect, useState } from 'react';
import { supabase } from './supabase';

// El entorno lo declara la base (public.app_config, vía fn_app_environment), no el
// bundle: así la interfaz no puede contradecir a los datos que muestra.
//   demo        → aviso de demo + acceso rápido con cuentas de demostración
//   production  → sin aviso y sin cuentas de demostración
//   unknown     → no se pudo consultar: se muestra el aviso (lado seguro) pero no el acceso rápido
export type EnvironmentMode = 'demo' | 'production' | 'unknown';

interface EnvironmentValue {
  mode: EnvironmentMode;
  isDemo: boolean;
  allowDemoAccounts: boolean;
}

const EnvironmentContext = createContext<EnvironmentValue>({
  mode: 'unknown',
  isDemo: true,
  allowDemoAccounts: false,
});

const BASE_TITLE = typeof document !== 'undefined' ? document.title : '';

export const EnvironmentProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [mode, setMode] = useState<EnvironmentMode>('unknown');

  useEffect(() => {
    let cancelled = false;
    supabase.rpc('fn_app_environment').then(({ data, error }) => {
      if (cancelled) return;
      if (error || (data !== 'demo' && data !== 'production')) setMode('unknown');
      else setMode(data);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  const isDemo = mode !== 'production';

  useEffect(() => {
    document.title = isDemo ? `DEMO · ${BASE_TITLE}` : BASE_TITLE;
  }, [isDemo]);

  return (
    <EnvironmentContext.Provider value={{ mode, isDemo, allowDemoAccounts: mode === 'demo' }}>
      {children}
    </EnvironmentContext.Provider>
  );
};

export function useEnvironment(): EnvironmentValue {
  return useContext(EnvironmentContext);
}
