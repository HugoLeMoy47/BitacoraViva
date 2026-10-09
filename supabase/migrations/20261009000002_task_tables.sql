-- ==============================================================================
-- Seguidor de tareas (E7) · Migración 2 de 4: tablas, RLS, auditoría y baja lógica
--
-- Plan: 30_entrega/plan-ciclo-integracion-e7-seguidor-de-tareas.md · Fase 1 (BV-7.2, BV-7.3)
-- Nombres: 00_gobernanza/glosario.md §4-bis · Entidades: 20_arquitectura/modelo-de-datos.md §5-bis
--
-- Es el ESTADO FINAL del CAFEMIN Task Tracker reescrito con las reglas duras de Bitácora
-- Viva, no una copia de sus 14 migraciones (no hay datos que migrar: la demo es ficticia).
--
-- Lo que cambia respecto del tracker y por qué
--  * `organization_id` en toda tabla, con llave foránea compuesta (id, organization_id):
--    una tarea no puede apuntar a una persona, categoría o plantilla de otra organización.
--  * Regla 3: ninguna tabla admite DELETE. La baja es lógica (`archived_at`) y definitiva.
--  * Regla 5: auditoría por disparador en toda tabla. En `shift_note` el texto se omite
--    del evento (texto libre del turno; el evento prueba que existió, no lo copia).
--  * Regla 1: la seguridad vive aquí. El tracker confiaba parte de ella en el navegador
--    (qué botón se muestra); aquí cada regla es política o disparador.
--
-- Códigos de error (SQLSTATE) de este módulo
--  TK001 el voluntariado sólo avanza el estado de su tarea y sube su evidencia
--  TK002 una tarea no retrocede ni se reabre desde ese nivel
--  TK003 falta evidencia para cerrar una tarea que la exige
--  TK006 no se deja a la organización sin dirección        (migración 1)
--  TK007 sólo se asigna a personas con acceso a tareas
--  TK008 la organización de un registro no cambia
--  TK009 un registro archivado no se modifica ni se restaura
--  TK010 sin sesión o sin acceso a tareas                   (migración 3)
--  TK011 la tarea no existe                                  (migración 3)
--  TK012 la tarea ya fue tomada                              (migración 3)
--  TK013 sólo se toman tareas pendientes                     (migración 3)
--  TK014 tope de tareas tomadas sin empezar                  (migración 3)
--  TK017 la tarea a soltar no es tuya                        (migración 3)
--  TK018 la tarea a soltar ya se empezó                      (migración 3)
--  TK019 la tarea a soltar la asignó coordinación            (migración 3)
--  TK021 la rutina no existe o está archivada                (migración 3)
--  TK022 la rutina ya se inició hoy                          (migración 3)
--  TK023 la evidencia y las notas de turno no se editan
--  TK024 ajuste o dato inválido                              (migración 3)
-- ==============================================================================

