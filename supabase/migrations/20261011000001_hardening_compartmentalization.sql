-- ==============================================================================
-- Endurecimiento: compartimentación, organización en ARCO y auditoría sin datos
-- personales (Reglas Duras 1, 5 y 6; Ethos C2, C3, C4, C7)
--
-- Origen: auditoría del 11 oct 2026 (30_entrega/reporte-auditoria-endurecimiento-2026-10-11.md).
-- Decisiones del Product Owner (40_bitacora/decisiones.md, 11 oct 2026):
--   1. audit_event guarda solo el nombre de la tabla y los NOMBRES de los campos que
--      cambiaron; nunca valores personales.
--   2. Compartir o aclarar una entrada de bitácora: persona autora, personas del área de la
--      entrada y dirección. Las notas de trabajo protegidas no se comparten nunca.
--   3. «anonymized» solo se alcanza por fn_anonymize_person; reabrir un expediente cerrado
--      es exclusivo de director.
--
-- Qué corrige
--  C-1  Cinco funciones de ARCO/acuse no comprobaban la organización (security definer).
--  C-2  audit_event conservaba la fila completa de person, consent, arco_request,
--       user_profile y authority_request; la anonimización no podía borrarla (tabla inmutable).
--       La anonimización además conserva solo el año de nacimiento (ADR-0001).
--  A-2  Compartir, aclarar y escribir a nombre de un área no validaban autoría ni área.
--  A-3  anonymized y la reapertura no estaban restringidos.
--  M-1  Funciones security definer sin search_path fijo.
--
-- NO incluye A-1 (revocar INSERT/UPDATE directos en tablas del núcleo): queda para una
-- migración propia una vez confirmada por el Product Owner.
-- Los eventos de auditoría ya escritos son inmutables y no se tocan.
-- ==============================================================================


-- ------------------------------------------------------------------------------
-- 0. Comprobación de organización: también para compartición
-- ------------------------------------------------------------------------------
create or replace function public.fn_assert_same_org(p_table text, p_id uuid)
returns void
stable
security definer
set search_path = public
language plpgsql as $$
declare
    v_org uuid;
begin
    if p_table not in ('person', 'case', 'journal_entry', 'sharing_event') then
        raise exception 'Tabla no admitida para la comprobación de organización.';
    end if;
    execute format('select organization_id from public.%I where id = $1', p_table) into v_org using p_id;
    -- Mismo mensaje si no existe o es ajeno: no se revela la existencia de registros de otra organización.
    if v_org is null or v_org is distinct from public.current_organization_id() then
        raise exception 'Registro no encontrado.';
    end if;
end;
$$;


-- ------------------------------------------------------------------------------
-- 1. Auditoría que guarda solo nombres de campos (C-2)
-- ------------------------------------------------------------------------------
create or replace function public.fn_audit_trigger_fields()
returns trigger
security definer
set search_path = public
language plpgsql as $$
declare
    v_row jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
    v_old jsonb := case when tg_op = 'INSERT' then null else to_jsonb(old) end;
    v_fields jsonb;
    v_org uuid := nullif(v_row ->> 'organization_id', '')::uuid;
begin
    if v_org is null then
        return case when tg_op = 'DELETE' then old else new end;
    end if;

    -- INSERT: los campos con valor. UPDATE: los que cambiaron. Nunca el valor.
    select coalesce(jsonb_agg(e.key order by e.key), '[]'::jsonb) into v_fields
    from jsonb_each(v_row) e
    where e.key <> 'updated_at'
      and case tg_op
              when 'INSERT' then e.value <> 'null'::jsonb
              when 'UPDATE' then e.value is distinct from (v_old -> e.key)
              else true
          end;

    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_org, auth.uid(), tg_op, tg_table_name, nullif(v_row ->> 'id', '')::uuid,
            jsonb_build_object('changed_fields', v_fields));

    return case when tg_op = 'DELETE' then old else new end;
end;
$$;

do $$
declare
    t text;
