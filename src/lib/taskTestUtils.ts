import { Task } from '../types/database';

// Fábrica de tareas para las pruebas unitarias. Va en su propio módulo (y no dentro de cada prueba)
// para que todas partan del mismo objeto completo: una prueba que olvida un campo obligatorio no
// debería compilar.
export function makeTask(over: Partial<Task> = {}): Task {
  return {
    id: crypto.randomUUID(),
    organization_id: 'org-a',
    name: 'Tarea',
    details: null,
    status: 'pending',
    photo_required: false,
    assigned_to: null,
    claimed_at: null,
    due_at: null,
    started_at: null,
    done_at: null,
    task_category_id: null,
    work_area_id: null,
    routine_template_id: null,
    case_id: null,
    case_number: null,
    case_task_kind_id: null,
    created_at: '2026-09-01T10:00:00.000Z',
    created_by: null,
    updated_at: '2026-09-01T10:00:00.000Z',
    archived_at: null,
    ...over,
  };
}
