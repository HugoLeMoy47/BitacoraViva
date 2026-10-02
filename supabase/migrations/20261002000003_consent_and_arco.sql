-- ==============================================================================
-- Bitácora Viva — Migración 000004: Épica E5
-- Consentimiento Informado, Aviso de Privacidad y Derechos ARCO
-- Fuente de verdad: 50_Productos/BitacoraViva/20_arquitectura/privacidad-y-cumplimiento.md
-- Normas: Ethos C1, C2, C4, C7, E-02, E-05; ADR-0001; Reglas Duras 1-7 y 10 de Supabase
-- ==============================================================================

-- 1. Tabla: privacy_notice (Aviso de Privacidad versionado por organización - P-13)
create table if not exists public.privacy_notice (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    version text not null,
    title text not null,
    summary text not null,
    full_text text not null,
    effective_date date not null default current_date,
    active boolean not null default true,
    created_at timestamptz not null default now(),
    unique (organization_id, version)
);

-- 2. Tabla: consent (Consentimiento informado general, expreso para datos sensibles y oposición)
create table if not exists public.consent (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    person_id uuid not null references public.person(id) on delete cascade,
    case_id uuid references public.case(id) on delete set null,
    privacy_notice_id uuid references public.privacy_notice(id),
    consent_type text not null check (consent_type in (
        'general_care',          -- Tratamiento general de datos para auxilio humanitario y alojamiento
        'sensitive_data',        -- Consentimiento expreso e informado para datos sensibles (salud, violencia, migración)
        'internal_sharing',      -- Autorización de compartición profesional entre áreas internas del albergue
        'secondary_use_research' -- Autorización para inclusión en reportes estadísticos agregados y memoria histórica
    )),
    status text not null default 'granted' check (status in ('granted', 'revoked', 'opposed')),
    -- Salvaguardas para Niñez Migrante No Acompañada (BV-5.1)
    is_minor_assent boolean not null default false,
    legal_guardian_name text,
    legal_guardian_role text,
    authority_letter_ref text,
    granted_at timestamptz not null default now(),
    granted_by_user_id uuid not null references public.user_profile(id),
    revoked_at timestamptz,
    revoked_by_user_id uuid references public.user_profile(id),
    revocation_reason text,
    notes text,
    created_at timestamptz not null default now()
);

-- 3. Tabla: arco_request (Registro formal de solicitudes ARCO - BV-5.1 a BV-5.5)
create table if not exists public.arco_request (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    person_id uuid not null references public.person(id) on delete restrict,
    case_id uuid references public.case(id) on delete set null,
    request_type text not null check (request_type in ('access', 'rectification', 'cancellation', 'opposition')),
    status text not null default 'pending' check (status in ('pending', 'approved_executed', 'rejected')),
    details text not null,
    reason text not null, -- Motivo obligatorio (Ethos C8)
    requested_by_name text not null,
    is_legal_representative boolean not null default false,
    representative_relationship text,
    received_at timestamptz not null default now(),
    handled_by_user_id uuid references public.user_profile(id),
    resolved_at timestamptz,
    resolution_notes text,
    created_at timestamptz not null default now()
);

-- Índices de alto rendimiento
create index if not exists idx_privacy_notice_org on public.privacy_notice (organization_id, active);
create index if not exists idx_consent_person on public.consent (person_id, consent_type, status);
create index if not exists idx_consent_org on public.consent (organization_id);
create index if not exists idx_arco_request_person on public.arco_request (person_id);
create index if not exists idx_arco_request_org_status on public.arco_request (organization_id, status);

-- ==============================================================================
-- 4. Invariantes de Seguridad e Integridad (Reglas Duras 2 y 3)
-- ==============================================================================

-- Revocar privilegio DELETE
revoke delete on public.privacy_notice from authenticated;
revoke delete on public.consent from authenticated;
revoke delete on public.arco_request from authenticated;

-- Disparador: Prohibir DELETE en privacy_notice, consent y arco_request
create or replace function public.fn_prevent_delete_arco()
returns trigger as $$
begin
    raise exception 'Violación de integridad: Los registros de consentimiento y solicitudes ARCO son inmutables; no se permite su eliminación (Reglas Duras 2 y 3 / Ethos C7).';
