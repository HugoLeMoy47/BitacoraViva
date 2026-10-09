-- ==============================================================================
-- Seguidor de tareas (E7) · Migración 3 de 4: funciones del pool, rutinas, ajustes y evidencia
--
-- Plan: 30_entrega/plan-ciclo-integracion-e7-seguidor-de-tareas.md · Fase 1 (BV-7.4, BV-7.13, BV-7.15)
--
-- Toda función `security definer` se salta RLS, así que cada una repite la regla de acceso:
-- (1) sesión, (2) acceso a tareas, (3) la propia organización. Ninguna es ejecutable por `anon`.
--
-- Diferencias deliberadas respecto del tracker
--  * Todo está acotado a la organización de quien llama. La devolución automática del tracker
--    era global; en un producto multi-organización eso sería escribir en datos ajenos.
--  * La devolución de lo vencido no necesita `pg_cron`: corre cuando alguien abre el pool, que
--    es quien se beneficia de que lo abandonado ya esté libre (promesa que no depende de una
--    extensión que puede no estar habilitada).
--  * Cada acceso a una evidencia deja evento de auditoría (BV-7.15). Límite honesto: el
--    contenido lo firma el cliente contra Storage, así que la base no puede IMPEDIR que se
--    firme una URL sin pasar por aquí; sí asegura que la vía normal queda registrada y que
--    el bucket es privado (migración 4). Es la misma limitación de D-12 (auditoría de lecturas).
-- ==============================================================================

-- ---------------------------------------------------------------- 1. Nueva acción de auditoría
alter table public.audit_event drop constraint if exists audit_event_action_check;
alter table public.audit_event add constraint audit_event_action_check check (action in (
    'INSERT', 'UPDATE', 'DELETE', 'LOGIN', 'EXPORT', 'STATUS_CHANGE',
    'CLARIFICATION', 'SHARE', 'ACKNOWLEDGE',
    'RECTIFICATION', 'ANONYMIZATION', 'OPPOSITION',
    'CONSENT_GRANTED', 'CONSENT_REVOKED', 'ARCO_ACCESS_EXTRACT_ISSUED',
    'EVIDENCE_ACCESS'
));

-- ---------------------------------------------------------------- 2. Devolver al pool lo vencido
-- Devuelve cuántas tareas liberó. Sólo lo TOMADO por la persona (claimed_at no nulo): una tarea
-- que coordinación asignó nunca se desasigna sola, sería deshacer una decisión ajena.
create or replace function public.fn_release_expired_claims()
returns int
security definer
set search_path = public
language plpgsql as $$
declare
    v_org uuid := public.current_organization_id();
    v_days int;
    v_released int;
begin
    if auth.uid() is null or not public.has_task_role() then
        raise exception 'Acceso denegado: se requiere una sesión con acceso a tareas.' using errcode = 'TK010';
    end if;

    select pool_release_days into v_days from public.task_setting where organization_id = v_org;
    if coalesce(v_days, 1) <= 0 then
        return 0;
    end if;

    update public.task
       set assigned_to = null, claimed_at = null
     where organization_id = v_org
       and archived_at is null
       and status = 'pending'
       and assigned_to is not null
       and claimed_at is not null
       and claimed_at < now() - make_interval(days => coalesce(v_days, 1));

    get diagnostics v_released = row_count;
    return v_released;
end;
$$;

