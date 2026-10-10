-- ==============================================================================
-- Seguidor de tareas (E7) · Migración 7: vínculo tarea–caso (BV-7.16)
--
-- Plan: 30_entrega/plan-ciclo-integracion-e7-seguidor-de-tareas.md · Fase 6, decisión 6a
--
-- El voluntariado no tiene acceso a expedientes, pero a veces una tarea nace de un caso
-- («acompañar a una familia a un trámite»). El vínculo entrega EXACTAMENTE un dato del caso: el folio
-- (`case_number`), copiado a la tarea. La tabla `case` y la tabla `person` siguen sin ser legibles para
-- quien sólo tiene rol de tareas.
--
-- Decisión 6a (Product Owner, 09 oct 2026): una tarea vinculada NO lleva texto libre. «Cita médica» más un
-- folio ya cuenta algo del caso aunque no haya nombre (D-14, D-18). Su nombre sale de un catálogo neutro
-- (`case_task_kind`: acompañamiento, trámite, seguimiento…) que administra la dirección, y no tiene detalle.
--
--  * Quién vincula: quien opera expedientes (director, caseworker, intake_officer; NO viewer) y SÓLO por
--    las funciones de esta migración. La coordinación de tareas no vincula, aunque edite tareas.
--  * Las columnas de vínculo no se escriben a mano: un disparador rechaza el cambio hecho desde la
--    aplicación (rol authenticated) y lo acepta cuando viene de las funciones, que corren con el rol
--    propietario. No hay variable de sesión que falsificar.
--  * Una tarea vinculada nunca está en el pool y no se puede tomar de él: la asigna la coordinación.
--  * Toda vinculación y desvinculación es un UPDATE de `task`, que ya genera audit_event con el
--    valor anterior y el nuevo de `case_id`.
--  * El folio queda copiado en la tarea: sobrevive a la anonimización de la persona.
--
-- Códigos nuevos: TK025 dato de una tarea vinculada que no se edita a mano
--                 TK026 sin permiso para vincular tareas a casos
--                 TK027 el caso o el tipo de tarea no existe (o está archivado)
--                 TK028 una tarea vinculada a un caso no se toma del pool
-- ==============================================================================

-- ---------------------------------------------------------------- 1. Catálogo neutro
create table if not exists public.case_task_kind (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    key text not null check (key ~ '^[a-z][a-z0-9_]{1,39}$'),
    label_es text not null check (length(btrim(label_es)) between 1 and 120),
    sort_order int not null default 0,
    created_at timestamptz not null default now(),
    created_by uuid references public.user_profile(id),
    updated_at timestamptz not null default now(),
    updated_by uuid references public.user_profile(id),
    archived_at timestamptz,
    archived_by uuid references public.user_profile(id),
    unique (organization_id, key),
    unique (id, organization_id)
);

-- ---------------------------------------------------------------- 2. Columnas de la tarea
alter table public.task
    add column if not exists case_id uuid references public."case"(id),
    add column if not exists case_number text,
    add column if not exists case_task_kind_id uuid;

alter table public.task drop constraint if exists task_case_task_kind_fk;
alter table public.task add constraint task_case_task_kind_fk
    foreign key (case_task_kind_id, organization_id) references public.case_task_kind (id, organization_id);

-- Coherencia: o no hay vínculo, o hay caso, folio y tipo, y no hay texto libre
alter table public.task drop constraint if exists task_case_link_check;
alter table public.task add constraint task_case_link_check check (
    (case_id is null and case_number is null and case_task_kind_id is null)
    or (case_id is not null and case_number is not null and case_task_kind_id is not null and details is null)
);

create index if not exists idx_task_case on public.task (case_id) where case_id is not null;

-- ---------------------------------------------------------------- 3. Disparador de vínculo
-- SIN security definer a propósito: current_user es quien ejecuta la sentencia. Desde la aplicación es
-- `authenticated` (o `anon`); dentro de las funciones de abajo es el propietario.
create or replace function public.fn_task_case_guard()
returns trigger
language plpgsql as $$
declare
    v_app boolean := current_user in ('authenticated', 'anon');
    v_link boolean := false;