end;
$$ language plpgsql;

drop trigger if exists trg_prevent_delete_privacy_notice on public.privacy_notice;
create trigger trg_prevent_delete_privacy_notice
before delete on public.privacy_notice
for each row execute function public.fn_prevent_delete_arco();

drop trigger if exists trg_prevent_delete_consent on public.consent;
create trigger trg_prevent_delete_consent
before delete on public.consent
for each row execute function public.fn_prevent_delete_arco();

drop trigger if exists trg_prevent_delete_arco_request on public.arco_request;
create trigger trg_prevent_delete_arco_request
before delete on public.arco_request
for each row execute function public.fn_prevent_delete_arco();

-- Disparadores de Auditoría Inmutable (Regla Dura 4)
drop trigger if exists trg_audit_consent on public.consent;
create trigger trg_audit_consent
after insert or update on public.consent
for each row execute function public.fn_audit_log();

drop trigger if exists trg_audit_arco_request on public.arco_request;
create trigger trg_audit_arco_request
after insert or update on public.arco_request
for each row execute function public.fn_audit_log();

-- ==============================================================================
-- 5. Actualización del disparador de journal_entry para permitir purga por anonimización
-- ==============================================================================
create or replace function public.fn_prevent_update_journal_entry()
returns trigger as $$
begin
    -- 1) Permitir purga estricta por ejercicio de derecho ARCO de cancelación (ADR-0001)
    if new.body = '[CONTENIDO SUPRIMIDO POR EJERCICIO DE DERECHO ARCO DE CANCELACIÓN - ADR-0001]' then
        if not public.has_role('director') then
            raise exception 'Violación de seguridad: La purga por anonimización de bitácora está reservada exclusivamente al rol director (ADR-0001).';
        end if;
        return new;
    end if;

    -- 2) Prevenir alteración del cuerpo original o metadatos de autoría
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

    return new;
end;
$$ language plpgsql;

-- ==============================================================================
-- 6. Procedimientos Transaccionales de Derechos ARCO
-- ==============================================================================

-- A. Procedimiento: Registrar Consentimiento Informado (BV-5.1)
create or replace function public.fn_register_consent(
    p_person_id uuid,
    p_consent_type text,
    p_status text default 'granted',
    p_case_id uuid default null,
    p_is_minor_assent boolean default false,
    p_legal_guardian_name text default null,
    p_legal_guardian_role text default null,
    p_authority_letter_ref text default null,
    p_notes text default null
)
returns uuid as $$
declare
    v_org_id uuid;
    v_user_id uuid := auth.uid();
    v_notice_id uuid;
    v_consent_id uuid;
begin
    -- Obtener organización de la persona
    select organization_id into v_org_id from public.person where id = p_person_id;
    if v_org_id is null then
        raise exception 'Persona no encontrada.';
    end if;

    -- Obtener aviso de privacidad activo
    select id into v_notice_id 
    from public.privacy_notice 
    where organization_id = v_org_id and active = true 
    order by effective_date desc limit 1;

    insert into public.consent (
        organization_id, person_id, case_id, privacy_notice_id, consent_type,
        status, is_minor_assent, legal_guardian_name, legal_guardian_role,
        authority_letter_ref, granted_at, granted_by_user_id, notes
    ) values (
        v_org_id, p_person_id, p_case_id, v_notice_id, p_consent_type,
        p_status, p_is_minor_assent, p_legal_guardian_name, p_legal_guardian_role,
        p_authority_letter_ref, now(), coalesce(v_user_id, 'a0000000-0000-0000-0000-000000000001'::uuid), p_notes
    ) returning id into v_consent_id;

    return v_consent_id;
end;
$$ language plpgsql security definer;

-- B. Procedimiento: Rectificación Biográfica con Trazabilidad (BV-5.4)
create or replace function public.fn_rectify_person(
    p_person_id uuid,
    p_given_name text,
    p_paternal_family_name text,
    p_maternal_family_name text,
    p_preferred_name text,
    p_birth_date date,
    p_birth_date_is_estimated boolean,
    p_sex_id int,
    p_nationality_country_id int,
    p_phone_number text,
    p_email text,
    p_reason text
)
returns void as $$
declare
    v_person record;
    v_user_id uuid := auth.uid();
