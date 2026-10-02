-- ==============================================================================
-- Bitácora Viva — Migración 000003: Épica E4
-- Bitácora de Área, Visibilidad, Compartición y Ergonomía de Corrección
-- Fuente de verdad: 50_Productos/BitacoraViva/20_arquitectura/modelo-de-datos.md
-- Normas: Ethos C3, ADR-0005, Reglas Duras 1-7 y 10 de Supabase
-- ==============================================================================

-- 1. Tabla: journal_entry (Inmutable, Privada por Defecto y con Ergonomía de Corrección)
create table if not exists public.journal_entry (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    case_id uuid not null references public.case(id) on delete cascade,
    area_id uuid not null references public.area(id),
    author_user_id uuid not null references public.user_profile(id),
    entry_type_key text not null check (entry_type_key in (
        'intake_interview', -- Entrevista de ingreso cualitativa inicial (MAP-OIM v3 tbMap156)
        'follow_up',        -- Nota de seguimiento / evolución
        'referral',         -- Derivación / interconsulta
        'home_visit',       -- Visita domiciliaria / comunitaria
        'incident',         -- Incidencia o evento crítico de protección
        'note'              -- Nota general de trabajo social o administrativa
    )),
    body text not null,
    -- Ethos E-02 / MD-04: Nota de trabajo protegida (deliberación profesional interna, excluida de ARCO)
    is_work_note boolean not null default false,
    -- Distinción temporal obligatoria: cuándo pasó vs cuándo se redactó
    occurred_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    -- Ethos C3 / Regla Dura 6: Nace privada al área por omisión a nivel de esquema
    visibility text not null default 'area_private' check (visibility in ('area_private', 'shared')),
    -- BV-4.2: Enlace a la nota aclaratoria / fe de erratas que la supera
    superseded_by_id uuid references public.journal_entry(id)
);

-- 2. Tabla: sharing_event (Registro inmutable del momento y motivo en que se comparte)
create table if not exists public.sharing_event (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    journal_entry_id uuid not null references public.journal_entry(id) on delete cascade,
    case_id uuid not null references public.case(id) on delete cascade,
    from_area_id uuid not null references public.area(id),
    to_area_id uuid not null references public.area(id),
    from_visibility text not null default 'area_private',
    to_visibility text not null default 'shared',
    reason text not null, -- Motivo obligatorio e ineludible (Ethos C3)
    shared_by_user_id uuid not null references public.user_profile(id),
    shared_at timestamptz not null default now(),
    -- Bandeja directiva (digest/inbox): acuse de recibo de dirección (BV-4.4 / ADR-0005)
    acknowledged_by_user_id uuid references public.user_profile(id),
    acknowledged_at timestamptz
);

-- 3. Tabla: attachment (Evidencias y documentos adjuntos privados)
create table if not exists public.attachment (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    case_id uuid not null references public.case(id) on delete cascade,
    journal_entry_id uuid references public.journal_entry(id) on delete set null,
    storage_path text not null,
    file_name text not null,
    mime_type text not null,
    size_bytes bigint not null,
    uploaded_by uuid not null references public.user_profile(id),
    uploaded_at timestamptz not null default now(),
    visibility text not null default 'area_private' check (visibility in ('area_private', 'shared'))
);

-- Índices de consulta de alto rendimiento
create index if not exists idx_journal_entry_case on public.journal_entry (case_id, occurred_at desc);
create index if not exists idx_journal_entry_area on public.journal_entry (area_id, visibility);
create index if not exists idx_sharing_event_pending on public.sharing_event (organization_id, acknowledged_at) where acknowledged_at is null;
create index if not exists idx_attachment_case on public.attachment (case_id);

-- ==============================================================================
-- 4. Disparadores de Inmutabilidad e Integridad Estricta
-- ==============================================================================

-- Disparador: Prohibir DELETE absoluto en journal_entry, sharing_event y attachment (Regla Dura 3)
create or replace function public.fn_prevent_delete_journal()
returns trigger as $$
begin
    raise exception 'Violación de integridad: La bitácora y sus evidencias son estrictamente inmutables; no se permite borrar registros (Regla Dura 3 / ADR-0005).';