begin
    foreach t in array array['person', 'consent', 'arco_request', 'user_profile', 'authority_request'] loop
        execute format('drop trigger if exists trg_audit_%s on public.%I', t, t);
        execute format('create trigger trg_audit_%s after insert or update on public.%I
                        for each row execute function public.fn_audit_trigger_fields()', t, t);
    end loop;
end $$;


-- ------------------------------------------------------------------------------
-- 2. Funciones de ARCO y acuse: sesión, organización y search_path (C-1, C-2, M-1)
-- ------------------------------------------------------------------------------
alter function public.fn_register_consent(uuid, text, text, uuid, boolean, text, text, text, text)
    set search_path = public;

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
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_person record;
    v_after record;
    v_changed jsonb;
    v_user_id uuid := auth.uid();
begin
    if v_user_id is null or not (public.has_role('director') or public.has_role('intake_officer')) then
        raise exception 'Acceso denegado: La rectificación de datos biográficos está reservada a dirección o personal de ingreso (BV-5.4).';
    end if;
    perform public.fn_assert_same_org('person', p_person_id);

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

    select * into v_after from public.person where id = p_person_id;

    -- Decisión del PO (11 oct 2026): el log dice QUÉ campos cambiaron y por qué, nunca los valores.
    select coalesce(jsonb_agg(a.key order by a.key), '[]'::jsonb) into v_changed
    from jsonb_each(to_jsonb(v_after)) a
    where a.key <> 'updated_at' and a.value is distinct from (to_jsonb(v_person) -> a.key);

    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_person.organization_id, v_user_id, 'RECTIFICATION', 'person', p_person_id,
            jsonb_build_object('changed_fields', v_changed, 'reason', p_reason));
end;
$$;

create or replace function public.fn_anonymize_person(
    p_person_id uuid,
    p_reason text
)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_person record;
    v_user_id uuid := auth.uid();
    v_case record;
    v_org_id uuid;
begin
    -- Exclusivo rol director (ADR-0001 / BV-5.3)
    if v_user_id is null or not public.has_role('director') then
        raise exception 'Acceso denegado: La anonimización irreversible está reservada exclusivamente al rol director (ADR-0001).';
    end if;
    perform public.fn_assert_same_org('person', p_person_id);

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

    -- 1. Destrucción de identificadores directos preservando el esqueleto estadístico.
    --    La fecha de nacimiento se reduce al año (rango de edad, ADR-0001): la columna es NOT NULL.
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
        birth_date = make_date(extract(year from v_person.birth_date)::int, 1, 1),
        birth_date_is_estimated = true,
        is_anonymized = true,
        anonymized_at = now(),
        anonymized_by = v_user_id,
        updated_at = now()
    where id = p_person_id;

    -- 2. Estatus terminal 'anonymized'. Esta es la ÚNICA vía para alcanzarlo (A-3): la marca vale
    --    solo dentro de esta transacción y la lee fn_change_case_status.
    perform set_config('bv.anonymizing', 'on', true);
    for v_case in select id from public.case where titular_person_id = p_person_id loop
        perform public.fn_change_case_status(
            v_case.id, 'engagement_status', 'anonymized',
            'Cancelación y supresión de datos por ejercicio de derecho ARCO (ADR-0001).'
        );
        perform public.fn_change_case_status(
            v_case.id, 'record_status', 'anonymized',
            'Cierre definitivo y anonimización de expediente (ADR-0001).'
        );

        -- 3. Purga del cuerpo de entradas de bitácora preservando metadatos de actuación
        update public.journal_entry
        set body = '[CONTENIDO SUPRIMIDO POR EJERCICIO DE DERECHO ARCO DE CANCELACIÓN - ADR-0001]'
        where case_id = v_case.id;

        -- 4. Purga de evidencias adjuntas
        delete from public.attachment where case_id = v_case.id;
    end loop;
    perform set_config('bv.anonymizing', 'off', true);

    -- 5. Registro perpetuo (nunca se purga - ADR-0001): sin identificadores
    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_org_id, v_user_id, 'ANONYMIZATION', 'person', p_person_id,
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
        ));
end;
$$;

create or replace function public.fn_apply_opposition(
    p_person_id uuid,
    p_reason text
)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_org_id uuid;
    v_user_id uuid := auth.uid();
