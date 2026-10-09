import React, { useMemo, useState } from 'react';
import { ListChecks, PlayCircle, Plus } from 'lucide-react';
import { t } from '../lib/i18n';
import { SessionUser } from '../lib/session';
import { useCatalog } from '../lib/catalog';
import { useToast } from '../lib/toast';
import { navigate } from '../lib/router';
import { canManageTasks } from '../lib/navigation';
import { useTasks } from '../lib/useTasks';
import { usePhoneScreen } from '../lib/usePhoneScreen';
import { TaskInput } from '../lib/tasks';
import { Advance, canMove, groupByStatus, progressOf } from '../lib/taskFlow';
import { Task, TaskStatus } from '../types/database';
import { TaskBoard } from './TaskBoard';
import { TaskCard } from './TaskCard';
import { TaskMobileList } from './TaskMobileList';
import { TaskFormModal } from './TaskFormModal';
import { TaskArchiveModal } from './TaskArchiveModal';
import { TaskReportsView } from './TaskReportsView';
import { TaskCatalogsView } from './TaskCatalogsView';
import { PoolPanel } from './PoolPanel';
import { StartRoutineModal } from './StartRoutineModal';
import { RoutinesView } from './RoutinesView';
import { ShiftNotesView } from './ShiftNotesView';
import { TaskSettingsView } from './TaskSettingsView';
import { Tabs } from './Tabs';
import { VolunteerProgress } from './VolunteerProgress';
import { VictoryModal } from './VictoryModal';

// Seguidor de tareas (E7). Quien gestiona (dirección y coordinación de tareas) ve y mantiene todas, y
// además tiene Reportes y Rutinas; sólo la dirección administra Catálogos y Ajustes. El resto ve las suyas,
// toma tareas del pool, inicia rutinas y deja notas de turno. Lo que cada
// rol puede hacer lo decide la base de datos (RLS y disparadores): aquí sólo se ofrece lo que la base va
// a aceptar.

const VICTORY_MESSAGES = 6;
type PersonFilter = 'all' | 'unassigned' | string;
type Section = 'board' | 'reports' | 'routines' | 'notes' | 'catalogs' | 'settings';

// Segmento de la ruta (#/tareas/reportes) de cada sección
const SECTION_PARAM: Record<Section, string | null> = {
  board: null,
  reports: 'reportes',
  routines: 'rutinas',
  notes: 'notas',
  catalogs: 'catalogos',
  settings: 'ajustes',
};

interface TasksViewProps {
  user: SessionUser;
  /** Segmento de la ruta tras «tareas»: `reportes`, `catalogos` o nada (tablero) */
  section: string | null;
  /** Cadena de consulta de la ruta (filtros de un reporte compartido) */
  query: string;
}

