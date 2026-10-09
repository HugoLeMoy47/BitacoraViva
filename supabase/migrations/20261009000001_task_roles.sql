-- ==============================================================================
-- Seguidor de tareas (E7) · Migración 1 de 4: roles agregados (ADR-0007)
--
-- Plan: 30_entrega/plan-ciclo-integracion-e7-seguidor-de-tareas.md · Fase 1 (BV-7.1)
--
-- Qué hace
--  1. Agrega al catálogo `role` los roles que sólo operan en tareas: `task_manager`
--     (coordinación) y `volunteer` (voluntariado).
--  2. Separa "tiene algún rol" en tres preguntas distintas, porque a partir de ahora
--     ya no significan lo mismo:
--       * has_case_role()    -> viewer, caseworker, intake_officer o director
--       * has_active_role()  -> cualquier rol vigente (incluye los de tareas)
--       * has_task_role() / has_task_management() -> acceso a tareas
--  3. Protege al último `director` de cada organización (regla heredada del tracker,
--     PT006, aquí TK006).
--
-- Decisión de seguridad que vale la pena leer
--  `has_any_role()` ya se usa en las políticas del catálogo de casos y en los
--  indicadores agregados. Si siguiera significando "cualquier rol", un voluntario
--  pasaría esas puertas sin que nadie lo decidiera. Por eso `has_any_role()` pasa a
--  significar "tiene un rol de casos": lo que ya existía queda cerrado para los roles
--  de tareas POR DEFECTO, y sólo las políticas que de verdad deben admitirlos
--  (organización, perfiles y roles) se reescriben con `has_active_role()`.
--
-- Códigos de error propios del módulo (SQLSTATE): TK001 a TK0xx. Se documentan en
-- la migración que los define.
-- ==============================================================================

-- ---------------------------------------------------------------- 1. Catálogo de roles
do $$
declare
    v_con text;
begin
    -- El CHECK de `role.name` nació en línea con el nombre generado por el motor
    select c.conname into v_con
    from pg_constraint c
    where c.conrelid = 'public.role'::regclass
      and c.contype = 'c'
      and pg_get_constraintdef(c.oid) like '%viewer%';
    if v_con is not null then
        execute format('alter table public.role drop constraint %I', v_con);
    end if;
end $$;

alter table public.role
    add constraint role_name_check check (name in (
        'viewer', 'caseworker', 'intake_officer', 'director',
        'task_manager', 'volunteer'
    ));

insert into public.role (name, description) values
    ('task_manager', 'Coordinación de tareas: crea y asigna tareas, ve reportes y reabre. Sin acceso a personas ni casos'),
    ('volunteer', 'Voluntariado: ve sus tareas y el pool, las toma y las avanza. Sin acceso a personas ni casos')
on conflict (name) do nothing;

-- ---------------------------------------------------------------- 2. Preguntas de acceso
-- Roles que operan sobre el expediente o lo consultan en agregado.
create or replace function public.has_case_role()
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select exists (
        select 1 from public.user_role
        where user_id = auth.uid()
          and revoked_at is null
          and role_name in ('viewer', 'caseworker', 'intake_officer', 'director')
    );
$$;

-- Compatibilidad: significa "tiene un rol de casos". Ver la nota de seguridad del encabezado.
create or replace function public.has_any_role()
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select public.has_case_role();
$$;

-- Cualquier rol vigente, de casos o de tareas. Sólo para lo que debe ver todo el personal
-- de la organización (la propia organización, los perfiles y los roles).
create or replace function public.has_active_role()
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select exists (
        select 1 from public.user_role
        where user_id = auth.uid() and revoked_at is null
    );
$$;

-- La cuenta no está desactivada.
create or replace function public.is_active_user()
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select coalesce((select active from public.user_profile where id = auth.uid()), false);
$$;

-- Acceso a tareas: el voluntariado, la coordinación, la dirección y quienes reciben
-- tareas desde casos (caseworker, intake_officer). viewer queda fuera a propósito.
create or replace function public.has_task_role()
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select public.is_active_user() and exists (
        select 1 from public.user_role
        where user_id = auth.uid()
          and revoked_at is null
          and role_name in ('director', 'task_manager', 'volunteer', 'caseworker', 'intake_officer')
    );
$$;

-- Gestión de tareas: crear, editar, reabrir, cerrar sin foto y archivar.
create or replace function public.has_task_management()
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select public.is_active_user() and exists (
        select 1 from public.user_role
        where user_id = auth.uid()
          and revoked_at is null
          and role_name in ('director', 'task_manager')
    );
$$;

