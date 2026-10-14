import React, { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react';
import { supabase } from './supabase';
import { RoleName, UserProfile, UserRole } from '../types/database';

// RNF-04: la sesión caduca por inactividad a los 30 minutos.
export const INACTIVITY_TIMEOUT_MS = 30 * 60 * 1000;
// RNF-04 / P-10: límite absoluto continuo de sesión de 12 horas (configurable por dirección).
export const ABSOLUTE_TIMEOUT_MS = 12 * 60 * 60 * 1000;
export const SESSION_STARTED_KEY = 'bv_session_started_at';

// Rol «principal» (para la etiqueta y las pantallas de casos): los de casos van antes que los de tareas.
const ROLE_PRIORITY: RoleName[] = ['director', 'intake_officer', 'caseworker', 'viewer', 'task_manager', 'volunteer'];

export interface SessionUser {
  profile: UserProfile;
  /** Rol principal; los permisos y las pantallas salen de TODOS los roles vigentes (`roles`) */
  role: RoleName;
  /** Todos los roles vigentes de la persona: se acumulan (ADR-0007) */
  roles: RoleName[];
  userRole: UserRole;
  /** Áreas a las que pertenece la persona por sus roles vigentes (compartimentación, Ethos C2) */
  areaIds: string[];
  assignedAreaId?: string;
  assignedAreaCode?: string;
  assignedAreaName?: string;
  enforceAbsoluteSessionTimeout?: boolean;
}

export type SessionStatus = 'loading' | 'anonymous' | 'authenticated';

// Claves de traducción (src/locales/es.json → login.*) para no llevar texto en lógica.
export type SessionNotice =
  | 'login.error_credentials'
  | 'login.error_no_role'
  | 'login.notice_expired'
  | 'login.notice_absolute_expired'
  | null;

interface SessionContextValue {
  status: SessionStatus;
  user: SessionUser | null;
  notice: SessionNotice;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
}

const SessionContext = createContext<SessionContextValue | null>(null);

async function loadSessionUser(userId: string): Promise<SessionUser | null> {
  const [profileRes, rolesRes] = await Promise.all([
    supabase.from('user_profile').select('*').eq('id', userId).maybeSingle(),
    supabase.from('user_role').select('*').eq('user_id', userId).is('revoked_at', null),
  ]);

  const profile = profileRes.data as UserProfile | null;
  const roles = (rolesRes.data || []) as UserRole[];
  if (!profile || !profile.active || roles.length === 0) return null;

  const userRole =
    ROLE_PRIORITY.map((r) => roles.find((x) => x.role_name === r)).find(Boolean) || roles[0];

  const [areaRes, orgRes] = await Promise.all([
    userRole.area_id
      ? supabase.from('area').select('id, code, name').eq('id', userRole.area_id).maybeSingle()
      : Promise.resolve({ data: null }),
    supabase
      .from('organization')
      .select('enforce_absolute_session_timeout')
      .eq('id', profile.organization_id)
      .maybeSingle(),
  ]);

  const area = areaRes.data;
  const enforceAbsolute = orgRes.data?.enforce_absolute_session_timeout ?? true;

  return {
    profile,
    role: userRole.role_name,
    roles: Array.from(new Set(roles.map((r) => r.role_name))),
    userRole,
    areaIds: Array.from(new Set(roles.map((r) => r.area_id).filter((a): a is string => !!a))),
    assignedAreaId: area?.id,
    assignedAreaCode: area?.code,
    assignedAreaName: area?.name,
    enforceAbsoluteSessionTimeout: enforceAbsolute,
  };
}

export const SessionProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [status, setStatus] = useState<SessionStatus>('loading');
  const [user, setUser] = useState<SessionUser | null>(null);
  const [notice, setNotice] = useState<SessionNotice>(null);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const applySession = useCallback(async (userId: string | null) => {
    if (!userId) {
      setUser(null);
      setStatus('anonymous');
      return;
    }
    const loaded = await loadSessionUser(userId);
    if (!loaded) {
      // Sin perfil activo o sin rol vigente: no se opera (BV-1.2).
      await supabase.auth.signOut();
      setUser(null);
      setNotice('login.error_no_role');
      setStatus('anonymous');
      return;
    }
    setUser(loaded);
    setStatus('authenticated');
  }, []);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => applySession(data.session?.user.id ?? null));
    // El callback no debe hacer llamadas a supabase de forma síncrona (deadlock del cliente).
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      setTimeout(() => applySession(session?.user.id ?? null), 0);
    });
    return () => sub.subscription.unsubscribe();
  }, [applySession]);

  // Cierre por inactividad (30 min) y verificación de límite absoluto continuo
  useEffect(() => {
    if (status !== 'authenticated') return;

    const expire = async () => {
      setNotice('login.notice_expired');
      await supabase.auth.signOut();
    };
    const reset = () => {
      if (user?.enforceAbsoluteSessionTimeout !== false) {
        const started = Number(sessionStorage.getItem(SESSION_STARTED_KEY) || Date.now());
        if (Date.now() - started >= ABSOLUTE_TIMEOUT_MS) {
          sessionStorage.removeItem(SESSION_STARTED_KEY);
          setNotice('login.notice_absolute_expired');
          void supabase.auth.signOut();
          return;
        }
      }
      if (timerRef.current) clearTimeout(timerRef.current);
      timerRef.current = setTimeout(expire, INACTIVITY_TIMEOUT_MS);
    };

    const events: (keyof WindowEventMap)[] = ['mousemove', 'keydown', 'click', 'touchstart', 'scroll'];
    events.forEach((e) => window.addEventListener(e, reset, { passive: true }));
    reset();

    return () => {
      events.forEach((e) => window.removeEventListener(e, reset));
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, [status, user?.enforceAbsoluteSessionTimeout]);

  // Límite absoluto continuo (12h) configurable por Dirección (RNF-04 / P-10)
  useEffect(() => {
    if (status !== 'authenticated') return;

    if (!sessionStorage.getItem(SESSION_STARTED_KEY)) {
      sessionStorage.setItem(SESSION_STARTED_KEY, String(Date.now()));
    }

    if (user?.enforceAbsoluteSessionTimeout === false) return;

    const started = Number(sessionStorage.getItem(SESSION_STARTED_KEY) || Date.now());
    const remaining = ABSOLUTE_TIMEOUT_MS - (Date.now() - started);

    const expireAbsolute = async () => {
      sessionStorage.removeItem(SESSION_STARTED_KEY);
      setNotice('login.notice_absolute_expired');
      await supabase.auth.signOut();
    };

    if (remaining <= 0) {
      void expireAbsolute();
      return;
    }

    const absTimer = setTimeout(expireAbsolute, remaining);
    return () => clearTimeout(absTimer);
  }, [status, user?.enforceAbsoluteSessionTimeout]);

  const signIn = useCallback(async (email: string, password: string) => {
    setNotice(null);
    sessionStorage.removeItem(SESSION_STARTED_KEY);
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    if (error) {
      setNotice('login.error_credentials');
    }
  }, []);

  const signOut = useCallback(async () => {
    setNotice(null);
    sessionStorage.removeItem(SESSION_STARTED_KEY);
    await supabase.auth.signOut();
  }, []);

  return (
    <SessionContext.Provider value={{ status, user, notice, signIn, signOut }}>
      {children}
    </SessionContext.Provider>
  );
};

export function useSession(): SessionContextValue {
  const ctx = useContext(SessionContext);
  if (!ctx) throw new Error('useSession debe usarse dentro de SessionProvider');
  return ctx;
}
