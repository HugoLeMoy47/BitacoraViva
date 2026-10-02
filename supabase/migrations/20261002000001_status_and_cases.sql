-- ==============================================================================
-- Bitácora Viva — Migración 000002: Épicas E2 y E3
-- Catálogos de Estatus Multidimensional y Gestión de Casos (MAP-OIM v3)
-- Fuente de verdad: 50_Productos/BitacoraViva/20_arquitectura/modelo-de-datos.md
-- Normas: 10 Reglas Duras de Supabase y Modelo de Estatus Híbrido (ME-02/ME-04)
-- ==============================================================================

-- 1. Tabla: status_axis (Los 5 ejes normativos de estatus del sistema)
create table if not exists public.status_axis (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    code text not null check (code in ('legal_status', 'engagement_status', 'shelter_status', 'record_status', 'case_stage')),
    label_es text not null,
    is_primary boolean not null default false,
    is_system boolean not null default true,
    sort_order int not null default 0,
    created_at timestamptz not null default now(),
    unique (organization_id, code)
);

-- 2. Tabla: status_value (Catálogo de valores por eje de estatus)
create table if not exists public.status_value (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    axis_id uuid not null references public.status_axis(id) on delete cascade,
    code text not null,
    label_es text not null,
    sort_order int not null default 0,
    is_active_care boolean not null default false,
    is_system boolean not null default true,
    is_terminal boolean not null default false,
    created_at timestamptz not null default now(),
    unique (axis_id, code)
);