end;
$$ language plpgsql;

drop trigger if exists trg_prevent_delete_journal_entry on public.journal_entry;
create trigger trg_prevent_delete_journal_entry
before delete on public.journal_entry
for each row execute function public.fn_prevent_delete_journal();

drop trigger if exists trg_prevent_delete_sharing_event on public.sharing_event;
create trigger trg_prevent_delete_sharing_event
before delete on public.sharing_event
for each row execute function public.fn_prevent_delete_journal();

-- Disparador: Prevenir modificación del cuerpo o metadatos de journal_entry
create or replace function public.fn_prevent_update_journal_entry()
returns trigger as $$
begin
    -- Solo se permite actualizar:
    -- 1) superseded_by_id (al vincular una fe de erratas)
    -- 2) visibility (al transicionar a shared mediante sharing_event)
    if old.body != new.body or
       old.author_user_id != new.author_user_id or
       old.area_id != new.area_id or
       old.occurred_at != new.occurred_at or
       old.created_at != new.created_at or
       old.entry_type_key != new.entry_type_key or
       old.case_id != new.case_id or
       old.organization_id != new.organization_id then
        raise exception 'Violación de integridad: El contenido original de un registro de bitácora no admite edición. Utilice una fe de erratas (BV-4.2).';
    end if;

    -- Si se cambia visibility a shared, verificar que existe motivo de compartición
    if old.visibility = 'area_private' and new.visibility = 'shared' then
        -- Permitido en el flujo transaccional
        null;
    end if;

    return new;
end;
$$ language plpgsql;

drop trigger if exists trg_prevent_update_journal_entry on public.journal_entry;
create trigger trg_prevent_update_journal_entry
before update on public.journal_entry
for each row execute function public.fn_prevent_update_journal_entry();

-- ==============================================================================
-- 5. Funciones Transaccionales para Flujos de Negocio
-- ==============================================================================

-- Función: Crear entrada de bitácora
create or replace function public.fn_create_journal_entry(
    p_case_id uuid,
    p_entry_type_key text,
    p_body text,
    p_occurred_at timestamptz default now(),
    p_is_work_note boolean default false,
    p_area_id uuid default null
)
returns uuid
security definer
set search_path = public
language plpgsql as $$
declare
    v_user_id uuid;
    v_org_id uuid;
    v_area_id uuid;
    v_new_entry_id uuid;
begin
    v_user_id := auth.uid();
    
    if p_body is null or trim(p_body) = '' then
        raise exception 'El texto de la intervención en bitácora es obligatorio.';
    end if;

    -- Obtener caso y organización
    select organization_id into v_org_id from public.case where id = p_case_id;
    if v_org_id is null then
        raise exception 'Expediente no encontrado.';
    end if;

    -- Determinar área operativa del autor
    if p_area_id is not null then
        v_area_id := p_area_id;
    else
        select area_id into v_area_id 
        from public.user_role 
        where user_id = v_user_id and revoked_at is null and area_id is not null 
        limit 1;
        
        -- Si es director sin área específica, asociar a área de coordinación
        if v_area_id is null then
            select id into v_area_id 
            from public.area 
            where organization_id = v_org_id and code = 'coordinacion' 
            limit 1;
        end if;
    end if;

    if v_area_id is null then
        raise exception 'No se pudo determinar el área operativa para el registro de bitácora.';
    end if;

    insert into public.journal_entry (
        organization_id,
        case_id,
        area_id,
        author_user_id,
        entry_type_key,
        body,
        is_work_note,
        occurred_at,
        created_at,
        visibility
    ) values (
        v_org_id,
        p_case_id,
        v_area_id,
        v_user_id,
        p_entry_type_key,
        p_body,
        p_is_work_note,
        coalesce(p_occurred_at, now()),
        now(),
        'area_private'
    ) returning id into v_new_entry_id;

    -- Disparador de auditoría
    insert into public.audit_event (
        organization_id,
        actor_user_id,
        action,
        table_name,
        record_id,
        case_id,
        new_values
    ) values (
        v_org_id,
        v_user_id,
        'INSERT',
        'journal_entry',
        v_new_entry_id,
        p_case_id,
        jsonb_build_object(
            'entry_type_key', p_entry_type_key,
            'is_work_note', p_is_work_note,
            'area_id', v_area_id,
            'occurred_at', p_occurred_at
        )
    );

    return v_new_entry_id;