begin
    if v_app then
        -- Cada escritura desde la aplicación limpia la marca: no se puede heredar de otra sentencia
        perform set_config('bv.task_case_link_row', '', true);
        if tg_op = 'INSERT' then
            if new.case_id is not null or new.case_number is not null or new.case_task_kind_id is not null then
                raise exception 'El vínculo con un caso lo hace quien opera expedientes, desde el caso.' using errcode = 'TK025';
            end if;
        else
            if new.case_id is distinct from old.case_id
               or new.case_number is distinct from old.case_number
               or new.case_task_kind_id is distinct from old.case_task_kind_id then
                raise exception 'El vínculo con un caso lo hace quien opera expedientes, desde el caso.' using errcode = 'TK025';
            end if;
            -- Una tarea vinculada no tiene texto libre que editar
            if old.case_id is not null
               and (new.name is distinct from old.name or new.details is distinct from old.details) then
                raise exception 'El nombre de una tarea vinculada a un caso sale de un catálogo y no se edita.' using errcode = 'TK025';
            end if;
            -- Y no se toma del pool: la asigna la coordinación
            if old.case_id is not null and old.assigned_to is null and new.assigned_to is not null
               and auth.uid() is not null and not public.has_task_management() then
                raise exception 'Una tarea ligada a un caso no se toma del pool: la asigna quien coordina.' using errcode = 'TK028';
            end if;
        end if;
    end if;

    -- Desde las funciones de vínculo, la guarda de la tarea no aplica el nivel de asignado: quien vincula
    -- opera expedientes y no tiene por qué ser gestión de tareas. La marca vale sólo para ESTA fila.
    if not v_app then
        v_link := (tg_op = 'INSERT' and new.case_id is not null)
               or (tg_op = 'UPDATE' and (new.case_id is distinct from old.case_id
                                         or new.case_task_kind_id is distinct from old.case_task_kind_id));
        perform set_config('bv.task_case_link_row', case when v_link then new.id::text else '' end, true);
    end if;

    -- Derivados: el folio y el nombre salen del caso y del tipo, nunca de quien escribe
    if new.case_id is not null
       and (tg_op = 'INSERT'
            or new.case_id is distinct from old.case_id
            or new.case_task_kind_id is distinct from old.case_task_kind_id) then
        select c.case_number into new.case_number
        from public."case" c
        where c.id = new.case_id and c.organization_id = new.organization_id;
        if not found then
            raise exception 'El caso no existe en esta organización.' using errcode = 'TK027';
        end if;
        select k.label_es into new.name
        from public.case_task_kind k
        where k.id = new.case_task_kind_id and k.organization_id = new.organization_id and k.archived_at is null;
        if not found then
            raise exception 'El tipo de tarea no existe o está archivado.' using errcode = 'TK027';
        end if;
        new.details := null;
    elsif new.case_id is null then
        new.case_number := null;
        new.case_task_kind_id := null;
    end if;

    return new;
end;
$$;

drop trigger if exists trg_task_15_case_guard on public.task;
create trigger trg_task_15_case_guard before insert or update on public.task
for each row execute function public.fn_task_case_guard();

-- La guarda de la tarea (migración 2) con un único cambio: el atajo de vínculo marcado arriba
create or replace function public.fn_task_guard()
returns trigger
security definer
set search_path = public
language plpgsql as $$
declare
    v_uid uuid := auth.uid();
    v_pool_move boolean;
    v_expired boolean;
    v_release_days int;