begin
    if not (public.has_role('director') or public.has_role('intake_officer')) then
        raise exception 'Acceso denegado: La rectificación de datos biográficos está reservada a dirección o personal de ingreso (BV-5.4).';
    end if;

    if p_reason is null or trim(p_reason) = '' then
        raise exception 'El motivo de rectificación es obligatorio e ineludible (Ethos C8).';
    end if;

    select * into v_person from public.person where id = p_person_id;
    if v_person is null then
        raise exception 'Persona no encontrada.';
    end if;

    if v_person.is_anonymized then
        raise exception 'Operación no permitida: Una persona anonimizada no admite rectificación (ADR-0001).';
    end if;

    -- Actualización de la persona
    update public.person
    set given_name = trim(p_given_name),
        paternal_family_name = trim(p_paternal_family_name),
        maternal_family_name = nullif(trim(p_maternal_family_name), ''),
        preferred_name = nullif(trim(p_preferred_name), ''),
        birth_date = p_birth_date,
        birth_date_is_estimated = p_birth_date_is_estimated,
        sex_id = p_sex_id,
        nationality_country_id = p_nationality_country_id,
        phone_number = nullif(trim(p_phone_number), ''),
        email = nullif(trim(p_email), ''),
        updated_at = now()
    where id = p_person_id;

    -- Registro en audit_event
    insert into public.audit_event (
        organization_id, user_id, action, table_name, record_id,
        old_values, new_values
    ) values (
        v_person.organization_id,
        v_user_id,
        'RECTIFICATION',
        'person',
        p_person_id,
        to_jsonb(v_person),
        jsonb_build_object(
            'given_name', trim(p_given_name),
            'paternal_family_name', trim(p_paternal_family_name),
            'maternal_family_name', trim(p_maternal_family_name),
            'preferred_name', trim(p_preferred_name),
            'birth_date', p_birth_date,
            'reason', p_reason
        )
    );
end;
$$ language plpgsql security definer;

-- C. Procedimiento: Cancelación por Supresión mediante Anonimización Irreversible (ADR-0001 / BV-5.3)
create or replace function public.fn_anonymize_person(
    p_person_id uuid,
    p_reason text
)
returns void as $$
declare
    v_person record;
    v_user_id uuid := auth.uid();
    v_case record;
    v_org_id uuid;
begin
    -- Exclusivo rol director (ADR-0001 / BV-5.3)
    if not public.has_role('director') then
        raise exception 'Acceso denegado: La anonimización irreversible está reservada exclusivamente al rol director (ADR-0001).';
    end if;

    if p_reason is null or trim(p_reason) = '' then
        raise exception 'El motivo de anonimización es obligatorio e ineludible (Ethos C8 / ADR-0001).';
    end if;

    select * into v_person from public.person where id = p_person_id;
    if v_person is null then
        raise exception 'Persona no encontrada.';
    end if;

    if v_person.is_anonymized then
        raise exception 'La persona ya se encuentra anonimizada.';
    end if;

    v_org_id := v_person.organization_id;

    -- 1. Destrucción de identificadores directos en public.person preservando esqueleto estadístico
    update public.person
    set given_name = 'PERSONA ANONIMIZADA',
        paternal_family_name = 'SUPRIMIDO',
        maternal_family_name = null,
        preferred_name = null,
        phone_number = null,
        email = null,
        address_line = null,
        neighborhood = null,
        postal_code = null,
        other_language = null,
        other_profile = null,
        other_sex = null,
        other_nationality = null,
        birth_date_is_estimated = true,
        is_anonymized = true,
        anonymized_at = now(),
        anonymized_by = v_user_id,
        updated_at = now()
    where id = p_person_id;

    -- 2. Transición de todos los casos asociados a estatus 'anonymized' terminal
    for v_case in select id from public.case where titular_person_id = p_person_id loop
        -- Eje engagement_status -> anonymized
        perform public.fn_change_case_status(
            v_case.id,
            'engagement_status',
            'anonymized',
            'Cancelación y supresión de datos por ejercicio de derecho ARCO (ADR-0001).'
        );
        -- Eje record_status -> anonymized
        perform public.fn_change_case_status(
            v_case.id,
            'record_status',
            'anonymized',
            'Cierre definitivo y anonimización de expediente (ADR-0001).'
        );

        -- 3. Purga del cuerpo de entradas de bitácora preservando metadatos de actuación
        update public.journal_entry
        set body = '[CONTENIDO SUPRIMIDO POR EJERCICIO DE DERECHO ARCO DE CANCELACIÓN - ADR-0001]'
        where case_id = v_case.id;

        -- 4. Purga de evidencias adjuntas
        delete from public.attachment where case_id = v_case.id;
    end loop;

    -- 5. Registro perpetuo en audit_event (nunca se purga - ADR-0001)
    insert into public.audit_event (
        organization_id, user_id, action, table_name, record_id,
        new_values
    ) values (
        v_org_id,
        v_user_id,
        'ANONYMIZATION',
        'person',
        p_person_id,
        jsonb_build_object(
            'reason', p_reason,
            'executed_at', now(),
            'executed_by', v_user_id,
            'retained_skeleton', jsonb_build_object(
                'sex_id', v_person.sex_id,
                'nationality_country_id', v_person.nationality_country_id,
                'primary_language_id', v_person.primary_language_id,
                'birth_year', extract(year from v_person.birth_date),
                'is_self_identified_migrant', v_person.is_self_identified_migrant
            )
        )
    );
