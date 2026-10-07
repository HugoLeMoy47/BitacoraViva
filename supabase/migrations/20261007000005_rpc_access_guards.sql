-- ==============================================================================
-- Funciones security definer: repetir la regla de acceso (Regla Dura 1)
--
-- Hallazgo (pruebas negativas, supabase/tests/rls_negative.sql): las funciones de
-- escritura se ejecutan con los privilegios del propietario y se saltan RLS, pero no
-- repetian la regla de acceso. Con solo la clave publica anon (sin sesion) se podia
-- cambiar el estatus de cualquier expediente y registrar consentimientos; un viewer
-- ademas podia crear bitacora y aclaraciones; y un director de OTRA organizacion
-- podia escribir sobre expedientes ajenos.
--
-- Correccion en dos capas:
--  1. EXECUTE: ninguna funcion fn_* es ejecutable por anon ni PUBLIC (solo
--     authenticated). Excepcion: fn_app_environment, que el login necesita.
--  2. Cada funcion de escritura exige sesion, rol operativo vigente
--     (director, intake_officer o caseworker: los mismos que las politicas INSERT)
--     y que el registro sea de la organizacion de quien llama.
-- La logica de cada funcion no cambia; solo se antepone la comprobacion. Ademas,
-- fn_register_consent deja de atribuir a un director fijo cuando no hay sesion.
-- ==============================================================================

create or replace function public.fn_assert_same_org(p_table text, p_id uuid)
returns void
stable
security definer
set search_path = public
language plpgsql as $$
declare
    v_org uuid;
begin
    if p_table not in ('person', 'case', 'journal_entry') then
        raise exception 'Tabla no admitida para la comprobación de organización.';
    end if;
    execute format('select organization_id from public.%I where id = $1', p_table) into v_org using p_id;
    -- Mismo mensaje si no existe o es ajeno: no se revela la existencia de registros de otra organización.
    if v_org is null or v_org is distinct from public.current_organization_id() then
        raise exception 'Registro no encontrado.';
    end if;
end;
$$;

CREATE OR REPLACE FUNCTION public.fn_change_case_status(p_case_id uuid, p_axis_code text, p_new_value_code text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

    -- Regla Dura 1: la función repite la regla de acceso (se ejecuta saltándose RLS)
    if auth.uid() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: se requiere una sesión con rol operativo vigente.';
    end if;
    perform public.fn_assert_same_org('case', p_case_id);
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
$function$;

CREATE OR REPLACE FUNCTION public.fn_create_clarification_note(p_superseded_entry_id uuid, p_body text, p_occurred_at timestamp with time zone DEFAULT now(), p_is_work_note boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_old_entry record;
    v_user_id uuid;
    v_new_entry_id uuid;
begin

    -- Regla Dura 1: la función repite la regla de acceso (se ejecuta saltándose RLS)
    if auth.uid() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: se requiere una sesión con rol operativo vigente.';
    end if;
    perform public.fn_assert_same_org('journal_entry', p_superseded_entry_id);
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
$function$;

CREATE OR REPLACE FUNCTION public.fn_create_journal_entry(p_case_id uuid, p_entry_type_key text, p_body text, p_occurred_at timestamp with time zone DEFAULT now(), p_is_work_note boolean DEFAULT false, p_area_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_user_id uuid;
    v_org_id uuid;
    v_area_id uuid;
    v_new_entry_id uuid;
begin

    -- Regla Dura 1: la función repite la regla de acceso (se ejecuta saltándose RLS)
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
$function$;

CREATE OR REPLACE FUNCTION public.fn_register_consent(p_person_id uuid, p_consent_type text, p_status text DEFAULT 'granted'::text, p_case_id uuid DEFAULT NULL::uuid, p_is_minor_assent boolean DEFAULT false, p_legal_guardian_name text DEFAULT NULL::text, p_legal_guardian_role text DEFAULT NULL::text, p_authority_letter_ref text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
    v_org_id uuid;
    v_user_id uuid := auth.uid();
    v_notice_id uuid;
    v_consent_id uuid;
begin

    -- Regla Dura 1: la función repite la regla de acceso (se ejecuta saltándose RLS)
    if auth.uid() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: se requiere una sesión con rol operativo vigente.';
    end if;
    perform public.fn_assert_same_org('person', p_person_id);
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
        p_authority_letter_ref, now(), v_user_id, p_notes
    ) returning id into v_consent_id;

    return v_consent_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_share_journal_entry(p_journal_entry_id uuid, p_to_area_id uuid, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_entry record;
    v_user_id uuid;
    v_sharing_id uuid;
begin

    -- Regla Dura 1: la función repite la regla de acceso (se ejecuta saltándose RLS)
    if auth.uid() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: se requiere una sesión con rol operativo vigente.';
    end if;
    perform public.fn_assert_same_org('journal_entry', p_journal_entry_id);
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
$function$;

-- Capa 1: EXECUTE solo para authenticated (fn_app_environment queda abierta a anon)
do $$
declare
    f record;
begin
    for f in
        select p.oid::regprocedure as sig
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname like 'fn\_%' and p.proname <> 'fn_app_environment'
    loop
        execute format('revoke execute on function %s from public, anon', f.sig);
        execute format('grant execute on function %s to authenticated', f.sig);
    end loop;
end $$;

-- Las funciones nuevas tampoco nacen ejecutables por anon
alter default privileges for role postgres in schema public revoke execute on functions from public, anon;