begin
    if v_user_id is null or not public.has_role('director') then
        raise exception 'Acceso denegado: El registro formal de oposición está reservado a dirección (BV-5.5).';
    end if;
    perform public.fn_assert_same_org('person', p_person_id);

    if p_reason is null or trim(p_reason) = '' then
        raise exception 'El motivo de oposición es obligatorio e ineludible (Ethos C8).';
    end if;

    select organization_id into v_org_id from public.person where id = p_person_id;
    if v_org_id is null then
        raise exception 'Persona no encontrada.';
    end if;

    -- Autoría siempre identificada (C4): ya no hay director sustituto cuando falta la sesión
    insert into public.consent (
        organization_id, person_id, consent_type, status, granted_at, granted_by_user_id, notes
    ) values (
        v_org_id, p_person_id, 'secondary_use_research', 'opposed', now(), v_user_id,
        concat('Oposición registrada formalmente: ', p_reason)
    );

    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_org_id, v_user_id, 'OPPOSITION', 'person', p_person_id,
        jsonb_build_object('scope', 'secondary_use_research', 'reason', p_reason, 'timestamp', now()));
end;
$$;

create or replace function public.fn_generate_arco_access_extract(
    p_person_id uuid
)
returns jsonb
security definer
set search_path = public
language plpgsql as $$
declare
    v_person record;
    v_cases jsonb;
    v_entries jsonb;
    v_consents jsonb;
    v_result jsonb;
    v_user_id uuid := auth.uid();
begin
    -- Exclusivo rol director (BV-5.2)
    if v_user_id is null or not public.has_role('director') then
        raise exception 'Acceso denegado: La emisión de extractos formales ARCO está reservada a dirección (BV-5.2).';
    end if;
    perform public.fn_assert_same_org('person', p_person_id);

    select * into v_person from public.person where id = p_person_id;
    if v_person is null then
        raise exception 'Persona no encontrada.';
    end if;

    select coalesce(jsonb_agg(jsonb_build_object(
        'case_number', c.case_number,
        'opened_at', c.opened_at,
        'travels_with_family', c.travels_with_family,
        'parent_case_id', c.parent_case_id
    )), '[]'::jsonb) into v_cases
    from public.case c where c.titular_person_id = p_person_id;

    -- Entradas de bitácora EXCLUYENDO notas de trabajo protegidas (Ethos E-02 / MD-04)
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
      and je.is_work_note = false;

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

    -- Auditoría obligatoria de emisión: la persona se identifica por record_id, no por su nombre
    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_person.organization_id, v_user_id, 'ARCO_ACCESS_EXTRACT_ISSUED', 'person', p_person_id,
            jsonb_build_object('emitted_at', now()));

    return v_result;
end;
$$;

create or replace function public.fn_acknowledge_sharing(
    p_sharing_event_id uuid
)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_user_id uuid := auth.uid();
    v_org_id uuid;
begin
    if v_user_id is null or not public.has_role('director') then
        raise exception 'Permiso denegado: El acuse de recibo de alertas directivas está reservado a roles de dirección.';
    end if;
    perform public.fn_assert_same_org('sharing_event', p_sharing_event_id);

    select organization_id into v_org_id from public.sharing_event where id = p_sharing_event_id;

    update public.sharing_event
    set acknowledged_by_user_id = v_user_id,
        acknowledged_at = now()
    where id = p_sharing_event_id and acknowledged_at is null;

    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_org_id, v_user_id, 'ACKNOWLEDGE', 'sharing_event', p_sharing_event_id,
            jsonb_build_object('acknowledged_at', now()));
end;
$$;


-- ------------------------------------------------------------------------------
-- 3. Bitácora: autoría, área y dirección (A-2); notas de trabajo sin compartir (E-02)
-- ------------------------------------------------------------------------------

-- ¿Puede quien llama actuar sobre esta entrada? Autoría, personas del área de la entrada y dirección.
create or replace function public.fn_can_act_on_entry(p_entry_id uuid)
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select auth.uid() is not null
       and public.has_operational_role()
       and exists (
            select 1 from public.journal_entry je
            where je.id = p_entry_id
              and je.organization_id = public.current_organization_id()
              and (
                    public.has_role('director')
                    or je.author_user_id = auth.uid()
                    or je.area_id in (
                        select ur.area_id from public.user_role ur
                        where ur.user_id = auth.uid() and ur.revoked_at is null and ur.area_id is not null
                    )
              )
       );
$$;

revoke execute on function public.fn_can_act_on_entry(uuid) from public, anon;
grant execute on function public.fn_can_act_on_entry(uuid) to authenticated;

create or replace function public.fn_share_journal_entry(p_journal_entry_id uuid, p_to_area_id uuid, p_reason text)
returns uuid
security definer
set search_path = public
language plpgsql as $$
declare
    v_entry record;
    v_user_id uuid;
    v_sharing_id uuid;