-- ---------------------------------------------------------------- 3. Tomar una tarea del pool
-- Atómico: el bloqueo de fila impide que dos personas tomen la misma.
create or replace function public.fn_claim_open_task(p_task_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql as $$
declare
    v_uid uuid := auth.uid();
    v_org uuid := public.current_organization_id();
    v_max int;
    v_unstarted int;
    v_task public.task%rowtype;
begin
    if v_uid is null or not public.has_task_role() then
        raise exception 'Acceso denegado: se requiere una sesión con acceso a tareas.' using errcode = 'TK010';
    end if;

    -- Antes de nada, lo abandonado vuelve al pool
    perform public.fn_release_expired_claims();

    -- El tope cuenta SÓLO lo que la persona tomó por su cuenta y no ha empezado. Contar también lo
    -- que le asignó coordinación la castigaría por una decisión que no es suya.
    select pool_max_unstarted into v_max from public.task_setting where organization_id = v_org;
    if coalesce(v_max, 0) > 0 then
        select count(*) into v_unstarted
        from public.task
        where assigned_to = v_uid and status = 'pending' and claimed_at is not null and archived_at is null;
        if v_unstarted >= v_max then
            raise exception 'Ya tienes % tarea(s) tomadas sin empezar. Empieza o suelta alguna antes de tomar otra.', v_unstarted
                using errcode = 'TK014';
        end if;
    end if;

    select * into v_task
    from public.task
    where id = p_task_id and organization_id = v_org and archived_at is null
    for update;

    if not found then
        raise exception 'La tarea no existe.' using errcode = 'TK011';
    end if;
    if v_task.assigned_to is not null then
        raise exception 'Esta tarea ya fue tomada por otra persona.' using errcode = 'TK012';
    end if;
    if v_task.status <> 'pending' then
        raise exception 'Sólo se pueden tomar tareas pendientes.' using errcode = 'TK013';
    end if;

    update public.task
       set assigned_to = v_uid, claimed_at = now()
     where id = p_task_id
    returning * into v_task;

    return to_jsonb(v_task);
end;
$$;

-- ---------------------------------------------------------------- 4. Soltar una tarea tomada
-- El inverso de tomar. En un teléfono, con una mano, el pulgar se equivoca. Lo que NO se puede
-- soltar es lo que coordinación asignó: eso es devolver trabajo que alguien te dio, y esa
-- conversación es con esa persona.
create or replace function public.fn_release_task(p_task_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql as $$
declare
    v_uid uuid := auth.uid();
    v_org uuid := public.current_organization_id();
    v_task public.task%rowtype;
begin
    if v_uid is null or not public.has_task_role() then
        raise exception 'Acceso denegado: se requiere una sesión con acceso a tareas.' using errcode = 'TK010';
    end if;

    select * into v_task
    from public.task
    where id = p_task_id and organization_id = v_org and archived_at is null
    for update;

    if not found then
        raise exception 'La tarea no existe.' using errcode = 'TK011';
    end if;
    if v_task.assigned_to is distinct from v_uid then
        raise exception 'Esta tarea no es tuya.' using errcode = 'TK017';
    end if;
    if v_task.status <> 'pending' then
        raise exception 'Ya empezaste esta tarea. Habla con quien coordina si necesitas soltarla.' using errcode = 'TK018';
    end if;
    if v_task.claimed_at is null then
        raise exception 'Esta tarea te la asignó quien coordina. Pídele a esa persona que la reasigne.' using errcode = 'TK019';
    end if;

    update public.task
       set assigned_to = null, claimed_at = null
     where id = p_task_id
    returning * into v_task;

    return to_jsonb(v_task);
end;
$$;

-- ---------------------------------------------------------------- 5. Iniciar una rutina
-- Una vez por plantilla y por día. El botón del modal ya evita el doble toque, pero la base es
-- la autoridad: un reintento de red o dos aparatos abiertos bastaban para duplicar la jornada.
-- «Día» es la fecha del servidor; cuando exista zona horaria por organización se usará esa.
create or replace function public.fn_start_routine(p_template_id uuid)
returns jsonb
security definer
set search_path = public
language plpgsql as $$
declare
    v_uid uuid := auth.uid();
    v_org uuid := public.current_organization_id();
    v_template public.routine_template%rowtype;
    v_item record;
    v_count int := 0;
begin
    if v_uid is null or not public.has_task_role() then
        raise exception 'Acceso denegado: se requiere una sesión con acceso a tareas.' using errcode = 'TK010';
    end if;

    select * into v_template
    from public.routine_template
    where id = p_template_id and organization_id = v_org and archived_at is null;

    if not found then
        raise exception 'La rutina no existe o está archivada.' using errcode = 'TK021';
    end if;

    if exists (
        select 1 from public.task
        where assigned_to = v_uid
          and routine_template_id = p_template_id
          and archived_at is null
          and created_at >= current_date
    ) then
        raise exception 'Ya iniciaste esta rutina hoy. Tus tareas están en el tablero.' using errcode = 'TK022';
    end if;

    for v_item in
        select * from public.routine_template_item
        where routine_template_id = p_template_id and organization_id = v_org and archived_at is null
        order by sort_order asc, name asc
    loop
        insert into public.task (
            organization_id, name, details, photo_required, work_area_id, task_category_id,
            assigned_to, status, due_at, routine_template_id
        ) values (
            v_org, v_item.name, v_item.details, v_item.photo_required,
            coalesce(v_item.work_area_id, v_template.work_area_id),
            coalesce(v_item.task_category_id, v_template.task_category_id),
            v_uid, 'pending', current_date, p_template_id
        );
        v_count := v_count + 1;
    end loop;

    if v_count = 0 then
        raise exception 'La rutina no tiene tareas.' using errcode = 'TK024';
    end if;

    return jsonb_build_object('routine', v_template.name, 'tasks_created', v_count);
end;
$$;

-- ---------------------------------------------------------------- 6. Ajustes de operación
-- Sólo el director. Cada cambio queda en auditoría por el disparador de task_setting.
create or replace function public.fn_update_task_setting(
    p_shift_note_scope text,
    p_shift_note_days int,
    p_pool_max_unstarted int,
    p_pool_release_days int
)
returns uuid
security definer
set search_path = public
language plpgsql as $$
declare
    v_org uuid := public.current_organization_id();
    v_id uuid;
begin
    if auth.uid() is null or not public.is_active_user() or not public.has_role('director') then
        raise exception 'Acceso denegado: sólo la dirección cambia los ajustes de operación.' using errcode = 'TK010';
    end if;
    if p_shift_note_scope not in ('all', 'area', 'own') then
        raise exception 'El alcance de las notas de turno debe ser all, area u own.' using errcode = 'TK024';
    end if;
    if p_shift_note_days is null or p_shift_note_days < 0 or p_shift_note_days > 3650 then
        raise exception 'Los días visibles de las notas deben estar entre 0 y 3650.' using errcode = 'TK024';
    end if;
    if p_pool_max_unstarted is null or p_pool_max_unstarted < 0 or p_pool_max_unstarted > 100 then
        raise exception 'El tope del pool debe estar entre 0 y 100.' using errcode = 'TK024';
    end if;
    if p_pool_release_days is null or p_pool_release_days < 0 or p_pool_release_days > 365 then
        raise exception 'Los días para devolver al pool deben estar entre 0 y 365.' using errcode = 'TK024';
    end if;

    update public.task_setting
       set shift_note_scope = p_shift_note_scope,
           shift_note_days = p_shift_note_days,
           pool_max_unstarted = p_pool_max_unstarted,
           pool_release_days = p_pool_release_days
     where organization_id = v_org
    returning id into v_id;

    if v_id is null then
        raise exception 'La organización no tiene ajustes de operación.' using errcode = 'TK024';
    end if;
    return v_id;
end;
$$;

-- ---------------------------------------------------------------- 7. Acceso a una evidencia
-- Devuelve la RUTA del archivo (nunca una URL) y deja evento de auditoría. El cliente firma la
-- URL (60 s) contra el bucket privado con esa ruta.
create or replace function public.fn_task_evidence_access(p_evidence_id uuid)
returns text
security definer
set search_path = public
language plpgsql as $$
declare
    v_uid uuid := auth.uid();
    v_org uuid := public.current_organization_id();
    v_ev public.task_evidence%rowtype;
begin
    if v_uid is null or not public.has_task_role() then
        raise exception 'Acceso denegado: se requiere una sesión con acceso a tareas.' using errcode = 'TK010';
    end if;

    select * into v_ev from public.task_evidence
    where id = p_evidence_id and organization_id = v_org and archived_at is null;
    if not found then
        raise exception 'La evidencia no existe.' using errcode = 'TK011';
    end if;

    if not (public.has_task_management() or exists (
        select 1 from public.task t where t.id = v_ev.task_id and t.assigned_to = v_uid
    )) then
        raise exception 'Acceso denegado: sólo la gestión o quien tiene la tarea ve su evidencia.' using errcode = 'TK010';
    end if;

    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_org, v_uid, 'EVIDENCE_ACCESS', 'task_evidence', v_ev.id, jsonb_build_object('task_id', v_ev.task_id));

    return v_ev.storage_path;
end;
$$;

-- ---------------------------------------------------------------- 8. Permisos de ejecución
revoke execute on function public.fn_release_expired_claims() from public, anon;
revoke execute on function public.fn_claim_open_task(uuid) from public, anon;
revoke execute on function public.fn_release_task(uuid) from public, anon;
revoke execute on function public.fn_start_routine(uuid) from public, anon;
revoke execute on function public.fn_update_task_setting(text, int, int, int) from public, anon;
revoke execute on function public.fn_task_evidence_access(uuid) from public, anon;
grant execute on function public.fn_release_expired_claims() to authenticated;
grant execute on function public.fn_claim_open_task(uuid) to authenticated;
grant execute on function public.fn_release_task(uuid) to authenticated;
grant execute on function public.fn_start_routine(uuid) to authenticated;
grant execute on function public.fn_update_task_setting(text, int, int, int) to authenticated;
grant execute on function public.fn_task_evidence_access(uuid) to authenticated;
