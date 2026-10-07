-- ==============================================================================
-- Correccion de escrituras a audit_event (defecto detectado al conectar el frontend)
--
-- 1. El CHECK de audit_event.action solo admitia 6 valores, pero las funciones de
--    E4 y E5 asientan SHARE, ACKNOWLEDGE, CLARIFICATION, RECTIFICATION,
--    ANONYMIZATION, OPPOSITION y ARCO_ACCESS_EXTRACT_ISSUED. Toda esa operacion
--    fallaba y hacia rollback, sin dejar rastro.
-- 2. Las funciones de bitacora insertaban en columnas inexistentes
--    (actor_user_id, case_id). La columna real es user_id y el expediente se
--    asienta dentro de new_values, sin cambiar el esquema de la tabla.
-- Las funciones conservan su logica y firma; solo cambia la sentencia de auditoria.
-- ==============================================================================

alter table public.audit_event drop constraint if exists audit_event_action_check;
alter table public.audit_event add constraint audit_event_action_check check (action in (
    'INSERT', 'UPDATE', 'DELETE', 'LOGIN', 'EXPORT', 'STATUS_CHANGE',
    'CLARIFICATION', 'SHARE', 'ACKNOWLEDGE',
    'RECTIFICATION', 'ANONYMIZATION', 'OPPOSITION',
    'CONSENT_GRANTED', 'CONSENT_REVOKED', 'ARCO_ACCESS_EXTRACT_ISSUED'
));

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

    select organization_id into v_org_id from public.case where id = p_case_id;
    if v_org_id is null then
        raise exception 'Expediente no encontrado.';
    end if;

    if p_area_id is not null then
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

    insert into public.audit_event (
        organization_id, user_id, action, table_name, record_id, new_values
    ) values (
        v_org_id, v_user_id, 'INSERT', 'journal_entry', v_new_entry_id,
        jsonb_build_object(
            'case_id', p_case_id,
            'entry_type_key', p_entry_type_key,
            'is_work_note', p_is_work_note,
            'area_id', v_area_id,
            'occurred_at', p_occurred_at
        )
    );

    return v_new_entry_id;
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

    insert into public.journal_entry (
        organization_id, case_id, area_id, author_user_id, entry_type_key,
        body, is_work_note, occurred_at, created_at, visibility
    ) values (
        v_old_entry.organization_id, v_old_entry.case_id, v_old_entry.area_id, v_user_id,
        v_old_entry.entry_type_key, p_body, p_is_work_note,
        coalesce(p_occurred_at, now()), now(), v_old_entry.visibility
    ) returning id into v_new_entry_id;

    update public.journal_entry
    set superseded_by_id = v_new_entry_id
    where id = p_superseded_entry_id;

    insert into public.audit_event (
        organization_id, user_id, action, table_name, record_id, new_values
    ) values (
        v_old_entry.organization_id, v_user_id, 'CLARIFICATION', 'journal_entry', v_new_entry_id,
        jsonb_build_object(
            'case_id', v_old_entry.case_id,
            'superseded_entry_id', p_superseded_entry_id,
            'is_work_note', p_is_work_note
        )
    );

    return v_new_entry_id;
end;
$$;

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

    insert into public.audit_event (
        organization_id, user_id, action, table_name, record_id, new_values
    ) values (
        v_entry.organization_id, v_user_id, 'SHARE', 'sharing_event', v_sharing_id,
        jsonb_build_object(
            'case_id', v_entry.case_id,
            'journal_entry_id', p_journal_entry_id,
            'from_area_id', v_entry.area_id,
            'to_area_id', p_to_area_id,
            'reason', p_reason
        )
    );

    return v_sharing_id;
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
    v_user_id uuid;
    v_org_id uuid;
begin
    v_user_id := auth.uid();

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

    insert into public.audit_event (
        organization_id, user_id, action, table_name, record_id, new_values
    ) values (
        v_org_id, v_user_id, 'ACKNOWLEDGE', 'sharing_event', p_sharing_event_id,
        jsonb_build_object('acknowledged_at', now())
    );
end;
$$;
