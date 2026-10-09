import { useCallback, useEffect, useRef, useState } from 'react';
import { supabase } from './supabase';
import { SessionUser } from './session';
import { useToast } from './toast';
import { t } from './i18n';
import {
  CatalogKind,
  EMPTY_TASK_DATA,
  RoutineDraft,
  ShiftNoteInput,
  TaskData,
  TaskInput,
  catalogApi,
  evidenceApi,
  loadTaskData,
  noteApi,
  poolApi,
  routineApi,
  settingApi,
  taskApi,
  taskErrorMessage,
} from './tasks';
import { TaskSetting } from '../types/database';
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
  /** Catálogos (sólo dirección): categorías y áreas de trabajo */
  createCatalogItem: (kind: CatalogKind, label: string, takenKeys: string[]) => Promise<boolean>;
  renameCatalogItem: (kind: CatalogKind, id: string, label: string) => Promise<boolean>;
  archiveCatalogItem: (kind: CatalogKind, id: string) => Promise<boolean>;
  /** Pool de tareas abiertas */
  claim: (id: string) => Promise<boolean>;
  release: (id: string) => Promise<boolean>;
  /** Devuelve al pool lo tomado y vencido; se llama al abrir el pool */
  refreshPool: () => Promise<void>;
  /** Rutinas */
  startRoutine: (id: string) => Promise<boolean>;
  saveRoutine: (draft: RoutineDraft) => Promise<boolean>;
  archiveRoutine: (id: string) => Promise<boolean>;
  /** Notas de turno */
  addNote: (input: ShiftNoteInput) => Promise<boolean>;
  retractNote: (id: string) => Promise<boolean>;
  /** Evidencia fotográfica: subir una foto a una tarea (recarga para que el cierre se habilite) */
  uploadEvidence: (taskId: string, file: File) => Promise<boolean>;
  /** Ajustes de operación (sólo dirección) */
  saveSettings: (s: Pick<TaskSetting, 'shift_note_scope' | 'shift_note_days' | 'pool_max_unstarted' | 'pool_release_days'>) => Promise<boolean>;
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
    createCatalogItem: (kind, label, takenKeys) => act(() => catalogApi.create(kind, orgId, label, takenKeys), 'tasks.catalogs.toast_created'),
    renameCatalogItem: (kind, id, label) => act(() => catalogApi.rename(kind, id, label), 'tasks.catalogs.toast_renamed', id),
    archiveCatalogItem: (kind, id) => act(() => catalogApi.archive(kind, id), 'tasks.catalogs.toast_archived', id),
    claim: (id) => act(() => poolApi.claim(id).then(() => undefined), 'tasks.pool.toast_claimed', id),
    release: (id) => act(() => poolApi.release(id).then(() => undefined), 'tasks.pool.toast_released', id),
    refreshPool: async () => {
      try {
        await poolApi.releaseExpired();
        await reload();
      } catch {
        // Devolver lo vencido es una cortesía al abrir el pool: si falla, el pool se muestra como está
      }
    },
    startRoutine: (id) =>
      act(async () => {
        const r = await routineApi.start(id);
        toast.success(t('tasks.routines.toast_started').replace('{n}', String(r.tasks_created)));
      }, null, id),
    saveRoutine: (draft) => act(() => routineApi.save(orgId, draft, data.routineItems), 'tasks.routines.toast_saved'),
    archiveRoutine: (id) => act(() => routineApi.archive(id), 'tasks.routines.toast_archived', id),
    addNote: (input) => act(() => noteApi.create(orgId, input), 'tasks.notes.toast_created'),
    retractNote: (id) => act(() => noteApi.retract(id), 'tasks.notes.toast_retracted', id),
    uploadEvidence: (taskId, file) => act(() => evidenceApi.upload(orgId, taskId, file), 'tasks.evidence.toast_uploaded', taskId),
    saveSettings: (s) => act(() => settingApi.update(s).then(() => undefined), 'tasks.settings.toast_saved'),
  };
}