begin
    if auth.uid() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: se requiere una sesión con rol operativo vigente.';
    end if;
    perform public.fn_assert_same_org('journal_entry', p_journal_entry_id);
    v_user_id := auth.uid();

    if not public.fn_can_act_on_entry(p_journal_entry_id) then
        raise exception 'Permiso denegado: solo la persona autora, el área de la entrada o Dirección pueden compartirla (Ethos C3).';
    end if;

    if p_reason is null or trim(p_reason) = '' then
        raise exception 'Violación de Ethos C3: Compartir un registro con otra área exige asentar un motivo explícito.';
    end if;

    select * into v_entry from public.journal_entry where id = p_journal_entry_id;
    if v_entry.id is null then
        raise exception 'Registro de bitácora no encontrado.';
    end if;

    if v_entry.is_work_note then
        raise exception 'Violación de Ethos E-02: una nota de trabajo protegida no se comparte; solo la ven su autoría, su área y Dirección.';
    end if;

    if not exists (
        select 1 from public.area a
        where a.id = p_to_area_id and a.organization_id = v_entry.organization_id and a.active
    ) then
        raise exception 'Área destino no válida.';
    end if;

    if v_entry.area_id = p_to_area_id then
        raise exception 'El registro ya pertenece a esta área.';
    end if;

    update public.journal_entry
    set visibility = 'shared'
    where id = p_journal_entry_id;

    insert into public.sharing_event (
        organization_id, journal_entry_id, case_id, from_area_id, to_area_id,
        from_visibility, to_visibility, reason, shared_by_user_id, shared_at
    ) values (
        v_entry.organization_id, p_journal_entry_id, v_entry.case_id, v_entry.area_id, p_to_area_id,
        v_entry.visibility, 'shared', p_reason, v_user_id, now()
    ) returning id into v_sharing_id;

    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_entry.organization_id, v_user_id, 'SHARE', 'sharing_event', v_sharing_id,
        jsonb_build_object(
            'case_id', v_entry.case_id,
            'journal_entry_id', p_journal_entry_id,
            'from_area_id', v_entry.area_id,
            'to_area_id', p_to_area_id,
            'reason', p_reason
        ));

    return v_sharing_id;
end;
$$;

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
    v_work_note boolean;
begin
    if auth.uid() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: se requiere una sesión con rol operativo vigente.';
    end if;
    perform public.fn_assert_same_org('journal_entry', p_superseded_entry_id);
    v_user_id := auth.uid();

    if not public.fn_can_act_on_entry(p_superseded_entry_id) then
        raise exception 'Permiso denegado: solo la persona autora, el área de la entrada o Dirección pueden aclararla.';
    end if;

    if p_body is null or trim(p_body) = '' then
        raise exception 'El texto de la aclaración es obligatorio.';
    end if;

    select * into v_old_entry from public.journal_entry where id = p_superseded_entry_id;
    if v_old_entry.id is null then
        raise exception 'El registro de bitácora original a corregir no existe.';
    end if;

    if v_old_entry.superseded_by_id is not null then
        raise exception 'Este registro de bitácora ya ha sido superado por una aclaración previa.';
    end if;

    -- La aclaración de una nota de trabajo protegida es también nota de trabajo y nunca nace compartida (E-02)
    v_work_note := coalesce(p_is_work_note, false) or v_old_entry.is_work_note;

    insert into public.journal_entry (
        organization_id, case_id, area_id, author_user_id, entry_type_key,
        body, is_work_note, occurred_at, created_at, visibility
    ) values (
        v_old_entry.organization_id, v_old_entry.case_id, v_old_entry.area_id, v_user_id,
        v_old_entry.entry_type_key, p_body, v_work_note,
        coalesce(p_occurred_at, now()), now(),
        case when v_work_note then 'area_private' else v_old_entry.visibility end
    ) returning id into v_new_entry_id;

    update public.journal_entry
    set superseded_by_id = v_new_entry_id
    where id = p_superseded_entry_id;

    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_old_entry.organization_id, v_user_id, 'CLARIFICATION', 'journal_entry', v_new_entry_id,
        jsonb_build_object(
            'case_id', v_old_entry.case_id,
            'superseded_entry_id', p_superseded_entry_id,
            'is_work_note', v_work_note
        ));

    return v_new_entry_id;
end;
$$;

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
    v_area_code text;