end;
$$;

-- Función: Asentar fe de erratas / nota aclaratoria (BV-4.2)
create or replace function public.fn_create_clarification_note(
    p_superseded_entry_id uuid,
    p_body text,
    p_occurred_at timestamptz default now(),
    p_is_work_note boolean default false
)
returns uuid
security definer
set search_path = public
language plpgsql as $$
declare
    v_old_entry record;
    v_user_id uuid;
    v_new_entry_id uuid;
begin
    v_user_id := auth.uid();

    select * into v_old_entry 
    from public.journal_entry 
    where id = p_superseded_entry_id;

    if v_old_entry.id is null then
        raise exception 'El registro de bitácora original a corregir no existe.';
    end if;

    if v_old_entry.superseded_by_id is not null then
        raise exception 'Este registro de bitácora ya ha sido superado por una aclaración previa.';
    end if;

    -- Crear la nueva entrada de corrección
    insert into public.journal_entry (
        organization_id,
        case_id,
        area_id,
        author_user_id,
        entry_type_key,
        body,
        is_work_note,
        occurred_at,
        created_at,
        visibility
    ) values (
        v_old_entry.organization_id,
        v_old_entry.case_id,
        v_old_entry.area_id,
        v_user_id,
        v_old_entry.entry_type_key,
        p_body,
        p_is_work_note,
        coalesce(p_occurred_at, now()),
        now(),
        v_old_entry.visibility
    ) returning id into v_new_entry_id;

    -- Vincular el registro original al nuevo registro aclaratorio
    update public.journal_entry
    set superseded_by_id = v_new_entry_id
    where id = p_superseded_entry_id;

    -- Auditoría
    insert into public.audit_event (
        organization_id,
        actor_user_id,
        action,
        table_name,
        record_id,
        case_id,
        new_values
    ) values (
        v_old_entry.organization_id,
        v_user_id,
        'CLARIFICATION',
        'journal_entry',
        v_new_entry_id,
        v_old_entry.case_id,
        jsonb_build_object(
            'superseded_entry_id', p_superseded_entry_id,
            'is_work_note', p_is_work_note
        )
    );

    return v_new_entry_id;
end;
$$;

-- Función: Compartir entrada con otra área (BV-4.3 y Ethos C3)
create or replace function public.fn_share_journal_entry(
    p_journal_entry_id uuid,
    p_to_area_id uuid,
    p_reason text
)
returns uuid
security definer
set search_path = public
language plpgsql as $$
declare
    v_entry record;
    v_user_id uuid;
    v_sharing_id uuid;
begin
    v_user_id := auth.uid();

    if p_reason is null or trim(p_reason) = '' then
        raise exception 'Violación de Ethos C3: Compartir un registro con otra área exige asentar un motivo explícito.';
    end if;

    select * into v_entry from public.journal_entry where id = p_journal_entry_id;
    if v_entry.id is null then
        raise exception 'Registro de bitácora no encontrado.';
    end if;

    if v_entry.area_id = p_to_area_id then
        raise exception 'El registro ya pertenece a esta área.';
    end if;

    -- Marcar entrada como compartida
    update public.journal_entry
    set visibility = 'shared'
    where id = p_journal_entry_id;

    -- Crear el sharing_event
    insert into public.sharing_event (
        organization_id,
        journal_entry_id,
        case_id,
        from_area_id,
        to_area_id,
        from_visibility,
        to_visibility,
        reason,
        shared_by_user_id,
        shared_at
    ) values (
        v_entry.organization_id,
        p_journal_entry_id,
        v_entry.case_id,
        v_entry.area_id,
        p_to_area_id,
        v_entry.visibility,
        'shared',
        p_reason,
        v_user_id,
        now()
    ) returning id into v_sharing_id;

    -- Auditoría
    insert into public.audit_event (
        organization_id,
        actor_user_id,
        action,
        table_name,
        record_id,
        case_id,
        new_values
    ) values (
        v_entry.organization_id,
        v_user_id,
        'SHARE',
        'sharing_event',
        v_sharing_id,
        v_entry.case_id,
        jsonb_build_object(
            'journal_entry_id', p_journal_entry_id,
            'from_area_id', v_entry.area_id,
            'to_area_id', p_to_area_id,
            'reason', p_reason
        )
    );

    return v_sharing_id;