begin
    -- Sólo se asigna a personas con acceso a tareas (no a un viewer ni a una cuenta desactivada)
    if new.assigned_to is not null
       and (tg_op = 'INSERT' or new.assigned_to is distinct from old.assigned_to)
       and not public.user_has_task_role(new.assigned_to) then
        raise exception 'Sólo se asignan tareas a personas activas con acceso a tareas.' using errcode = 'TK007';
    end if;

    if tg_op = 'INSERT' then
        return new;
    end if;

    -- Mantenimiento (sin sesión) y gestión: sin las restricciones del nivel de asignado
    if v_uid is null or public.has_task_management() then
        return new;
    end if;

    -- Vínculo con un caso (migración 7): lo marcó el disparador trg_task_15_case_guard, que sólo lo hace
    -- cuando la escritura viene de fn_create_case_task / fn_set_task_case, y para esta misma fila
    if current_setting('bv.task_case_link_row', true) = new.id::text then
        return new;
    end if;

    -- Nivel de asignado. Dos transiciones de asignación son legítimas, y se escriben como lo
    -- que son —lo que se hace, no por dónde llegó la escritura—:
    --  * tomar del pool (de nadie a mí) y soltar (de mí a nadie), siempre en pendiente;
    --  * la devolución de lo tomado y vencido, que corre cuando alguien abre el pool.
    v_pool_move := (
            (old.assigned_to is null and new.assigned_to = v_uid)
         or (old.assigned_to = v_uid and new.assigned_to is null)
        ) and old.status = 'pending' and new.status = 'pending';

    select pool_release_days into v_release_days
    from public.task_setting where organization_id = old.organization_id;
    v_expired := coalesce(v_release_days, 1) > 0
        and old.assigned_to is not null
        and old.claimed_at is not null
        and old.status = 'pending' and new.status = 'pending'
        and new.assigned_to is null and new.claimed_at is null
        and old.claimed_at < now() - make_interval(days => coalesce(v_release_days, 1));

    if new.name is distinct from old.name
       or new.details is distinct from old.details
       or new.photo_required is distinct from old.photo_required
       or new.task_category_id is distinct from old.task_category_id
       or new.work_area_id is distinct from old.work_area_id
       or new.routine_template_id is distinct from old.routine_template_id
       or new.due_at is distinct from old.due_at
       or new.archived_at is distinct from old.archived_at
       or (not (v_pool_move or v_expired)
           and (new.assigned_to is distinct from old.assigned_to
                or new.claimed_at is distinct from old.claimed_at))
    then
        raise exception 'Sólo puedes cambiar el estado de la tarea y subir su evidencia.' using errcode = 'TK001';
    end if;

    -- El estado sólo avanza: pendiente -> en curso -> hecho. Reabrir es de coordinación.
    if (case new.status when 'pending' then 0 when 'in_progress' then 1 else 2 end)
     < (case old.status when 'pending' then 0 when 'in_progress' then 1 else 2 end) then
        raise exception 'Una tarea sólo avanza; reabrirla le corresponde a quien coordina.' using errcode = 'TK002';
    end if;

    -- Sin evidencia no hay cierre cuando la tarea la exige
    if new.status = 'done' and old.status <> 'done' and new.photo_required
       and not exists (
            select 1 from public.task_evidence e
            where e.task_id = new.id and e.archived_at is null
       ) then
        raise exception 'Esta tarea requiere una foto de evidencia para cerrarse.' using errcode = 'TK003';
    end if;

    return new;
end;
$$;

-- ---------------------------------------------------------------- 4. Funciones
create or replace function public.fn_create_case_task(
    p_case_id uuid,
    p_kind_id uuid,
    p_assigned_to uuid default null,
    p_due_at date default null,
    p_work_area_id uuid default null
)
returns uuid
security definer
set search_path = public
language plpgsql as $$
declare
    v_uid uuid := auth.uid();
    v_org uuid := public.current_organization_id();
    v_id uuid;
begin
    if v_uid is null or not public.has_operational_role() then
        raise exception 'Sólo quien opera expedientes vincula tareas a un caso.' using errcode = 'TK026';
    end if;
    if not exists (select 1 from public."case" where id = p_case_id and organization_id = v_org) then
        raise exception 'El caso no existe en esta organización.' using errcode = 'TK027';
    end if;

    -- El nombre y el folio los pone el disparador a partir del caso y del tipo
    insert into public.task (organization_id, name, case_id, case_task_kind_id, assigned_to, due_at, work_area_id)
    values (v_org, 'pendiente', p_case_id, p_kind_id, p_assigned_to, p_due_at, p_work_area_id)
    returning id into v_id;
    return v_id;