begin
    if auth.uid() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: se requiere una sesión con rol operativo vigente.';
    end if;
    perform public.fn_assert_same_org('case', p_case_id);
    v_user_id := auth.uid();

    if p_body is null or trim(p_body) = '' then
        raise exception 'El texto de la intervención en bitácora es obligatorio.';
    end if;

    select organization_id into v_org_id from public.case where id = p_case_id;
    if v_org_id is null then
        raise exception 'Expediente no encontrado.';
    end if;

    if p_area_id is not null then
        -- Escribir a nombre de un área exige ser de esa área (o dirección) y que sea de la misma
        -- organización. Quien no tiene área asignada (ingreso) solo escribe en coordinación.
        select a.code into v_area_code
        from public.area a
        where a.id = p_area_id and a.organization_id = v_org_id and a.active;
        if v_area_code is null then
            raise exception 'Área no válida para esta organización.';
        end if;

        if not public.has_role('director') then
            if exists (
                select 1 from public.user_role ur
                where ur.user_id = v_user_id and ur.revoked_at is null and ur.area_id is not null
            ) then
                if not exists (
                    select 1 from public.user_role ur
                    where ur.user_id = v_user_id and ur.revoked_at is null and ur.area_id = p_area_id
                ) then
                    raise exception 'Permiso denegado: solo se escribe a nombre del propio área (Ethos C2, C4).';
                end if;
            elsif v_area_code <> 'coordinacion' then
                raise exception 'Permiso denegado: sin área asignada solo se escribe a nombre de coordinación.';
            end if;
        end if;
        v_area_id := p_area_id;
    else
        select area_id into v_area_id
        from public.user_role
        where user_id = v_user_id and revoked_at is null and area_id is not null
        limit 1;

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
        organization_id, case_id, area_id, author_user_id, entry_type_key,
        body, is_work_note, occurred_at, created_at, visibility
    ) values (
        v_org_id, p_case_id, v_area_id, v_user_id, p_entry_type_key,
        p_body, p_is_work_note, coalesce(p_occurred_at, now()), now(), 'area_private'
    ) returning id into v_new_entry_id;

    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_org_id, v_user_id, 'INSERT', 'journal_entry', v_new_entry_id,
        jsonb_build_object(
            'case_id', p_case_id,
            'entry_type_key', p_entry_type_key,
            'is_work_note', p_is_work_note,
            'area_id', v_area_id,
            'occurred_at', p_occurred_at
        ));

    return v_new_entry_id;
end;
$$;

-- La base impide que una nota de trabajo cambie de naturaleza o de visibilidad, venga de donde venga.
create or replace function public.fn_prevent_update_journal_entry()
returns trigger as $$
begin
    if old.is_work_note is distinct from new.is_work_note then
        raise exception 'Violación de Ethos E-02: una nota de trabajo protegida no deja de serlo (ni una entrada ordinaria pasa a serlo).';
    end if;
    if new.is_work_note and new.visibility is distinct from old.visibility then
        raise exception 'Violación de Ethos E-02: una nota de trabajo protegida no se comparte.';
    end if;

    -- Purga estricta por ejercicio de derecho ARCO de cancelación (ADR-0001)
    if new.body = '[CONTENIDO SUPRIMIDO POR EJERCICIO DE DERECHO ARCO DE CANCELACIÓN - ADR-0001]' then
        if not public.has_role('director') then
            raise exception 'Violación de seguridad: La purga por anonimización de bitácora está reservada exclusivamente al rol director (ADR-0001).';
        end if;
        return new;
    end if;

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

-- Una nota de trabajo nunca nace compartida (E-02), ni siquiera por una inserción directa
create or replace function public.fn_journal_work_note_born_private()
returns trigger as $$
begin
    if new.is_work_note and new.visibility is distinct from 'area_private' then
        raise exception 'Violación de Ethos E-02: una nota de trabajo protegida nace y permanece privada al área.';
    end if;
    return new;
end;
$$ language plpgsql;

drop trigger if exists trg_journal_work_note_born_private on public.journal_entry;
create trigger trg_journal_work_note_born_private
before insert on public.journal_entry
for each row execute function public.fn_journal_work_note_born_private();


