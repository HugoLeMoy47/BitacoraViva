import { useCallback, useEffect, useRef, useState } from 'react';
import { supabase } from './supabase';
import { SessionUser } from './session';
import { useToast } from './toast';
import { t } from './i18n';
import { EMPTY_TASK_DATA, TaskData, TaskInput, loadTaskData, taskApi, taskErrorMessage } from './tasks';
import { TaskStatus } from '../types/database';

// Estado de la pantalla de tareas: carga, tiempo real y escrituras con aviso de resultado.
//  · Tiempo real: cambios de otras personas llegan por Supabase Realtime (que respeta RLS).
//  · Respaldo: si el canal no está disponible, se relee cada minuto y al volver a la pestaña.
//  · Cada acción muestra su resultado y, si falla, explica el siguiente paso.

const FALLBACK_REFRESH_MS = 60_000;
const REALTIME_DEBOUNCE_MS = 400;

export type TaskLoadState = 'loading' | 'ready' | 'error';

export interface UseTasks {
  data: TaskData;
  state: TaskLoadState;
  /** id de la tarea con una escritura en curso (para deshabilitar sus botones) */
  busyId: string | null;
  /** Hay una alta o edición en curso */
  saving: boolean;
  reload: () => Promise<void>;
  create: (input: TaskInput) => Promise<boolean>;
  update: (id: string, input: TaskInput) => Promise<boolean>;
  setStatus: (id: string, status: TaskStatus, successKey?: string) => Promise<boolean>;
  archive: (id: string) => Promise<boolean>;
}

export function useTasks(user: SessionUser): UseTasks {
  const toast = useToast();
  const [data, setData] = useState<TaskData>(EMPTY_TASK_DATA);
  const [state, setState] = useState<TaskLoadState>('loading');
  const [busyId, setBusyId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const orgId = user.profile.organization_id;
  const mounted = useRef(true);

  const reload = useCallback(async () => {
    try {
      const fresh = await loadTaskData();
      if (!mounted.current) return;
      setData(fresh);
      setState('ready');
    } catch (e) {
      if (!mounted.current) return;
      // Si ya había datos en pantalla se conservan: un fallo de red no debe vaciar el tablero
      setState((prev) => (prev === 'ready' ? 'ready' : 'error'));
      toast.error(taskErrorMessage(e));
    }
  }, [toast]);

  useEffect(() => {
    mounted.current = true;
    reload();

    let timer: ReturnType<typeof setTimeout> | null = null;
    const soon = () => {
      if (timer) clearTimeout(timer);
      timer = setTimeout(reload, REALTIME_DEBOUNCE_MS);
    };

    const channel = supabase
      .channel(`task-changes-${orgId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'task', filter: `organization_id=eq.${orgId}` }, soon)
      .subscribe();

    const interval = setInterval(reload, FALLBACK_REFRESH_MS);
    const onVisible = () => {
      if (document.visibilityState === 'visible') reload();
    };
    document.addEventListener('visibilitychange', onVisible);

    return () => {
      mounted.current = false;
      if (timer) clearTimeout(timer);
      clearInterval(interval);
      document.removeEventListener('visibilitychange', onVisible);
      supabase.removeChannel(channel);
    };
  }, [orgId, reload]);

  const act = useCallback(
    async (work: () => Promise<void>, successKey: string | null, id?: string): Promise<boolean> => {
      if (id) setBusyId(id);
      else setSaving(true);
      let ok = false;
      try {
        await work();
        ok = true;
        if (successKey) toast.success(t(successKey));
      } catch (e) {
        toast.error(taskErrorMessage(e));
      }
      await reload();
      if (mounted.current) {
        setBusyId(null);
        setSaving(false);
      }
      return ok;
    },
    [reload, toast]
  );

  return {
    data,
    state,
    busyId,
    saving,
    reload,
    create: (input) => act(() => taskApi.create(orgId, input), 'tasks.toast_created'),
    update: (id, input) => act(() => taskApi.update(id, input), 'tasks.toast_updated'),
    setStatus: (id, status, successKey) => act(() => taskApi.setStatus(id, status), successKey ?? null, id),
    archive: (id) => act(() => taskApi.archive(id), 'tasks.toast_archived', id),
  };
}