end;
$$ language plpgsql security definer;

-- D. Procedimiento: Oposición a Tratamientos Secundarios (BV-5.5)
create or replace function public.fn_apply_opposition(
    p_person_id uuid,
    p_reason text
)
returns void as $$
declare
    v_org_id uuid;
    v_user_id uuid := auth.uid();
begin
    if not public.has_role('director') then
        raise exception 'Acceso denegado: El registro formal de oposición está reservado a dirección (BV-5.5).';
    end if;

    if p_reason is null or trim(p_reason) = '' then
        raise exception 'El motivo de oposición es obligatorio e ineludible (Ethos C8).';
    end if;

    select organization_id into v_org_id from public.person where id = p_person_id;
    if v_org_id is null then
        raise exception 'Persona no encontrada.';
    end if;

    -- Insertar o actualizar consentimiento con estatus opposed para uso secundario
    insert into public.consent (
        organization_id, person_id, consent_type, status,
        granted_at, granted_by_user_id, notes
    ) values (
        v_org_id, p_person_id, 'secondary_use_research', 'opposed',
        now(), coalesce(v_user_id, 'a0000000-0000-0000-0000-000000000001'::uuid),
        concat('Oposición registrada formalmente: ', p_reason)
    );

    -- Auditoría
    insert into public.audit_event (
        organization_id, user_id, action, table_name, record_id,
        new_values
    ) values (
        v_org_id,
        v_user_id,
        'OPPOSITION',
        'person',
        p_person_id,
        jsonb_build_object(
            'scope', 'secondary_use_research',
            'reason', p_reason,
            'timestamp', now()
        )
    );
end;
$$ language plpgsql security definer;

-- E. Función: Generar Extracto Estructurado de Acceso ARCO (BV-5.2 / Ethos E-02)
create or replace function public.fn_generate_arco_access_extract(
    p_person_id uuid
)
returns jsonb as $$
declare
    v_person record;
    v_cases jsonb;
    v_entries jsonb;
    v_consents jsonb;
    v_result jsonb;
    v_user_id uuid := auth.uid();