-- ------------------------------------------------------------------------------
-- 4. Estatus: anonymized solo por la anonimización; reabrir, solo dirección (A-3)
-- ------------------------------------------------------------------------------
create or replace function public.fn_change_case_status(p_case_id uuid, p_axis_code text, p_new_value_code text, p_reason text)
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
    v_new_status_id uuid;
    v_user_id uuid;
begin
    if auth.uid() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: se requiere una sesión con rol operativo vigente.';
    end if;
    perform public.fn_assert_same_org('case', p_case_id);
    v_user_id := auth.uid();

    if p_reason is null or trim(p_reason) = '' then
        raise exception 'Violación de integridad: Todo cambio de estatus exige un motivo explícito en texto (reason).';
    end if;

    select organization_id into v_org_id from public.case where id = p_case_id;
    if v_org_id is null then
        raise exception 'Expediente no encontrado.';
    end if;

    -- Compartimentación por área (BV-2.3)
    if p_axis_code = 'legal_status' then
        if not (public.has_role('director') or public.has_role_in_area('caseworker', 'legal')) then
            raise exception 'Permiso denegado: El estatus jurídico solo puede ser modificado por Dirección o personal adscrito al Área Jurídica.';
        end if;
    end if;

    -- Cierre administrativo: facultad de Dirección
    if p_axis_code = 'record_status' and p_new_value_code = 'closed' then
        if not public.has_role('director') then
            raise exception 'Permiso denegado: El cierre administrativo del expediente es facultad exclusiva de Dirección.';
        end if;
    end if;

    -- «anonymized» (terminal, irreversible) solo se alcanza anonimizando a la persona (ADR-0001)
    if p_new_value_code = 'anonymized'
       and coalesce(current_setting('bv.anonymizing', true), '') <> 'on' then
        raise exception 'Violación de Ethos C7: el estatus «anonymized» solo se alcanza anonimizando a la persona (fn_anonymize_person).';
    end if;

    select id into v_axis_id from public.status_axis where organization_id = v_org_id and code = p_axis_code;
    if v_axis_id is null then
        raise exception 'Eje de estatus no válido para esta organización.';
    end if;

    select id into v_new_val_id
    from public.status_value
    where axis_id = v_axis_id and code = p_new_value_code;

    if v_new_val_id is null then
        raise exception 'Valor de estatus destino no encontrado en el catálogo.';
    end if;

    select cs.id, sv.code into v_old_status_id, v_old_val_code
    from public.case_status cs
    join public.status_value sv on sv.id = cs.value_id
    where cs.case_id = p_case_id and cs.axis_id = v_axis_id and cs.valid_to is null;

    if v_old_val_code = 'anonymized' then
        raise exception 'Violación de Ethos: Un expediente en estatus anonimizado es terminal e irreversible.';
    end if;

    -- Reapertura: salir de «cerrado» es facultad de Dirección (BV-2.3)
    if p_axis_code = 'record_status' and v_old_val_code = 'closed' and p_new_value_code <> 'closed' then
        if not public.has_role('director') then
            raise exception 'Permiso denegado: Reabrir un expediente cerrado es facultad exclusiva de Dirección.';
        end if;
    end if;

    -- Regla Dura 7: se cierra el vigente y se abre uno nuevo en la misma transacción
    if v_old_status_id is not null then
        update public.case_status
        set valid_to = now()
        where id = v_old_status_id;
    end if;

    insert into public.case_status (
        organization_id, case_id, axis_id, value_id, valid_from, valid_to, reason, created_by
    ) values (
        v_org_id, p_case_id, v_axis_id, v_new_val_id, now(), null, p_reason, v_user_id
    ) returning id into v_new_status_id;

    if p_axis_code = 'record_status' and p_new_value_code = 'closed' then
        update public.case
        set closed_at = now(), closed_by = v_user_id, closure_reason = p_reason
        where id = p_case_id;
    end if;

    return v_new_status_id;
end;
$$;


-- ------------------------------------------------------------------------------
-- 5. Permisos
--    CREATE OR REPLACE conserva los permisos de las funciones redefinidas. Las funciones de
--    disparador nuevas no son llamables por los roles de aplicación. (No se repite el bucle
--    «authenticated ejecuta todo fn_*» de la migración 000005: reabriría helpers cerrados a propósito,
--    como fn_metric_rows.)
-- ------------------------------------------------------------------------------
revoke execute on function public.fn_audit_trigger_fields() from public, anon, authenticated;
revoke execute on function public.fn_journal_work_note_born_private() from public, anon, authenticated;