-- 3. Tabla: person (La persona atendida con ficha estandarizada MAP-OIM v3)
create table if not exists public.person (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    given_name text not null,
    paternal_family_name text not null,
    maternal_family_name text,
    preferred_name text,
    birth_date date not null,
    birth_date_is_estimated boolean not null default false,
    sex_id int not null default 1, -- 1: Masculino, 2: Femenino, 3: Otro
    other_sex text,
    nationality_country_id int not null default 1, -- OIM Catálogo
    other_nationality text,
    origin_department_id int,
    is_self_identified_migrant boolean not null default true,
    migration_profile_id int,
    other_profile text,
    primary_language_id int not null default 1, -- 1: Español
    other_language text,
    education_level_id int,
    marital_status_id int,
    occupations text[] default '{}'::text[],
    phone_number text,
    email text,
    address_line text,
    neighborhood text,
    postal_code text,
    is_anonymized boolean not null default false,
    anonymized_at timestamptz,
    anonymized_by uuid references public.user_profile(id),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- 4. Tabla: case (El expediente humanitario y folio único)
create table if not exists public.case (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    case_number text not null,
    parent_case_id uuid references public.case(id) on delete set null,
    previous_case_id uuid references public.case(id) on delete set null,
    titular_person_id uuid not null references public.person(id) on delete restrict,
    intake_state_id int not null default 9,
    intake_municipality_id int not null default 1,
    intake_channel_id int not null default 1,
    intake_window_type text not null default 'fija' check (intake_window_type in ('fija', 'movil', 'transaccional')),
    intake_date date not null default current_date,
    entry_route_id int not null default 3,
    entry_date_str text,
    travels_with_family boolean not null default false,
    opened_at timestamptz not null default now(),
    opened_by uuid references public.user_profile(id),
    closed_at timestamptz,
    closed_by uuid references public.user_profile(id),
    closure_reason text,
    assigned_area_id uuid references public.area(id),
    assigned_user_id uuid references public.user_profile(id),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (organization_id, case_number)
);

-- Vincular authority_request con foreign key a case ahora que existe la tabla
do $$
begin
    if not exists (
        select 1 from information_schema.table_constraints 
        where constraint_name = 'fk_authority_request_case'
    ) then
        alter table public.authority_request 
            add constraint fk_authority_request_case 
            foreign key (case_id) references public.case(id) on delete set null;
    end if;
exception when others then
    -- Ignorar si ya está vinculada o en local simple
end $$;

-- 5. Tabla: case_status (Hecho historizado con fecha y motivo - Regla Dura 7)
create table if not exists public.case_status (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    case_id uuid not null references public.case(id) on delete cascade,
    axis_id uuid not null references public.status_axis(id) on delete cascade,
    value_id uuid not null references public.status_value(id) on delete cascade,
    valid_from timestamptz not null default now(),
    valid_to timestamptz,
    reason text not null,
    created_by uuid references public.user_profile(id),
    created_at timestamptz not null default now()
);

-- Regla Dura 7: Índice único parcial para garantizar exactamente un estatus vigente por caso y eje
create unique index if not exists idx_case_status_current 
    on public.case_status (case_id, axis_id) 
    where valid_to is null;

-- 6. Tabla: case_vulnerability_marker (13 marcadores objetivos MAP-OIM v3)
create table if not exists public.case_vulnerability_marker (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    case_id uuid not null references public.case(id) on delete cascade,
    marker_code text not null check (marker_code in (
        'pregnant_or_lactating',
        'unaccompanied_child',
        'separated_child',
        'victim_of_violence',
        'medical_condition',
        'disability',
        'lgbtiq',
        'indigenous_language_speaker',
        'stateless_or_at_risk',
        'survivor_torture_trauma',
        'international_protection_need',
        'older_person_at_risk',
        'other_vulnerability'
    )),
    notes text,
    affirmed_by uuid not null references public.user_profile(id),
    affirmed_at timestamptz not null default now(),
    removed_by uuid references public.user_profile(id),
    removed_at timestamptz,
    created_at timestamptz not null default now()
);

-- Índices de consulta rápida
create index if not exists idx_status_axis_org on public.status_axis(organization_id);
create index if not exists idx_status_value_axis on public.status_value(axis_id);
create index if not exists idx_person_org on public.person(organization_id);
create index if not exists idx_person_name on public.person(paternal_family_name, given_name);
create index if not exists idx_case_org on public.case(organization_id);
create index if not exists idx_case_titular on public.case(titular_person_id);
create index if not exists idx_case_parent on public.case(parent_case_id);
create index if not exists idx_case_previous on public.case(previous_case_id);
create index if not exists idx_case_status_lookup on public.case_status(case_id, valid_to);
create index if not exists idx_vulnerability_case on public.case_vulnerability_marker(case_id);

-- ==============================================================================
-- REGLAS DE NEGOCIO Y DISPARADORES EN POSTGRESQL
-- ==============================================================================

-- Restricción: Un subfolio no puede tener subfolios (Profundidad máxima 1)
create or replace function public.fn_validate_subfolio_depth()
returns trigger as $$
declare
    v_grandparent_id uuid;
begin
    if new.parent_case_id is not null then
        select parent_case_id into v_grandparent_id 
        from public.case 
        where id = new.parent_case_id;

        if v_grandparent_id is not null then
            raise exception 'Violación de jerarquía: Un subfolio no puede tener subfolios dependientes (profundidad máxima 1).';
        end if;
    end if;
    return new;
end;
$$ language plpgsql;

drop trigger if exists trg_validate_subfolio_depth on public.case;
create trigger trg_validate_subfolio_depth
before insert or update on public.case
for each row execute function public.fn_validate_subfolio_depth();

-- Generador de folio secuencial y legible por organización (ej. ASF-2026-0001)
create or replace function public.fn_generate_case_number(p_org_id uuid)
returns text
language plpgsql as $$
declare
    v_slug text;
    v_prefix text;
    v_year text;
    v_seq int;
    v_folio text;
begin
    select slug into v_slug from public.organization where id = p_org_id;
    if v_slug is null then
        v_prefix := 'BV';
    else
        v_prefix := upper(substring(v_slug from 1 for 3));
    end if;

    v_year := to_char(now(), 'YYYY');

    -- Contar casos existentes en la organización para generar el correlativo
    select count(*) + 1 into v_seq from public.case where organization_id = p_org_id;

    v_folio := v_prefix || '-' || v_year || '-' || lpad(v_seq::text, 4, '0');
    return v_folio;
end;
$$;

-- Disparador: Todo caso nuevo nace con sus 5 ejes poblados (BV-2.2)
create or replace function public.fn_initialize_case_status()
returns trigger
security definer
set search_path = public
language plpgsql as $$
declare
    r_axis record;
    v_val_id uuid;
    v_initial_code text;
begin
    for r_axis in 
        select id, code from public.status_axis where organization_id = new.organization_id
    loop
        case r_axis.code
            when 'legal_status' then v_initial_code := 'undetermined';
            when 'engagement_status' then v_initial_code := 'first_contact';
            when 'shelter_status' then v_initial_code := 'not_applicable';
            when 'record_status' then v_initial_code := 'open';
            when 'case_stage' then v_initial_code := 'intake';
            else v_initial_code := null;
        end case;

        if v_initial_code is not null then
            select id into v_val_id 
            from public.status_value 
            where axis_id = r_axis.id and code = v_initial_code limit 1;

            if v_val_id is not null then
                insert into public.case_status (
                    organization_id,
                    case_id,
                    axis_id,
                    value_id,
                    valid_from,
                    valid_to,
                    reason,
                    created_by
                ) values (
                    new.organization_id,
                    new.id,
                    r_axis.id,
                    v_val_id,
                    now(),
                    null,
                    'Apertura de expediente y nacimiento automático de estatus',
                    new.opened_by
                );
            end if;
        end if;
    end loop;
    return new;
end;
$$;

drop trigger if exists trg_initialize_case_status on public.case;
create trigger trg_initialize_case_status
after insert on public.case
for each row execute function public.fn_initialize_case_status();

-- Función Transaccional para Cambio de Estatus (Regla Dura 7, ME-02 y Compartimentación)
create or replace function public.fn_change_case_status(
    p_case_id uuid,
    p_axis_code text,
    p_new_value_code text,
    p_reason text
)
returns uuid
security definer
set search_path = public
language plpgsql as $$
declare
    v_org_id uuid;
    v_axis_id uuid;
    v_old_status_id uuid;
    v_old_val_code text;
    v_new_val_id uuid;
    v_is_terminal boolean;
    v_new_status_id uuid;
    v_user_id uuid;
begin
    v_user_id := auth.uid();

    -- Validar motivo obligatorio
    if p_reason is null or trim(p_reason) = '' then
        raise exception 'Violación de integridad: Todo cambio de estatus exige un motivo explícito en texto (reason).';
    end if;

    -- Obtener caso y organización
    select organization_id into v_org_id from public.case where id = p_case_id;
    if v_org_id is null then
        raise exception 'Expediente no encontrado.';
    end if;

    -- Validar compartimentación por área (BV-2.3)
    if p_axis_code = 'legal_status' then
        if not (public.has_role('director') or public.has_role_in_area('caseworker', 'legal')) then
            raise exception 'Permiso denegado: El estatus jurídico solo puede ser modificado por Dirección o personal adscrito al Área Jurídica.';
        end if;
    end if;

    -- Validar gobernanza de cierre y reapertura
    if p_axis_code = 'record_status' and p_new_value_code in ('closed', 'anonymized') then
        if not public.has_role('director') then
            raise exception 'Permiso denegado: El cierre administrativo o anonimización del expediente es facultad exclusiva de Dirección.';
        end if;
    end if;

    -- Obtener eje
    select id into v_axis_id from public.status_axis where organization_id = v_org_id and code = p_axis_code;
    if v_axis_id is null then
        raise exception 'Eje de estatus no válido para esta organización.';
    end if;

    -- Obtener valor nuevo
    select id, is_terminal into v_new_val_id, v_is_terminal 
    from public.status_value 
    where axis_id = v_axis_id and code = p_new_value_code;

    if v_new_val_id is null then
        raise exception 'Valor de estatus destino no encontrado en el catálogo.';
    end if;

    -- Obtener estatus vigente actual
    select cs.id, sv.code into v_old_status_id, v_old_val_code
    from public.case_status cs
    join public.status_value sv on sv.id = cs.value_id
    where cs.case_id = p_case_id and cs.axis_id = v_axis_id and cs.valid_to is null;

    -- Candado: anonimizado es terminal irreversible
    if v_old_val_code = 'anonymized' then
        raise exception 'Violación de Ethos: Un expediente en estatus anonimizado es terminal e irreversible.';
    end if;

    -- Cerrar estatus vigente actual en la misma transacción (Regla Dura 7)
    if v_old_status_id is not null then
        update public.case_status
        set valid_to = now()
        where id = v_old_status_id;
    end if;

    -- Insertar nuevo estatus vigente
    insert into public.case_status (
        organization_id,
        case_id,
        axis_id,
        value_id,
        valid_from,
        valid_to,
        reason,
        created_by
    ) values (
        v_org_id,
        p_case_id,
        v_axis_id,
        v_new_val_id,
        now(),
        null,
        p_reason,
        v_user_id
    ) returning id into v_new_status_id;

    -- Si se cierra el expediente en record_status, actualizar metadatos en case
    if p_axis_code = 'record_status' and p_new_value_code = 'closed' then
        update public.case 
        set closed_at = now(), closed_by = v_user_id, closure_reason = p_reason
        where id = p_case_id;
    end if;

    return v_new_status_id;
end;
$$;

-- Vincular disparador de auditoría a todas las nuevas tablas
drop trigger if exists trg_audit_status_axis on public.status_axis;
create trigger trg_audit_status_axis
after insert or update on public.status_axis
for each row execute function public.fn_audit_trigger();

drop trigger if exists trg_audit_status_value on public.status_value;
create trigger trg_audit_status_value
after insert or update on public.status_value
for each row execute function public.fn_audit_trigger();

drop trigger if exists trg_audit_person on public.person;
create trigger trg_audit_person
after insert or update on public.person
for each row execute function public.fn_audit_trigger();

drop trigger if exists trg_audit_case on public.case;
create trigger trg_audit_case
after insert or update on public.case
for each row execute function public.fn_audit_trigger();

drop trigger if exists trg_audit_case_status on public.case_status;
create trigger trg_audit_case_status
after insert or update on public.case_status
for each row execute function public.fn_audit_trigger();

drop trigger if exists trg_audit_case_vulnerability_marker on public.case_vulnerability_marker;
create trigger trg_audit_case_vulnerability_marker
after insert or update on public.case_vulnerability_marker
for each row execute function public.fn_audit_trigger();

-- ==============================================================================
-- ROW LEVEL SECURITY (RLS)
-- ==============================================================================

alter table public.status_axis enable row level security;
alter table public.status_value enable row level security;
alter table public.person enable row level security;
alter table public.case enable row level security;
alter table public.case_status enable row level security;
alter table public.case_vulnerability_marker enable row level security;

-- Regla Dura 3: Revocar DELETE sobre tablas de negocio a authenticated
revoke delete on public.status_axis from authenticated;
revoke delete on public.status_value from authenticated;
revoke delete on public.person from authenticated;
revoke delete on public.case from authenticated;
revoke delete on public.case_status from authenticated;
revoke delete on public.case_vulnerability_marker from authenticated;

-- Políticas: status_axis y status_value (Catálogos legibles por usuarios de la org)
create policy "Usuarios ven ejes de estatus de su organización"
    on public.status_axis for select to authenticated
    using (organization_id = public.current_organization_id());

create policy "Directores gestionan ejes de estatus de su organización"
    on public.status_axis for all to authenticated
    using (organization_id = public.current_organization_id() and public.has_role('director'))
    with check (organization_id = public.current_organization_id() and public.has_role('director'));

create policy "Usuarios ven valores de estatus de su organización"
    on public.status_value for select to authenticated
    using (organization_id = public.current_organization_id());

create policy "Directores gestionan valores de estatus de su organización"
    on public.status_value for all to authenticated
    using (organization_id = public.current_organization_id() and public.has_role('director'))
    with check (organization_id = public.current_organization_id() and public.has_role('director'));

-- Políticas: person
create policy "Usuarios ven personas de su organización"
    on public.person for select to authenticated
    using (organization_id = public.current_organization_id());

create policy "Intake y directores registran personas de su organización"
    on public.person for insert to authenticated
    with check (
        organization_id = public.current_organization_id() 
        and (public.has_role('intake_officer') or public.has_role('director'))
    );

create policy "Gestores y directores actualizan personas de su organización"
    on public.person for update to authenticated
    using (
        organization_id = public.current_organization_id()
        and (public.has_role('caseworker') or public.has_role('intake_officer') or public.has_role('director'))
    )
    with check (
        organization_id = public.current_organization_id()
        and (public.has_role('caseworker') or public.has_role('intake_officer') or public.has_role('director'))
    );

-- Políticas: case
create policy "Usuarios ven casos de su organización"
    on public.case for select to authenticated
    using (organization_id = public.current_organization_id());

create policy "Intake y directores abren casos de su organización"
    on public.case for insert to authenticated
    with check (
        organization_id = public.current_organization_id()
        and (public.has_role('intake_officer') or public.has_role('director'))
    );

create policy "Gestores y directores actualizan casos de su organización"
    on public.case for update to authenticated
    using (
        organization_id = public.current_organization_id()
        and (public.has_role('caseworker') or public.has_role('intake_officer') or public.has_role('director'))
    )
    with check (
        organization_id = public.current_organization_id()
        and (public.has_role('caseworker') or public.has_role('intake_officer') or public.has_role('director'))
    );

-- Políticas: case_status
create policy "Usuarios ven estatus de casos de su organización"
    on public.case_status for select to authenticated
    using (organization_id = public.current_organization_id());

create policy "Gestores, intake y directores insertan estatus con motivo"
    on public.case_status for insert to authenticated
    with check (
        organization_id = public.current_organization_id()
        and (public.has_role('caseworker') or public.has_role('intake_officer') or public.has_role('director'))
    );

create policy "Actualización de estatus restringida al cierre de vigencia"
    on public.case_status for update to authenticated
    using (
        organization_id = public.current_organization_id()
        and (public.has_role('caseworker') or public.has_role('intake_officer') or public.has_role('director'))
    )
    with check (
        organization_id = public.current_organization_id()
        and (public.has_role('caseworker') or public.has_role('intake_officer') or public.has_role('director'))
    );

-- Políticas: case_vulnerability_marker
create policy "Usuarios ven marcadores de vulnerabilidad de su organización"
    on public.case_vulnerability_marker for select to authenticated
    using (organization_id = public.current_organization_id());

create policy "Gestores, intake y directores afirman marcadores de vulnerabilidad"
    on public.case_vulnerability_marker for insert to authenticated
    with check (
        organization_id = public.current_organization_id()
        and (public.has_role('caseworker') or public.has_role('intake_officer') or public.has_role('director'))
    );

create policy "Gestores y directores retiran o actualizan marcadores con auditoría"
    on public.case_vulnerability_marker for update to authenticated
    using (
        organization_id = public.current_organization_id()
        and (public.has_role('caseworker') or public.has_role('director'))
    )
    with check (
        organization_id = public.current_organization_id()
        and (public.has_role('caseworker') or public.has_role('director'))
    );
