-- ==============================================================================
-- Bitácora Viva — Migración 000001: Fundación Transversal (Épica E1)
-- Fuente de verdad: 50_Productos/BitacoraViva/20_arquitectura/modelo-de-datos.md
-- Normas: 10 Reglas Duras de Supabase (30_entrega/handoff-agente-desarrollo.md)
-- Alineación: Ethos v1.2 (C4, E-01, E-02, E-03, E-05) y RNF v1.0
-- ==============================================================================

-- 1. Extensiones necesarias
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- 2. Tabla: organization (Tenants / Albergues u Organizaciones de la Sociedad Civil)
create table if not exists public.organization (
    id uuid primary key default gen_random_uuid(),
    slug text not null unique,
    legal_name text not null,
    display_name text not null,
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- 3. Tabla: role (Catálogo estricto de 4 roles de negocio)
create table if not exists public.role (
    name text primary key check (name in ('viewer', 'caseworker', 'intake_officer', 'director')),
    description text not null,
    created_at timestamptz not null default now()
);

-- Insertar roles normativos
insert into public.role (name, description) values
    ('viewer', 'Lectura de métricas agregadas y anonimizadas; sin acceso a datos identificables'),
    ('caseworker', 'Gestión integral del caso, notas de evolución y bitácora en áreas asignadas'),
    ('intake_officer', 'Recepción inicial, levantamiento de ficha básica y apertura de folios'),
    ('director', 'Supervisión global del albergue, gobernanza de roles, digest de alertas y auditoría')
on conflict (name) do nothing;

-- 4. Tabla: user_profile (Perfiles vinculados a auth.users de Supabase)
create table if not exists public.user_profile (
    id uuid primary key references auth.users(id) on delete cascade,
    organization_id uuid not null references public.organization(id),
    email text not null,
    full_name text not null,
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- 5. Tabla: area (Áreas operativas dentro del albergue)
create table if not exists public.area (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    code text not null check (code in ('legal', 'psicologia', 'trabajo_social', 'medica', 'coordinacion')),
    name text not null,
    active boolean not null default true,
    created_at timestamptz not null default now(),
    unique (organization_id, code)
);

-- 6. Tabla: user_role (Asignación de roles con área operativa y trazabilidad de revocación)
-- Concesiones no se borran: se revocan con fecha para preservar auditoría de quién tuvo acceso (BV-1.2)
create table if not exists public.user_role (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.user_profile(id) on delete cascade,
    role_name text not null references public.role(name),
    area_id uuid references public.area(id),
    granted_by uuid references public.user_profile(id),
    granted_at timestamptz not null default now(),
    revoked_by uuid references public.user_profile(id),
    revoked_at timestamptz
);

-- Unicidad de rol activo por usuario y área (coalesce para rol transversal con area_id nula)
create unique index if not exists idx_user_role_active 
    on public.user_role (user_id, role_name, coalesce(area_id, '00000000-0000-0000-0000-000000000000'::uuid)) 
    where revoked_at is null;

-- 7. Tabla: authority_request (Requerimientos de autoridad judicial o administrativa - Ethos E-03)
-- Acceso reservado exclusivamente para roles de dirección
create table if not exists public.authority_request (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    case_id uuid, -- se vinculará formalmente vía FK cuando exista public.case en E3
    authority_name text not null,
    request_type text not null,
    official_letter_ref text not null,
    received_at timestamptz not null,
    handled_by_user_id uuid references public.user_profile(id),
    response_summary text,
    extract_delivered boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- 8. Tabla: audit_event (Regla Dura 4: Inmutable y Append-Only)
create table if not exists public.audit_event (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    user_id uuid references auth.users(id),
    action text not null check (action in ('INSERT', 'UPDATE', 'DELETE', 'LOGIN', 'EXPORT', 'STATUS_CHANGE')),
    table_name text not null,
    record_id uuid,
    old_values jsonb,
    new_values jsonb,
    ip_address text,
    user_agent text,
    created_at timestamptz not null default now()
);

-- Índices de consulta rápida
create index if not exists idx_user_profile_org on public.user_profile(organization_id);
create index if not exists idx_user_role_user on public.user_role(user_id);
create index if not exists idx_area_org on public.area(organization_id);
create index if not exists idx_authority_request_org on public.authority_request(organization_id);
create index if not exists idx_audit_event_org_created on public.audit_event(organization_id, created_at desc);
create index if not exists idx_audit_event_record on public.audit_event(table_name, record_id);

-- ==============================================================================
-- REGLAS DURAS DE INMUTABILIDAD Y PROTECCIÓN DE AUDITORÍA
-- ==============================================================================

-- Regla Dura 4: Disparador que bloquea cualquier intento de UPDATE o DELETE en audit_event
create or replace function public.fn_prevent_audit_tampering()
returns trigger as $$
begin
    raise exception 'Violación de Ethos: La tabla audit_event es estrictamente append-only. UPDATE o DELETE están prohibidos en el motor de base de datos.';
end;
$$ language plpgsql;

drop trigger if exists trg_prevent_audit_tampering on public.audit_event;
create trigger trg_prevent_audit_tampering
before update or delete on public.audit_event
for each row execute function public.fn_prevent_audit_tampering();

-- Regla Dura 5: Disparador de auditoría automática de escrituras
create or replace function public.fn_audit_trigger()
returns trigger
security definer
set search_path = public
language plpgsql as $$
declare
    v_org_id uuid;
    v_user_id uuid;
    v_rec_id uuid;
    v_old jsonb := null;
    v_new jsonb := null;
begin
    -- Obtener usuario actual autenticado
    v_user_id := auth.uid();

    if TG_OP = 'INSERT' then
        v_rec_id := (new.id)::uuid;
        v_new := to_jsonb(new);
        begin
            v_org_id := (new.organization_id)::uuid;
        exception when others then
            v_org_id := null;
        end;
    elsif TG_OP = 'UPDATE' then
        v_rec_id := (new.id)::uuid;
        v_old := to_jsonb(old);
        v_new := to_jsonb(new);
        begin
            v_org_id := (new.organization_id)::uuid;
        exception when others then
            v_org_id := null;
        end;
    elsif TG_OP = 'DELETE' then
        v_rec_id := (old.id)::uuid;
        v_old := to_jsonb(old);
        begin
            v_org_id := (old.organization_id)::uuid;
        exception when others then
            v_org_id := null;
        end;
    end if;

    -- Si no se pudo obtener org_id directo, buscar en el perfil del usuario
    if v_org_id is null and v_user_id is not null then
        select organization_id into v_org_id from public.user_profile where id = v_user_id;
    end if;

    -- Si se tiene organization_id, asentar evento
    if v_org_id is not null then
        insert into public.audit_event (
            organization_id,
            user_id,
            action,
            table_name,
            record_id,
            old_values,
            new_values
        ) values (
            v_org_id,
            v_user_id,
            TG_OP,
            TG_TABLE_NAME,
            v_rec_id,
            v_old,
            v_new
        );
    end if;

    if TG_OP = 'DELETE' then
        return old;
    else
        return new;
    end if;
end;
$$;

-- Vincular auditoría de escritura a las tablas de negocio de E1
drop trigger if exists trg_audit_organization on public.organization;
create trigger trg_audit_organization
after insert or update on public.organization
for each row execute function public.fn_audit_trigger();

drop trigger if exists trg_audit_user_profile on public.user_profile;
create trigger trg_audit_user_profile
after insert or update on public.user_profile
for each row execute function public.fn_audit_trigger();

drop trigger if exists trg_audit_area on public.area;
create trigger trg_audit_area
after insert or update on public.area
for each row execute function public.fn_audit_trigger();

drop trigger if exists trg_audit_user_role on public.user_role;
create trigger trg_audit_user_role
after insert or update on public.user_role
for each row execute function public.fn_audit_trigger();

drop trigger if exists trg_audit_authority_request on public.authority_request;
create trigger trg_audit_authority_request
after insert or update on public.authority_request
for each row execute function public.fn_audit_trigger();

-- ==============================================================================
-- FUNCIONES DE ASISTENCIA Y ROW LEVEL SECURITY (RLS)
-- ==============================================================================

-- Helper para obtener la organización del usuario autenticado
create or replace function public.current_organization_id()
returns uuid
stable
security definer
set search_path = public
language sql as $$
    select organization_id from public.user_profile where id = auth.uid() limit 1;
$$;

-- Helper para verificar si el usuario tiene un rol activo específico (revoked_at is null)
create or replace function public.has_role(p_role text)
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select exists (
        select 1 from public.user_role
        where user_id = auth.uid() 
          and role_name = p_role 
          and revoked_at is null
    );
$$;

-- Helper para verificar si el usuario tiene un rol activo adscrito a un área específica
create or replace function public.has_role_in_area(p_role text, p_area_code text)
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select exists (
        select 1 from public.user_role ur
        join public.area a on a.id = ur.area_id
        where ur.user_id = auth.uid()
          and ur.role_name = p_role
          and a.code = p_area_code
          and ur.revoked_at is null
    );
$$;

-- Habilitar RLS en todas las tablas
alter table public.organization enable row level security;
alter table public.role enable row level security;
alter table public.user_profile enable row level security;
alter table public.user_role enable row level security;
alter table public.area enable row level security;
alter table public.authority_request enable row level security;
alter table public.audit_event enable row level security;

-- Revocar DELETE en tablas de negocio para el rol authenticated (Regla Dura 3)
revoke delete on public.organization from authenticated;
revoke delete on public.user_profile from authenticated;
revoke delete on public.user_role from authenticated;
revoke delete on public.area from authenticated;
revoke delete on public.authority_request from authenticated;
revoke delete, update on public.audit_event from authenticated;

-- Políticas: role (Catálogo legible para todo usuario autenticado)
create policy "Roles legibles por usuarios autenticados"
    on public.role for select
    to authenticated
    using (true);

-- Políticas: organization
create policy "Usuarios ven su propia organización"
    on public.organization for select
    to authenticated
    using (id = public.current_organization_id());

create policy "Directores pueden actualizar su organización"
    on public.organization for update
    to authenticated
    using (id = public.current_organization_id() and public.has_role('director'))
    with check (id = public.current_organization_id() and public.has_role('director'));

-- Políticas: user_profile
create policy "Usuarios ven perfiles de su misma organización"
    on public.user_profile for select
    to authenticated
    using (organization_id = public.current_organization_id());

create policy "Directores pueden insertar y actualizar perfiles de su organización"
    on public.user_profile for insert
    to authenticated
    with check (organization_id = public.current_organization_id() and public.has_role('director'));

create policy "Directores o el propio usuario pueden actualizar perfil"
    on public.user_profile for update
    to authenticated
    using (organization_id = public.current_organization_id() and (id = auth.uid() or public.has_role('director')))
    with check (organization_id = public.current_organization_id() and (id = auth.uid() or public.has_role('director')));

-- Políticas: user_role
create policy "Usuarios ven roles de su organización"
    on public.user_role for select
    to authenticated
    using (exists (
        select 1 from public.user_profile up
        where up.id = user_role.user_id and up.organization_id = public.current_organization_id()
    ));

create policy "Directores gestionan roles de usuarios de su organización"
    on public.user_role for insert
    to authenticated
    with check (
        public.has_role('director') and exists (
            select 1 from public.user_profile up
            where up.id = user_role.user_id and up.organization_id = public.current_organization_id()
        )
    );

create policy "Directores actualizan/revocan roles de usuarios de su organización"
    on public.user_role for update
    to authenticated
    using (
        public.has_role('director') and exists (
            select 1 from public.user_profile up
            where up.id = user_role.user_id and up.organization_id = public.current_organization_id()
        )
    )
    with check (
        public.has_role('director') and exists (
            select 1 from public.user_profile up
            where up.id = user_role.user_id and up.organization_id = public.current_organization_id()
        )
    );

-- Políticas: area
create policy "Usuarios ven áreas activas de su organización"
    on public.area for select
    to authenticated
    using (organization_id = public.current_organization_id() and active = true);

create policy "Directores gestionan áreas de su organización"
    on public.area for all
    to authenticated
    using (organization_id = public.current_organization_id() and public.has_role('director'))
    with check (organization_id = public.current_organization_id() and public.has_role('director'));

-- Políticas: authority_request (Ethos E-03: acceso exclusivo para roles de dirección)
create policy "Solo directores leen requerimientos de autoridad"
    on public.authority_request for select
    to authenticated
    using (
        organization_id = public.current_organization_id()
        and public.has_role('director')
    );

create policy "Solo directores gestionan requerimientos de autoridad"
    on public.authority_request for all
    to authenticated
    using (
        organization_id = public.current_organization_id()
        and public.has_role('director')
    )
    with check (
        organization_id = public.current_organization_id()
        and public.has_role('director')
    );

-- Políticas: audit_event (Regla Dura 4: solo lectura para dirección dentro de su org, Ethos C4)
create policy "Solo directores leen auditoría de su organización"
    on public.audit_event for select
    to authenticated
    using (
        organization_id = public.current_organization_id()
        and public.has_role('director')
    );