end;
$$;

create or replace function public.fn_set_task_case(
    p_task_id uuid,
    p_case_id uuid,
    p_kind_id uuid default null
)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_uid uuid := auth.uid();
    v_org uuid := public.current_organization_id();
begin
    if v_uid is null or not public.has_operational_role() then
        raise exception 'Sólo quien opera expedientes vincula tareas a un caso.' using errcode = 'TK026';
    end if;
    if not exists (select 1 from public.task where id = p_task_id and organization_id = v_org and archived_at is null) then
        raise exception 'La tarea no existe.' using errcode = 'TK011';
    end if;

    if p_case_id is null then
        -- Desvincular: el disparador limpia folio y tipo; el nombre se queda como estaba
        update public.task set case_id = null where id = p_task_id;
        return;
    end if;

    if p_kind_id is null then
        raise exception 'Falta el tipo de tarea.' using errcode = 'TK027';
    end if;
    if not exists (select 1 from public."case" where id = p_case_id and organization_id = v_org) then
        raise exception 'El caso no existe en esta organización.' using errcode = 'TK027';
    end if;
    update public.task set case_id = p_case_id, case_task_kind_id = p_kind_id where id = p_task_id;
end;
$$;

revoke execute on function public.fn_create_case_task(uuid, uuid, uuid, date, uuid) from public, anon;
revoke execute on function public.fn_set_task_case(uuid, uuid, uuid) from public, anon;
grant execute on function public.fn_create_case_task(uuid, uuid, uuid, date, uuid) to authenticated;
grant execute on function public.fn_set_task_case(uuid, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------- 5. El pool no incluye lo vinculado
drop policy if exists task_select_pool on public.task;
create policy task_select_pool on public.task for select to authenticated
    using (assigned_to is null and status = 'pending' and archived_at is null and case_id is null);

-- Quien opera expedientes ve las tareas ligadas (para listar las del caso que ya ve). El voluntariado y la
-- coordinación siguen con sus políticas: lo suyo y, para la coordinación, todo.
drop policy if exists task_select_case_linked on public.task;
create policy task_select_case_linked on public.task for select to authenticated
    using (case_id is not null and archived_at is null and public.has_operational_role());

-- ---------------------------------------------------------------- 6. Catálogo: sellos, auditoría, privilegios y RLS
drop trigger if exists trg_task_10_stamp on public.case_task_kind;
create trigger trg_task_10_stamp before insert or update on public.case_task_kind
for each row execute function public.fn_task_stamp();

drop trigger if exists trg_audit_case_task_kind on public.case_task_kind;
create trigger trg_audit_case_task_kind after insert or update on public.case_task_kind
for each row execute function public.fn_audit_trigger();

alter table public.case_task_kind enable row level security;
revoke all on public.case_task_kind from anon;
revoke all on public.case_task_kind from authenticated;
grant select, insert, update on public.case_task_kind to authenticated;

drop policy if exists tenant_task_access on public.case_task_kind;
create policy tenant_task_access on public.case_task_kind as restrictive for all to authenticated
    using (organization_id = public.current_organization_id() and public.has_task_role())
    with check (organization_id = public.current_organization_id() and public.has_task_role());

drop policy if exists case_task_kind_select on public.case_task_kind;
create policy case_task_kind_select on public.case_task_kind for select to authenticated
    using (archived_at is null or public.has_task_management());
drop policy if exists case_task_kind_insert on public.case_task_kind;
create policy case_task_kind_insert on public.case_task_kind for insert to authenticated
    with check (public.has_role('director'));
drop policy if exists case_task_kind_update on public.case_task_kind;
create policy case_task_kind_update on public.case_task_kind for update to authenticated
    using (public.has_role('director')) with check (public.has_role('director'));