end;
$$;

-- Función: Acuse de recibo directivo de compartición (BV-4.4)
create or replace function public.fn_acknowledge_sharing(
    p_sharing_event_id uuid
)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_user_id uuid;
    v_org_id uuid;
begin
    v_user_id := auth.uid();

    -- Solo director puede acusar recibo del digest
    if not public.has_role('director') then
        raise exception 'Permiso denegado: El acuse de recibo de alertas directivas está reservado a roles de dirección.';
    end if;

    select organization_id into v_org_id from public.sharing_event where id = p_sharing_event_id;
    if v_org_id is null then
        raise exception 'Evento de compartición no encontrado.';
    end if;

    update public.sharing_event
    set acknowledged_by_user_id = v_user_id,
        acknowledged_at = now()
    where id = p_sharing_event_id and acknowledged_at is null;

    -- Auditoría
    insert into public.audit_event (
        organization_id,
        actor_user_id,
        action,
        table_name,
        record_id,
        new_values
    ) values (
        v_org_id,
        v_user_id,
        'ACKNOWLEDGE',
        'sharing_event',
        p_sharing_event_id,
        jsonb_build_object(
            'acknowledged_at', now()
        )
    );
end;
$$;

-- ==============================================================================
-- 6. Seguridad por Fila (Row Level Security - RLS)
-- ==============================================================================

alter table public.journal_entry enable row level security;
alter table public.sharing_event enable row level security;
alter table public.attachment enable row level security;

-- Política SELECT journal_entry:
-- 1) Director ve todo en su org.
-- 2) Caseworker/intake ven entradas de su área asignada.
-- 3) O entradas 'shared' si pertenecen al área receptora del sharing_event o son públicas al albergue.
create policy "journal_entry_select_policy" on public.journal_entry
    for select using (
        public.has_role('director') or
        author_user_id = auth.uid() or
        (
            area_id in (
                select area_id from public.user_role 
                where user_id = auth.uid() and revoked_at is null and area_id is not null
            )
        ) or
        (
            visibility = 'shared' and (
                exists (
                    select 1 from public.sharing_event se
                    where se.journal_entry_id = public.journal_entry.id
                      and se.to_area_id in (
                          select area_id from public.user_role 
                          where user_id = auth.uid() and revoked_at is null and area_id is not null
                      )
                )
            )
        )
    );

-- Política INSERT journal_entry:
create policy "journal_entry_insert_policy" on public.journal_entry
    for insert with check (
        public.has_role('director') or
        public.has_role('caseworker') or
        public.has_role('intake_officer')
    );

-- Política SELECT sharing_event:
create policy "sharing_event_select_policy" on public.sharing_event
    for select using (
        public.has_role('director') or
        from_area_id in (
            select area_id from public.user_role 
            where user_id = auth.uid() and revoked_at is null and area_id is not null
        ) or
        to_area_id in (
            select area_id from public.user_role 
            where user_id = auth.uid() and revoked_at is null and area_id is not null
        )
    );

-- Política SELECT attachment:
create policy "attachment_select_policy" on public.attachment
    for select using (
        public.has_role('director') or
        uploaded_by = auth.uid() or
        exists (
            select 1 from public.journal_entry je
            where je.id = public.attachment.journal_entry_id
              and (je.visibility = 'shared' or je.author_user_id = auth.uid())
        )
    );