-- ---------------------------------------------------------------- 1. Catálogos
create table if not exists public.task_category (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    key text not null check (key ~ '^[a-z][a-z0-9_]{1,39}$'),
    label_es text not null check (length(btrim(label_es)) > 0),
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

-- Espacio físico del inmueble (cocina, dormitorios). NO es `area`, que es funcional.
create table if not exists public.work_area (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    key text not null check (key ~ '^[a-z][a-z0-9_]{1,39}$'),
    label_es text not null check (length(btrim(label_es)) > 0),
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

-- ---------------------------------------------------------------- 2. Plantillas de rutina
create table if not exists public.routine_template (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    name text not null check (length(btrim(name)) between 1 and 120),
    description text check (description is null or length(description) <= 1000),
    work_area_id uuid,
    task_category_id uuid,
    created_at timestamptz not null default now(),
    created_by uuid references public.user_profile(id),
    updated_at timestamptz not null default now(),
    updated_by uuid references public.user_profile(id),
    archived_at timestamptz,
    archived_by uuid references public.user_profile(id),
    unique (id, organization_id),
    foreign key (work_area_id, organization_id) references public.work_area (id, organization_id),
    foreign key (task_category_id, organization_id) references public.task_category (id, organization_id)
);

create table if not exists public.routine_template_item (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    routine_template_id uuid not null,
    name text not null check (length(btrim(name)) between 1 and 120),
    details text check (details is null or length(details) <= 1000),
    sort_order int not null default 0,
    photo_required boolean not null default false,
    work_area_id uuid,
    task_category_id uuid,
    created_at timestamptz not null default now(),
    created_by uuid references public.user_profile(id),
    updated_at timestamptz not null default now(),
    updated_by uuid references public.user_profile(id),
    archived_at timestamptz,
    archived_by uuid references public.user_profile(id),
    foreign key (routine_template_id, organization_id) references public.routine_template (id, organization_id),
    foreign key (work_area_id, organization_id) references public.work_area (id, organization_id),
    foreign key (task_category_id, organization_id) references public.task_category (id, organization_id)
);

-- ---------------------------------------------------------------- 3. La tarea
create table if not exists public.task (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    name text not null check (length(btrim(name)) between 1 and 120),
    details text check (details is null or length(details) <= 1000),
    status text not null default 'pending' check (status in ('pending', 'in_progress', 'done')),
    photo_required boolean not null default false,
    assigned_to uuid,
    -- Cuándo la tomó la persona del pool. Distingue lo tomado de lo que coordinación asignó:
    -- sólo lo tomado se devuelve solo al pool.
    claimed_at timestamptz,
    -- Vencimiento (fecha, sin hora)
    due_at date,
    started_at timestamptz,
    done_at timestamptz,
    task_category_id uuid,
    work_area_id uuid,
    routine_template_id uuid,
    created_at timestamptz not null default now(),
    created_by uuid references public.user_profile(id),
    updated_at timestamptz not null default now(),
    updated_by uuid references public.user_profile(id),
    archived_at timestamptz,
    archived_by uuid references public.user_profile(id),
    unique (id, organization_id),
    check (claimed_at is null or assigned_to is not null),
    foreign key (assigned_to, organization_id) references public.user_profile (id, organization_id),
    foreign key (task_category_id, organization_id) references public.task_category (id, organization_id),
    foreign key (work_area_id, organization_id) references public.work_area (id, organization_id),
    foreign key (routine_template_id, organization_id) references public.routine_template (id, organization_id)
);

create index if not exists idx_task_org_status on public.task (organization_id, status);
create index if not exists idx_task_assignee on public.task (assigned_to, status);
create index if not exists idx_task_pool on public.task (organization_id) where assigned_to is null and status = 'pending';
create index if not exists idx_task_claimed on public.task (assigned_to, status) where claimed_at is not null;
create index if not exists idx_task_routine on public.task (assigned_to, routine_template_id) where routine_template_id is not null;

-- ---------------------------------------------------------------- 4. Evidencia fotográfica
-- Guarda la RUTA en el bucket privado `task-evidence`, nunca una URL. Se agrega y no se
-- edita: lo que acredita una tarea no se sustituye en silencio.
create table if not exists public.task_evidence (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    task_id uuid not null,
    storage_path text not null unique,
    mime_type text not null check (mime_type in ('image/jpeg', 'image/png', 'image/webp')),
    size_bytes int not null check (size_bytes > 0 and size_bytes <= 5242880),
    created_at timestamptz not null default now(),
    created_by uuid references public.user_profile(id),
    updated_at timestamptz not null default now(),
    updated_by uuid references public.user_profile(id),
    archived_at timestamptz,
    archived_by uuid references public.user_profile(id),
    foreign key (task_id, organization_id) references public.task (id, organization_id),
    -- {organización}/{tarea}/{archivo}: el primer y segundo segmento permiten decidir el acceso
    check (storage_path like organization_id::text || '/' || task_id::text || '/%')
);
create index if not exists idx_task_evidence_task on public.task_evidence (task_id);

-- ---------------------------------------------------------------- 5. Notas de turno
-- Recado en texto libre para el turno siguiente. NO es `journal_entry`: no pertenece a un caso.
create table if not exists public.shift_note (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    work_area_id uuid,
    note_date date not null default current_date,
    shift text not null default 'general' check (shift in ('morning', 'afternoon', 'night', 'general')),
    body text not null check (length(btrim(body)) between 1 and 2000),
    created_at timestamptz not null default now(),
    created_by uuid references public.user_profile(id),
    updated_at timestamptz not null default now(),
    updated_by uuid references public.user_profile(id),
    archived_at timestamptz,
    archived_by uuid references public.user_profile(id),
    foreign key (work_area_id, organization_id) references public.work_area (id, organization_id)
);
create index if not exists idx_shift_note_org_date on public.shift_note (organization_id, note_date desc);

-- ---------------------------------------------------------------- 6. Ajustes de operación
-- Decisiones que no tienen una respuesta correcta que el código pueda elegir por la
-- organización. Una fila por organización; sólo el director las cambia, por función.
create table if not exists public.task_setting (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null unique references public.organization(id),
    -- Quién lee las notas de turno: todas | sólo las de su área de trabajo | sólo las propias
    shift_note_scope text not null default 'all' check (shift_note_scope in ('all', 'area', 'own')),
    -- Días hacia atrás visibles. 0 = sin límite
    shift_note_days int not null default 30 check (shift_note_days >= 0),
    -- Máximo de tareas tomadas del pool y sin empezar por persona. 0 = sin tope
    pool_max_unstarted int not null default 0 check (pool_max_unstarted >= 0),
    -- Días tras los cuales lo tomado y no empezado vuelve al pool. 0 = nunca
    pool_release_days int not null default 1 check (pool_release_days >= 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    updated_by uuid references public.user_profile(id)
);

insert into public.task_setting (organization_id)
select id from public.organization
on conflict (organization_id) do nothing;

-- Toda organización nueva nace con sus ajustes por omisión
create or replace function public.fn_task_setting_default_row()
returns trigger
security definer
set search_path = public
language plpgsql as $$
begin
    insert into public.task_setting (organization_id) values (new.id) on conflict (organization_id) do nothing;
    return new;
end;
$$;

drop trigger if exists trg_task_setting_default_row on public.organization;
create trigger trg_task_setting_default_row
after insert on public.organization
for each row execute function public.fn_task_setting_default_row();

-- Lectura de ajustes para las políticas (security definer: se usa DENTRO de políticas de
-- otras tablas y no debe volver a entrar a RLS)
create or replace function public.current_shift_note_scope()
returns text
stable
security definer
set search_path = public
language sql as $$
    select coalesce((select shift_note_scope from public.task_setting
                     where organization_id = public.current_organization_id()), 'all');
$$;

create or replace function public.current_shift_note_days()
returns int
stable
security definer
set search_path = public
language sql as $$
    select coalesce((select shift_note_days from public.task_setting
                     where organization_id = public.current_organization_id()), 30);
$$;

revoke execute on function public.current_shift_note_scope() from public, anon;
revoke execute on function public.current_shift_note_days() from public, anon;
grant execute on function public.current_shift_note_scope() to authenticated;
grant execute on function public.current_shift_note_days() to authenticated;

-- ---------------------------------------------------------------- 7. Disparadores de integridad
-- 7.1 Sello común: autoría, organización inmutable y baja definitiva.
create or replace function public.fn_task_stamp()
returns trigger
language plpgsql as $$
begin
    if tg_op = 'INSERT' then
        new.updated_at := now();
        if auth.uid() is not null then
            -- Con sesión, la autoría no se declara: se sella
            new.created_by := auth.uid();
            new.updated_by := auth.uid();
            new.archived_at := null;
            new.archived_by := null;
        end if;
        return new;
    end if;

    if old.archived_at is not null then
        raise exception 'Un registro archivado no se modifica ni se restaura.' using errcode = 'TK009';
    end if;
    if new.organization_id is distinct from old.organization_id then
        raise exception 'La organización de un registro no cambia.' using errcode = 'TK008';
    end if;

    new.created_at := old.created_at;
    new.created_by := old.created_by;
    new.updated_at := now();
    if auth.uid() is not null then
        new.updated_by := auth.uid();
    end if;
    if new.archived_at is distinct from old.archived_at and auth.uid() is not null then
        new.archived_by := auth.uid();
    elsif new.archived_at is not distinct from old.archived_at then
        new.archived_by := old.archived_by;
    end if;
    return new;
end;
$$;

-- 7.2 Marcas de tiempo de la tarea. Separan la espera del trabajo (métricas de flujo).
-- Con sesión no se pueden falsificar: se calculan a partir del cambio de estado.
create or replace function public.fn_task_timestamps()
returns trigger
language plpgsql as $$
begin
    if tg_op = 'INSERT' then
        if new.status <> 'pending' and new.started_at is null then
            new.started_at := coalesce(new.done_at, now());
        end if;
        if new.status = 'done' and new.done_at is null then
            new.done_at := now();
        end if;
        return new;
    end if;

    if auth.uid() is not null then
        new.started_at := old.started_at;
        new.done_at := old.done_at;
    end if;

    -- El inicio se sella la primera vez que entra a En curso y nunca se pisa:
    -- reabrir no borra el hecho de que ya se había trabajado.
    if new.status = 'in_progress' and new.started_at is null then
        new.started_at := now();
    end if;

    if new.status = 'done' and old.status is distinct from 'done' then
        new.done_at := now();
        -- Salto directo de pendiente a hecho: el tiempo de trabajo es cero, que es lo honesto
        if new.started_at is null then
            new.started_at := new.done_at;
        end if;
    elsif new.status <> 'done' then
        new.done_at := null;
    end if;
    return new;
end;
$$;

-- 7.3 Guarda de la tarea: qué puede hacer cada nivel. Es la regla de la base, no del botón.
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

-- 7.4 Lo agregado no se edita: evidencia y notas de turno sólo admiten su baja.
create or replace function public.fn_append_only_guard()
returns trigger
language plpgsql as $$
declare
    v_skip text[] := array['archived_at', 'archived_by', 'updated_at', 'updated_by'];
begin
    if (to_jsonb(new) - v_skip) is distinct from (to_jsonb(old) - v_skip) then
        raise exception 'Este registro se agrega y no se edita; sólo puede darse de baja.' using errcode = 'TK023';
    end if;
    return new;
end;
$$;

-- 7.5 Auditoría que omite una columna (texto libre). Igual que fn_audit_trigger, sin la columna.
create or replace function public.fn_audit_trigger_redacted()
returns trigger
security definer
set search_path = public
language plpgsql as $$
declare
    v_org uuid;
    v_old jsonb := null;
    v_new jsonb := null;
    v_rec uuid;
    v_col text := TG_ARGV[0];
begin
    if tg_op in ('INSERT', 'UPDATE') then
        v_new := to_jsonb(new) - v_col;
        v_rec := new.id;
        v_org := new.organization_id;
    end if;
    if tg_op in ('UPDATE', 'DELETE') then
        v_old := to_jsonb(old) - v_col;
        v_rec := old.id;
        v_org := old.organization_id;
    end if;

    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, old_values, new_values)
    values (v_org, auth.uid(), tg_op, tg_table_name, v_rec, v_old, v_new);

    return case when tg_op = 'DELETE' then old else new end;
end;
$$;

do $$
declare
    t text;
begin
    foreach t in array array['task_category', 'work_area', 'routine_template', 'routine_template_item',
                             'task', 'task_evidence', 'shift_note'] loop
        execute format('drop trigger if exists trg_task_10_stamp on public.%I', t);
        execute format('create trigger trg_task_10_stamp before insert or update on public.%I
                        for each row execute function public.fn_task_stamp()', t);
    end loop;

    -- Auditoría de escrituras (regla dura 5)
    foreach t in array array['task_category', 'work_area', 'routine_template', 'routine_template_item',
                             'task', 'task_evidence', 'task_setting'] loop
        execute format('drop trigger if exists trg_audit_%1$s on public.%1$I', t);
        execute format('create trigger trg_audit_%1$s after insert or update on public.%1$I
                        for each row execute function public.fn_audit_trigger()', t);
    end loop;
end $$;

drop trigger if exists trg_audit_shift_note on public.shift_note;
create trigger trg_audit_shift_note after insert or update on public.shift_note
for each row execute function public.fn_audit_trigger_redacted('body');

drop trigger if exists trg_task_20_guard on public.task;
create trigger trg_task_20_guard before insert or update on public.task
for each row execute function public.fn_task_guard();

drop trigger if exists trg_task_30_timestamps on public.task;
create trigger trg_task_30_timestamps before insert or update on public.task
for each row execute function public.fn_task_timestamps();

drop trigger if exists trg_task_evidence_20_guard on public.task_evidence;
create trigger trg_task_evidence_20_guard before update on public.task_evidence
for each row execute function public.fn_append_only_guard();

drop trigger if exists trg_shift_note_20_guard on public.shift_note;
create trigger trg_shift_note_20_guard before update on public.shift_note
for each row execute function public.fn_append_only_guard();

-- Los ajustes sólo los cambia la función de la migración 3; este sello deja la huella
create or replace function public.fn_task_setting_stamp()
returns trigger
language plpgsql as $$
begin
    if new.organization_id is distinct from old.organization_id then
        raise exception 'La organización de un registro no cambia.' using errcode = 'TK008';
    end if;
    new.updated_at := now();
    if auth.uid() is not null then
        new.updated_by := auth.uid();
    end if;
    return new;
end;
$$;

drop trigger if exists trg_task_setting_10_stamp on public.task_setting;
create trigger trg_task_setting_10_stamp before update on public.task_setting
for each row execute function public.fn_task_setting_stamp();

-- ---------------------------------------------------------------- 8. Privilegios (regla dura 3)
do $$
declare
    t text;
begin
    foreach t in array array['task_category', 'work_area', 'routine_template', 'routine_template_item',
                             'task', 'task_evidence', 'shift_note', 'task_setting'] loop
        execute format('alter table public.%I enable row level security', t);
        execute format('revoke all on public.%I from anon', t);
        execute format('revoke all on public.%I from authenticated', t);
        execute format('grant select on public.%I to authenticated', t);
    end loop;
    -- Escritura directa: todo salvo los ajustes (que se cambian por función). Nunca DELETE.
    foreach t in array array['task_category', 'work_area', 'routine_template', 'routine_template_item',
                             'task', 'task_evidence', 'shift_note'] loop
        execute format('grant insert, update on public.%I to authenticated', t);
    end loop;
end $$;

-- ---------------------------------------------------------------- 9. Políticas (RLS)
-- 9.0 Tenant + acceso a tareas: política RESTRICTIVA sobre todo (se suma con AND a las demás)
do $$
declare
    t text;
begin
    foreach t in array array['task_category', 'work_area', 'routine_template', 'routine_template_item',
                             'task', 'task_evidence', 'shift_note', 'task_setting'] loop
        execute format('drop policy if exists tenant_task_access on public.%I', t);
        execute format(
            'create policy tenant_task_access on public.%I as restrictive for all to authenticated
             using (organization_id = public.current_organization_id() and public.has_task_role())
             with check (organization_id = public.current_organization_id() and public.has_task_role())', t);
    end loop;
end $$;

-- 9.1 Catálogos: todos los roles de tareas leen lo vigente; sólo el director escribe
do $$
declare
    t text;
begin
    foreach t in array array['task_category', 'work_area'] loop
        execute format('drop policy if exists %1$s_select on public.%1$I', t);
        execute format('create policy %1$s_select on public.%1$I for select to authenticated
                        using (archived_at is null or public.has_task_management())', t);
        execute format('drop policy if exists %1$s_insert on public.%1$I', t);
        execute format('create policy %1$s_insert on public.%1$I for insert to authenticated
                        with check (public.has_role(''director''))', t);
        execute format('drop policy if exists %1$s_update on public.%1$I', t);
        execute format('create policy %1$s_update on public.%1$I for update to authenticated
                        using (public.has_role(''director'')) with check (public.has_role(''director''))', t);
    end loop;
end $$;

-- 9.2 Plantillas: la gestión las mantiene; el resto lee las vigentes para iniciar su jornada
drop policy if exists routine_template_select on public.routine_template;
create policy routine_template_select on public.routine_template for select to authenticated
    using (archived_at is null or public.has_task_management());
drop policy if exists routine_template_insert on public.routine_template;
create policy routine_template_insert on public.routine_template for insert to authenticated
    with check (public.has_task_management());
drop policy if exists routine_template_update on public.routine_template;
create policy routine_template_update on public.routine_template for update to authenticated
    using (public.has_task_management()) with check (public.has_task_management());

drop policy if exists routine_template_item_select on public.routine_template_item;
create policy routine_template_item_select on public.routine_template_item for select to authenticated
    using (
        public.has_task_management()
        or (archived_at is null and exists (
                select 1 from public.routine_template r
                where r.id = routine_template_item.routine_template_id and r.archived_at is null))
    );
drop policy if exists routine_template_item_insert on public.routine_template_item;
create policy routine_template_item_insert on public.routine_template_item for insert to authenticated
    with check (public.has_task_management());
drop policy if exists routine_template_item_update on public.routine_template_item;
create policy routine_template_item_update on public.routine_template_item for update to authenticated
    using (public.has_task_management()) with check (public.has_task_management());

-- 9.3 Tareas
--  * la gestión ve todas y las mantiene;
--  * cualquier otro rol de tareas ve las suyas y el pool (sin asignar y pendientes);
--  * quien tiene una tarea asignada sólo puede avanzarla (el disparador acota qué columnas).
drop policy if exists task_select_management on public.task;
create policy task_select_management on public.task for select to authenticated
    using (public.has_task_management());
drop policy if exists task_select_own on public.task;
create policy task_select_own on public.task for select to authenticated
    using (assigned_to = auth.uid() and archived_at is null);
drop policy if exists task_select_pool on public.task;
create policy task_select_pool on public.task for select to authenticated
    using (assigned_to is null and status = 'pending' and archived_at is null);

drop policy if exists task_insert_management on public.task;
create policy task_insert_management on public.task for insert to authenticated
    with check (public.has_task_management());
drop policy if exists task_update_management on public.task;
create policy task_update_management on public.task for update to authenticated
    using (public.has_task_management()) with check (public.has_task_management());
drop policy if exists task_update_own on public.task;
create policy task_update_own on public.task for update to authenticated
    using (assigned_to = auth.uid() and archived_at is null)
    with check (assigned_to = auth.uid());

-- 9.4 Evidencia: la gestión y quien tiene la tarea asignada y abierta
drop policy if exists task_evidence_select on public.task_evidence;
create policy task_evidence_select on public.task_evidence for select to authenticated
    using (
        public.has_task_management()
        or exists (select 1 from public.task t where t.id = task_evidence.task_id and t.assigned_to = auth.uid())
    );
drop policy if exists task_evidence_insert on public.task_evidence;
create policy task_evidence_insert on public.task_evidence for insert to authenticated
    with check (
        public.has_task_management()
        or exists (
            select 1 from public.task t
            where t.id = task_evidence.task_id and t.assigned_to = auth.uid()
              and t.status <> 'done' and t.archived_at is null)
    );
drop policy if exists task_evidence_update on public.task_evidence;
create policy task_evidence_update on public.task_evidence for update to authenticated
    using (public.has_task_management()) with check (public.has_task_management());

-- 9.5 Notas de turno: alcance y ventana según el ajuste de la organización
drop policy if exists shift_note_select on public.shift_note;
create policy shift_note_select on public.shift_note for select to authenticated
    using (
        (
            public.has_task_management()
            or public.current_shift_note_scope() = 'all'
            or (public.current_shift_note_scope() = 'own' and created_by = auth.uid())
            -- «Mi área» se deduce de dónde trabaja la persona, sin otro catálogo que mantener.
            -- Consecuencia deliberada: quien aún no tiene tareas no ve notas de área.
            or (public.current_shift_note_scope() = 'area'
                and work_area_id in (
                    select t.work_area_id from public.task t
                    where t.assigned_to = auth.uid() and t.work_area_id is not null))
        )
        and (public.current_shift_note_days() = 0
             or note_date >= current_date - public.current_shift_note_days())
        -- La autora conserva la vista de lo que retiró: al retirar con RETURNING, la política de
        -- lectura también se aplica a la fila nueva y, sin esto, la propia autora no podría
        -- retirar su nota.
        and (archived_at is null or created_by = auth.uid() or public.has_task_management())
    );
drop policy if exists shift_note_insert on public.shift_note;
create policy shift_note_insert on public.shift_note for insert to authenticated
    with check (true);
-- Retirar una nota (baja lógica): su autor o la gestión. El disparador impide editar el texto.
drop policy if exists shift_note_update on public.shift_note;
create policy shift_note_update on public.shift_note for update to authenticated
    using (created_by = auth.uid() or public.has_task_management())
    with check (created_by = auth.uid() or public.has_task_management());

-- 9.6 Ajustes: los lee todo el personal de tareas; ninguna escritura directa
drop policy if exists task_setting_select on public.task_setting;
create policy task_setting_select on public.task_setting for select to authenticated
    using (true);
