-- ==============================================================================
-- Seguidor de tareas (E7) · Migración 4 de 4: Storage de evidencia fotográfica
--
-- Plan: 30_entrega/plan-ciclo-integracion-e7-seguidor-de-tareas.md · Fase 1 (BV-7.14)
--
-- Bucket PRIVADO `task-evidence`. Sin excepción (modelo-de-datos §4, attachment): en un albergue,
-- una foto de evidencia puede identificar a alguien en situación de vulnerabilidad, y una URL
-- pública permanente la deja legible para cualquiera que la reenvíe.
--
--  * Ruta de cada archivo: {organization_id}/{task_id}/{archivo}. Los dos primeros segmentos
--    deciden el acceso; la tabla `task_evidence` exige la misma forma (CHECK).
--  * Lectura y carga: la gestión de tareas, o quien tiene la tarea asignada. Subir sólo mientras
--    la tarea no está cerrada ni archivada.
--  * NO existe política de actualización ni de borrado: nadie sustituye ni elimina una evidencia
--    (regla dura 3). Corregir una foto equivocada es subir otra.
--  * Tipo y tamaño también se limitan en el bucket, no sólo en el navegador.
--  * El cliente firma URLs de 60 s; quien quiera la ruta con auditoría usa
--    public.fn_task_evidence_access (migración 3).
-- ==============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('task-evidence', 'task-evidence', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
    set public = false,
        file_size_limit = 5242880,
        allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

-- Se califican las funciones con `public.` a propósito: las políticas sobre storage.objects no
-- necesariamente evalúan con `public` en el search_path. Y la columna se califica como
-- storage.objects.name: dentro del EXISTS, un `name` a secas se resolvería a task.name
-- (el título de la tarea), y la política jamás coincidiría con la ruta del archivo.
drop policy if exists task_evidence_object_select on storage.objects;
create policy task_evidence_object_select on storage.objects
    for select to authenticated
    using (
        bucket_id = 'task-evidence'
        and (storage.foldername(storage.objects.name))[1] = public.current_organization_id()::text
        and public.has_task_role()
        and (
            public.has_task_management()
            or exists (
                select 1 from public.task t
                where t.id::text = (storage.foldername(storage.objects.name))[2]
                  and t.assigned_to = auth.uid()
            )
        )
    );

drop policy if exists task_evidence_object_insert on storage.objects;
create policy task_evidence_object_insert on storage.objects
    for insert to authenticated
    with check (
        bucket_id = 'task-evidence'
        and (storage.foldername(storage.objects.name))[1] = public.current_organization_id()::text
        and public.has_task_role()
        and (
            public.has_task_management()
            or exists (
                select 1 from public.task t
                where t.id::text = (storage.foldername(storage.objects.name))[2]
                  and t.assigned_to = auth.uid()
                  and t.status <> 'done'
                  and t.archived_at is null
            )
        )
    );