export const TasksView: React.FC<TasksViewProps> = ({ user, section: sectionParam, query }) => {
  const { userNames, organizationName } = useCatalog();
  const toast = useToast();
  const tasks = useTasks(user);
  const isPhone = usePhoneScreen();
  const isManagement = canManageTasks(user.roles);
  const canCatalogs = user.roles.includes('director');
  const me = user.profile.id;

  // Sólo se llega a una sección que el rol puede usar; si no, el tablero
  const section: Section =
    isManagement && sectionParam === 'reportes' ? 'reports'
    : isManagement && sectionParam === 'rutinas' ? 'routines'
    : sectionParam === 'notas' ? 'notes'
    : canCatalogs && sectionParam === 'catalogos' ? 'catalogs'
    : canCatalogs && sectionParam === 'ajustes' ? 'settings'
    : 'board';

  const [filter, setFilter] = useState<PersonFilter>('all');
  const [mobileStatus, setMobileStatus] = useState<TaskStatus>('pending');
  const [form, setForm] = useState<{ task: Task | null } | null>(null);
  const [archiving, setArchiving] = useState<Task | null>(null);
  const [startingRoutine, setStartingRoutine] = useState(false);
  const [victory, setVictory] = useState<{ taskName: string; message: string; isLast: boolean } | null>(null);

  const { categories, workAreas, evidenceTaskIds, assignableUserIds } = tasks.data;
  const categoryLabel = useMemo(() => new Map(categories.map((c) => [c.id, c.label_es])), [categories]);
  const workAreaLabel = useMemo(() => new Map(workAreas.map((a) => [a.id, a.label_es])), [workAreas]);

  // Tareas vigentes: lo archivado sale del tablero y de los reportes (queda en el historial y la auditoría)
  const live = useMemo(() => tasks.data.tasks.filter((x) => !x.archived_at), [tasks.data.tasks]);

  // El pool: trabajo sin asignar y pendiente que cualquier persona con acceso a tareas puede tomar
  const pool = useMemo(() => live.filter((x) => !x.assigned_to && x.status === 'pending'), [live]);
  const activeRoutines = useMemo(() => tasks.data.routines.filter((r) => !r.archived_at), [tasks.data.routines]);

  // Quien no gestiona ve en su tablero sólo lo suyo; lo sin asignar lo ve en el pool
  const visible = useMemo(
    () =>
      live.filter((task) => {
        if (!isManagement) return task.assigned_to === me;
        if (filter === 'all') return true;
        if (filter === 'unassigned') return !task.assigned_to;
        return task.assigned_to === filter;
      }),
    [live, isManagement, me, filter]
  );
  const groups = useMemo(() => groupByStatus(visible), [visible]);

  const people = useMemo(() => {
    const ids = Array.from(new Set(live.filter((x) => x.assigned_to).map((x) => x.assigned_to as string)));
    return ids.map((id) => ({ id, name: userNames[id] || t('tasks.assignee_former') })).sort((a, b) => a.name.localeCompare(b.name, 'es'));
  }, [live, userNames]);

  const assignees = useMemo(
    () =>
      assignableUserIds
        .map((id) => ({ id, name: userNames[id] || '' }))
        .filter((a) => a.name)
        .sort((a, b) => a.name.localeCompare(b.name, 'es')),
    [assignableUserIds, userNames]
  );

  const celebrate = (task: Task) => {
    const remaining = visible.filter((x) => x.id !== task.id && x.status !== 'done').length;
    const pick = 1 + Math.floor(Math.random() * VICTORY_MESSAGES);
    setVictory({
      taskName: task.name,
      isLast: remaining === 0,
      message: t(`tasks.victory_${pick}`).replace('{organization}', organizationName),
    });
  };

  const handleAdvance = async (task: Task, advance: Advance) => {
    const successKey = advance.to === 'in_progress' ? 'tasks.toast_started' : isManagement ? 'tasks.toast_done' : null;
    const ok = await tasks.setStatus(task.id, advance.to, successKey ?? undefined);
    // El reconocimiento es para quien hace el trabajo; la coordinación recibe sólo el aviso
    if (ok && advance.to === 'done' && !isManagement) celebrate(task);
  };

  const handleClaim = (task: Task) => tasks.claim(task.id);
  const handleRelease = (task: Task) => tasks.release(task.id);

  const handleStartRoutine = async (id: string) => {
    if (await tasks.startRoutine(id)) setStartingRoutine(false);
  };

  const handleReopen = (task: Task) => tasks.setStatus(task.id, 'in_progress', 'tasks.toast_reopened');

  const handleDrop = async (taskId: string, to: TaskStatus) => {
    const task = tasks.data.tasks.find((x) => x.id === taskId);
    if (!task || task.status === to) return;
    if (!task.assigned_to || !canMove(task, to, isManagement)) {
      toast.error(t('tasks.move_not_allowed'));
      return;
    }
    // La exigencia de foto se evalúa contra el DESTINO: arrastrar de pendiente directo a hecha también la requiere
    if (to === 'done' && task.photo_required && !evidenceTaskIds.has(task.id) && !isManagement) {
      toast.error(t('tasks.move_needs_photo'));
      return;
    }
    const successKey = to === 'in_progress' ? (task.status === 'done' ? 'tasks.toast_reopened' : 'tasks.toast_started') : isManagement ? 'tasks.toast_done' : undefined;
    const ok = await tasks.setStatus(task.id, to, successKey);
    if (ok && to === 'done' && !isManagement) celebrate(task);
  };

  const submitForm = async (input: TaskInput) => {
    if (!form) return;
    const ok = form.task ? await tasks.update(form.task.id, input) : await tasks.create(input);
    if (ok) setForm(null);
  };

  const confirmArchive = async () => {
    if (!archiving) return;
    const ok = await tasks.archive(archiving.id);
    if (ok) setArchiving(null);
  };

  const renderCard = (task: Task) => (
    <TaskCard
      key={task.id}
      task={task}
      assigneeName={task.assigned_to ? userNames[task.assigned_to] : undefined}
      categoryLabel={task.task_category_id ? categoryLabel.get(task.task_category_id) : undefined}
      workAreaLabel={task.work_area_id ? workAreaLabel.get(task.work_area_id) : undefined}
      hasEvidence={evidenceTaskIds.has(task.id)}
      isManagement={isManagement}
      busy={tasks.busyId === task.id}
      draggable={!isPhone && !!task.assigned_to}
      onDragStart={(e, dragged) => e.dataTransfer.setData('text/plain', dragged.id)}
      onAdvance={handleAdvance}
      onReopen={handleReopen}
      onEdit={(x) => setForm({ task: x })}
      onArchive={setArchiving}
      onClaim={isManagement ? undefined : handleClaim}
      onRelease={isManagement ? undefined : handleRelease}
    />
  );

  if (tasks.state === 'loading') {
    return <p className="py-10 text-center text-sm text-gray-600">{t('session.loading')}</p>;
  }
  if (tasks.state === 'error') {
    return (
      <div className="mx-auto max-w-md space-y-3 rounded-xl border border-gray-200 bg-white p-6 text-center shadow-sm">
        <p className="text-sm font-semibold text-carbon">{t('tasks.load_error')}</p>
        <button type="button" onClick={() => tasks.reload()} className="min-h-11 rounded-lg bg-carbon px-4 text-sm font-semibold text-white">
          {t('session.retry')}
        </button>
      </div>
    );
  }

  const nothingYet = isManagement && live.length === 0;
  const sectionTabs = [
    { id: 'board', label: t('tasks.tab_board') },
    ...(isManagement ? [{ id: 'reports', label: t('tasks.tab_reports') }, { id: 'routines', label: t('tasks.tab_routines') }] : []),
    { id: 'notes', label: t('tasks.tab_notes') },
    ...(canCatalogs ? [{ id: 'catalogs', label: t('tasks.tab_catalogs') }, { id: 'settings', label: t('tasks.tab_settings') }] : []),
  ];

  return (
    <div className="space-y-4">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h2 className="flex items-center gap-2 text-lg font-bold text-carbon">
            <ListChecks className="h-5 w-5 text-turquesa-dark" aria-hidden="true" />
            {t('tasks.title')}
          </h2>
          <p className="text-sm text-gray-600">{t(isManagement ? 'tasks.subtitle_manager' : 'tasks.subtitle_member')}</p>
        </div>

        {isManagement && section === 'board' && (
          <div className="flex flex-col gap-2 sm:flex-row sm:items-end">
            <label className="block text-xs font-semibold text-gray-700">
              {t('tasks.filter_person')}
              <select
                value={filter}
                onChange={(e) => setFilter(e.target.value)}
                className="mt-1 block min-h-11 w-full rounded-lg border border-gray-300 bg-white px-3 text-sm sm:w-56"
              >
                <option value="all">{t('tasks.filter_all')}</option>
                <option value="unassigned">{t('tasks.unassigned')}</option>
                {people.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                  </option>
                ))}
              </select>
            </label>
            <button
              type="button"
              onClick={() => setForm({ task: null })}
              className="inline-flex min-h-11 items-center justify-center gap-2 rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon hover:bg-turquesa-hover"
            >
              <Plus className="h-4 w-4" aria-hidden="true" />
              {t('tasks.new_task')}
            </button>
          </div>
        )}
      </div>

      {sectionTabs.length > 1 && (
        <Tabs
          ariaLabel={t('tasks.sections')}
          items={sectionTabs}
          value={section}
          onChange={(id) => navigate('tasks', SECTION_PARAM[id as Section])}
          className="flex-wrap"
        />
      )}

      {section === 'reports' && (
        <TaskReportsView
          tasks={live}
          categories={categories}
          workAreas={workAreas}
          userNames={userNames}
          initialQuery={query}
          filePrefix={t('tasks.reports.file_prefix')}
        />
      )}

      {section === 'routines' && (
        <RoutinesView
          routines={tasks.data.routines}
          items={tasks.data.routineItems}
          categories={categories}
          workAreas={workAreas}
          busyId={tasks.busyId}
          saving={tasks.saving}
          onSave={tasks.saveRoutine}
          onArchive={tasks.archiveRoutine}
        />
      )}

      {section === 'notes' && (
        <ShiftNotesView
          notes={tasks.data.notes}
          workAreas={workAreas}
          userNames={userNames}
          setting={tasks.data.setting}
          me={me}
          isManagement={isManagement}
          busyId={tasks.busyId}
          saving={tasks.saving}
          onAdd={tasks.addNote}
          onRetract={tasks.retractNote}
        />
      )}

      {section === 'settings' && <TaskSettingsView setting={tasks.data.setting} saving={tasks.saving} onSave={tasks.saveSettings} />}

      {section === 'catalogs' && (
        <TaskCatalogsView
          categories={categories}
          workAreas={workAreas}
          busyId={tasks.busyId}
          saving={tasks.saving}
          onCreate={tasks.createCatalogItem}
          onRename={tasks.renameCatalogItem}
          onArchive={tasks.archiveCatalogItem}
        />
      )}

      {section === 'board' && (
        <>
          {!isManagement && <VolunteerProgress progress={progressOf(visible)} fullName={user.profile.full_name} organizationName={organizationName} />}

          {!isManagement && (
            <>
              <div className="mb-4">
                <button
                  type="button"
                  onClick={() => {
                    // Las rutinas las crea otra persona: al abrir se relee, para no ofrecer una lista vieja
                    setStartingRoutine(true);
                    tasks.reload();
                  }}
                  className="inline-flex min-h-11 items-center gap-2 rounded-lg border border-turquesa bg-white px-4 text-sm font-semibold text-carbon hover:bg-claro-surface"
                >
                  <PlayCircle className="h-4 w-4 text-turquesa-dark" aria-hidden="true" />
                  {t('tasks.routines.start_button')}
                </button>
              </div>
              <PoolPanel tasks={pool} renderCard={renderCard} onOpen={tasks.refreshPool} />
            </>
          )}

          {nothingYet ? (
            <div className="rounded-xl border border-dashed border-gray-300 bg-white px-4 py-10 text-center">
              <p className="text-sm font-semibold text-carbon">{t('tasks.empty_manager_title')}</p>
              <p className="mx-auto mt-1 max-w-xs text-xs text-gray-600">{t('tasks.empty_manager_body')}</p>
            </div>
          ) : isPhone ? (
            <TaskMobileList groups={groups} active={mobileStatus} onChangeActive={setMobileStatus} renderCard={renderCard} isManagement={isManagement} />
          ) : (
            <TaskBoard groups={groups} renderCard={renderCard} onDropTask={handleDrop} />
          )}
        </>
      )}

      {form && (
        <TaskFormModal
          task={form.task}
          categories={categories}
          workAreas={workAreas}
          assignees={assignees}
          busy={tasks.saving}
          onClose={() => setForm(null)}
          onSubmit={submitForm}
        />
      )}
      {archiving && <TaskArchiveModal task={archiving} busy={tasks.busyId === archiving.id} onClose={() => setArchiving(null)} onConfirm={confirmArchive} />}
      {startingRoutine && <StartRoutineModal routines={activeRoutines} items={tasks.data.routineItems} busyId={tasks.busyId} onStart={handleStartRoutine} onClose={() => setStartingRoutine(false)} />}
      {victory && (
        <VictoryModal
          taskName={victory.taskName}
          message={victory.message}
          isLast={victory.isLast}
          onClose={() => setVictory(null)}
          onLeaveNote={() => navigate('tasks', SECTION_PARAM.notes)}
        />
      )}
    </div>
  );
};