begin
    -- Exclusivo rol director (BV-5.2)
    if not public.has_role('director') then
        raise exception 'Acceso denegado: La emisión de extractos formales ARCO está reservada a dirección (BV-5.2).';
    end if;

    select * into v_person from public.person where id = p_person_id;
    if v_person is null then
        raise exception 'Persona no encontrada.';
    end if;

    -- Obtener expedientes y sus estatus vigentes
    select coalesce(jsonb_agg(jsonb_build_object(
        'case_number', c.case_number,
        'opened_at', c.opened_at,
        'travels_with_family', c.travels_with_family,
        'parent_case_id', c.parent_case_id
    )), '[]'::jsonb) into v_cases
    from public.case c where c.titular_person_id = p_person_id;

    -- Obtener entradas de bitácora EXCLUYENDO notas de trabajo protegidas (is_work_note = false por Ethos E-02 / MD-04)
    select coalesce(jsonb_agg(jsonb_build_object(
        'case_id', je.case_id,
        'entry_type_key', je.entry_type_key,
        'body', je.body,
        'occurred_at', je.occurred_at,
        'created_at', je.created_at,
        'area_name', a.name
    ) order by je.occurred_at asc), '[]'::jsonb) into v_entries
    from public.journal_entry je
    join public.area a on a.id = je.area_id
    where je.case_id in (select id from public.case where titular_person_id = p_person_id)
      and je.is_work_note = false; -- Frontera ética estricta Ethos E-02

    -- Obtener consentimientos vigentes
    select coalesce(jsonb_agg(jsonb_build_object(
        'consent_type', c.consent_type,
        'status', c.status,
        'granted_at', c.granted_at,
        'is_minor_assent', c.is_minor_assent,
        'legal_guardian_name', c.legal_guardian_name
    )), '[]'::jsonb) into v_consents
    from public.consent c where c.person_id = p_person_id;

    v_result := jsonb_build_object(
        'extract_generated_at', now(),
        'person', jsonb_build_object(
            'id', v_person.id,
            'given_name', v_person.given_name,
            'paternal_family_name', v_person.paternal_family_name,
            'maternal_family_name', v_person.maternal_family_name,
            'preferred_name', v_person.preferred_name,
            'birth_date', v_person.birth_date,
            'phone_number', v_person.phone_number,
            'is_anonymized', v_person.is_anonymized
        ),
        'cases', v_cases,
        'journal_entries', v_entries,
        'consents', v_consents
    );

    -- Auditoría obligatoria de emisión de extracto ARCO
    insert into public.audit_event (
        organization_id, user_id, action, table_name, record_id,
        new_values
    ) values (
        v_person.organization_id,
        v_user_id,
        'ARCO_ACCESS_EXTRACT_ISSUED',
        'person',
        p_person_id,
        jsonb_build_object('emitted_at', now(), 'issued_to', v_person.given_name)
    );

    return v_result;
end;
$$ language plpgsql security definer;

-- ==============================================================================
-- 7. Políticas de Seguridad de Fila (RLS) - Regla Dura 1
-- ==============================================================================

alter table public.privacy_notice enable row level security;
alter table public.consent enable row level security;
alter table public.arco_request enable row level security;

-- Políticas: privacy_notice
create policy "privacy_notice_select_policy"
    on public.privacy_notice for select to authenticated
    using (true);

create policy "privacy_notice_insert_policy"
    on public.privacy_notice for insert to authenticated
    with check (public.has_role('director'));

create policy "privacy_notice_update_policy"
    on public.privacy_notice for update to authenticated
    using (public.has_role('director'))
    with check (public.has_role('director'));

-- Políticas: consent
create policy "consent_select_policy"
    on public.consent for select to authenticated
    using (true);

create policy "consent_insert_policy"
    on public.consent for insert to authenticated
    with check (
        public.has_role('director') or 
        public.has_role('intake_officer') or 
        public.has_role('caseworker')
    );

create policy "consent_update_policy"
    on public.consent for update to authenticated
    using (public.has_role('director') or public.has_role('intake_officer'))
    with check (public.has_role('director') or public.has_role('intake_officer'));

-- Políticas: arco_request
create policy "arco_request_select_policy"
    on public.arco_request for select to authenticated
    using (public.has_role('director') or public.has_role('intake_officer'));

create policy "arco_request_insert_policy"
    on public.arco_request for insert to authenticated
    with check (public.has_role('director') or public.has_role('intake_officer'));

create policy "arco_request_update_policy"
    on public.arco_request for update to authenticated
    using (public.has_role('director'))
    with check (public.has_role('director'));