-- Lo mismo para una persona concreta (uso interno: validar a quién se asigna una tarea).
create or replace function public.user_has_task_role(p_user_id uuid)
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select coalesce((select active from public.user_profile where id = p_user_id), false) and exists (
        select 1 from public.user_role
        where user_id = p_user_id
          and revoked_at is null
          and role_name in ('director', 'task_manager', 'volunteer', 'caseworker', 'intake_officer')
    );
$$;

revoke execute on function public.has_case_role() from public, anon;
revoke execute on function public.has_any_role() from public, anon;
revoke execute on function public.has_active_role() from public, anon;
revoke execute on function public.is_active_user() from public, anon;
revoke execute on function public.has_task_role() from public, anon;
revoke execute on function public.has_task_management() from public, anon;
revoke execute on function public.user_has_task_role(uuid) from public, anon, authenticated;
grant execute on function public.has_case_role() to authenticated;
grant execute on function public.has_any_role() to authenticated;
grant execute on function public.has_active_role() to authenticated;
grant execute on function public.is_active_user() to authenticated;
grant execute on function public.has_task_role() to authenticated;
grant execute on function public.has_task_management() to authenticated;

-- ---------------------------------------------------------------- 3. Quién ve la estructura
-- Organización, perfiles y roles los lee todo el personal, también el de tareas.
-- (Las demás políticas restrictivas de 20261007000001 siguen con has_any_role(), que ahora
-- es "rol de casos": áreas funcionales y catálogos de estatus no son para tareas.)
drop policy if exists require_active_role_select on public.organization;
create policy require_active_role_select on public.organization
    as restrictive for select to authenticated
    using (public.has_active_role());

drop policy if exists require_active_role_select on public.user_profile;
create policy require_active_role_select on public.user_profile
    as restrictive for select to authenticated
    using (id = auth.uid() or public.has_active_role());

drop policy if exists require_active_role_select on public.user_role;
create policy require_active_role_select on public.user_role
    as restrictive for select to authenticated
    using (user_id = auth.uid() or public.has_active_role());

-- ---------------------------------------------------------------- 4. Último director (TK006)
-- Disponibilidad, no confidencialidad: sin ningún director vigente nadie puede repartir
-- roles, publicar el aviso de privacidad ni leer la auditoría, y la única salida sería la
-- consola de la base, justo lo que la regla 10 prohíbe. Se cubren las dos formas de
-- perderlo: revocar su rol de director y desactivar su cuenta.
create or replace function public.fn_protect_last_director()
returns trigger
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid;
    v_org uuid;
    v_remaining int;
begin
    if tg_table_name = 'user_role' then
        -- Sólo importa si la fila era un director vigente y deja de serlo
        if old.role_name <> 'director' or old.revoked_at is not null then
            return new;
        end if;
        if new.role_name = 'director' and new.revoked_at is null then
            return new;
        end if;
        v_user := old.user_id;
    else
        -- user_profile: sólo cuando una cuenta activa se desactiva
        if not (old.active and not new.active) then
            return new;
        end if;
        if not exists (
            select 1 from public.user_role
            where user_id = old.id and role_name = 'director' and revoked_at is null
        ) then
            return new;
        end if;
        v_user := old.id;
    end if;

    -- Si la persona conserva otra concesión vigente de director (otra área), sigue siéndolo
    if tg_table_name = 'user_role' and exists (
        select 1 from public.user_role
        where user_id = v_user and role_name = 'director' and revoked_at is null and id <> old.id
    ) then
        return new;
    end if;

    select organization_id into v_org from public.user_profile where id = v_user;

    select count(distinct ur.user_id) into v_remaining
    from public.user_role ur
    join public.user_profile up on up.id = ur.user_id
    where up.organization_id = v_org
      and up.active
      and ur.role_name = 'director'
      and ur.revoked_at is null
      and ur.user_id <> v_user;

    if v_remaining = 0 then
        raise exception 'No se puede dejar a la organización sin dirección: asigna el rol de director a otra persona primero.'
            using errcode = 'TK006';
    end if;

    return new;
end;
$$;

drop trigger if exists trg_protect_last_director on public.user_role;
create trigger trg_protect_last_director
before update on public.user_role
for each row execute function public.fn_protect_last_director();

drop trigger if exists trg_protect_last_director on public.user_profile;
create trigger trg_protect_last_director
before update on public.user_profile
for each row execute function public.fn_protect_last_director();

-- ---------------------------------------------------------------- 5. Integridad entre organizaciones
-- Permite llaves foráneas compuestas (id, organization_id): una tarea no puede apuntar
-- a una persona, categoría o plantilla de otra organización, ni por error ni a propósito.
alter table public.user_profile
    drop constraint if exists uq_user_profile_id_org;
alter table public.user_profile
    add constraint uq_user_profile_id_org unique (id, organization_id);
