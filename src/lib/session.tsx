import React, { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react';
import { supabase } from './supabase';
import { RoleName, UserProfile, UserRole } from '../types/database';

// RNF-04: la sesión caduca por inactividad a los 30 minutos.
export const INACTIVITY_TIMEOUT_MS = 30 * 60 * 1000;

const ROLE_PRIORITY: RoleName[] = ['director', 'intake_officer', 'caseworker', 'viewer'];

export interface SessionUser {
  profile: UserProfile;
  role: RoleName;
  userRole: UserRole;
  assignedAreaId?: string;
  assignedAreaCode?: string;
  assignedAreaName?: string;
}

export type SessionStatus = 'loading' | 'anonymous' | 'authenticated';

// Claves de traducción (src/locales/es.json → login.*) para no llevar texto en lógica.
export type SessionNotice = 'login.error_credentials' | 'login.error_no_role' | 'login.notice_expired' | null;

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

  let area: { id: string; code: string; name: string } | null = null;
  if (userRole.area_id) {
    const { data } = await supabase
      .from('area')
      .select('id, code, name')
      .eq('id', userRole.area_id)
      .maybeSingle();
    area = data;
  }

  return {
    profile,
    role: userRole.role_name,
    userRole,
    assignedAreaId: area?.id,
    assignedAreaCode: area?.code,
    assignedAreaName: area?.name,
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

  // Cierre por inactividad
  useEffect(() => {
    if (status !== 'authenticated') return;

    const expire = async () => {
      setNotice('login.notice_expired');
      await supabase.auth.signOut();
    };
    const reset = () => {
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
  }, [status]);

  const signIn = useCallback(async (email: string, password: string) => {
    setNotice(null);
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    if (error) {
      setNotice('login.error_credentials');
    }
  }, []);

  const signOut = useCallback(async () => {
    setNotice(null);
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
