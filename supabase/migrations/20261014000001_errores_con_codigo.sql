-- ==============================================================================
-- E13 fase 1 · Errores de dominio con código estable
--
-- Hasta hoy la interfaz reconocía los errores de la base BUSCANDO PALABRAS EN ESPAÑOL dentro del mensaje, y esos
-- mensajes traían referencias internas («Ethos C8», «BV-5.1», «fn_anonymize_person») que llegaban a la pantalla.
-- Desde esta migración cada error de dominio de la base lleva un SQLSTATE propio de la plataforma, BVnnn:
--
--   BV1xx  sesión, rol y organización       BV4xx  consentimiento, privacidad y personas menores
--   BV2xx  algo no existe o es ajeno         BV5xx  estados y jerarquía
--   BV3xx  datos incompletos o inválidos     BV6xx  lo que nunca se edita ni se borra
--                                            BV7xx  técnicos (no deberían verse)
--
-- (Las tareas conservan sus TKnnn.) El mensaje en español NO cambia: queda como respaldo y para el registro
-- técnico; la interfaz traduce por código (src/locales/es.json, errors.db.bvnnn), y así el mismo error servirá
-- en cualquier idioma. La prueba «ninguna función vigente levanta un error sin código estable» impide que vuelva
-- a aparecer uno sin código (BV-13.2).
--
-- Generada de las definiciones vigentes (pg_get_functiondef): se reescribe cada función SIN tocar su lógica,
-- solo se añade `using errcode` a cada `raise exception`. 26 funciones, 78 códigos.
-- ==============================================================================

-- fn_acknowledge_sharing(uuid) · 1 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_acknowledge_sharing(p_sharing_event_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_user_id uuid := auth.uid();
    v_org_id uuid;
begin
    if v_user_id is null or not public.has_role('director') then
        raise exception 'Permiso denegado: El acuse de recibo de alertas directivas está reservado a roles de dirección.' using errcode = 'BV103';
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
$function$;

-- fn_aggregate_metrics(date,date) · 2 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_aggregate_metrics(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_org uuid := public.current_organization_id();
    v_min constant int := 5;
    v_exact boolean;
    v_len int;
    v_pf date;
    v_pt date;
    v_result jsonb;
begin
    if v_org is null or not public.has_any_role() then
        raise exception 'Acceso denegado: se requiere una sesión con rol vigente.' using errcode = 'BV101';
    end if;

    -- Cifras exactas para los roles operativos; redondeadas solo para el observador externo (R-19)
    v_exact := public.has_operational_role();

    if p_from is not null and p_to is not null then
        if p_from > p_to then
            raise exception 'El periodo es inválido: la fecha inicial es posterior a la final.' using errcode = 'BV301';
        end if;
        v_len := p_to - p_from + 1;
        v_pf := p_from - v_len;
        v_pt := p_from - 1;
    end if;

    with cur as (
        select * from public.fn_metric_rows_protected(v_org, p_from, p_to)
    ),
    prev as (
        select * from public.fn_metric_rows_protected(v_org, v_pf, v_pt) where v_pf is not null
    )
    select jsonb_build_object(
        'min_group_size', v_min,
        'exact', v_exact,
        'rounded_to', case when v_exact then null else 5 end,
        'generated_at', now(),
        'period', jsonb_build_object('from', p_from, 'to', p_to, 'prev_from', v_pf, 'prev_to', v_pt),
        'rows', coalesce(jsonb_agg(jsonb_build_object(
            'metric', c.metric,
            'bucket', c.bucket,
            'count', case when c.hidden is null
                          then (case when v_exact then c.n else ((c.n + 2) / 5) * 5 end) end,
            'value', case when c.hidden is null and c.metric = 'duration' then round(c.val, 1) end,
            'suppressed', c.hidden is not null,
            'hidden_reason', c.hidden,
            'prev_count', case when pr.n is not null and pr.hidden is null
                               then (case when v_exact then pr.n else ((pr.n + 2) / 5) * 5 end) end,
            'prev_value', case when pr.n is not null and pr.hidden is null and c.metric = 'duration'
                               then round(pr.val, 1) end
        ) order by c.metric,
                   (case when c.by_freq and c.hidden is null then -c.n else c.ord end),
                   c.bucket), '[]'::jsonb)
    ) into v_result
    from cur c
    left join prev pr on pr.metric = c.metric and pr.bucket = c.bucket;

    return v_result;
end;
$function$;

-- fn_anonymize_person(uuid,text) · 4 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_anonymize_person(p_person_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_person record;
    v_user_id uuid := auth.uid();
    v_case record;
    v_org_id uuid;
begin
    -- Exclusivo rol director (ADR-0001 / BV-5.3)
    if v_user_id is null or not public.has_role('director') then
        raise exception 'Acceso denegado: La anonimización irreversible está reservada exclusivamente al rol director (ADR-0001).' using errcode = 'BV104';
    end if;
    perform public.fn_assert_same_org('person', p_person_id);

    if p_reason is null or trim(p_reason) = '' then
        raise exception 'El motivo de anonimización es obligatorio e ineludible (Ethos C8 / ADR-0001).' using errcode = 'BV302';
    end if;

    select * into v_person from public.person where id = p_person_id;
    if v_person is null then
        raise exception 'Persona no encontrada.' using errcode = 'BV202';
    end if;

    if v_person.is_anonymized then
        raise exception 'La persona ya se encuentra anonimizada.' using errcode = 'BV501';
    end if;

    v_org_id := v_person.organization_id;

    -- 1. Destrucción de identificadores directos preservando el esqueleto estadístico.
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

    -- 2. Terceros en consentimientos y solicitudes ARCO: pseudonimización (L-1)
    update public.consent
    set legal_guardian_name = case when legal_guardian_name is not null
                                   then 'REPRESENTANTE-' || substr(md5(id::text), 1, 8) end,
        authority_letter_ref = case when authority_letter_ref is not null
                                    then 'REFERENCIA-' || substr(md5(id::text), 1, 8) end,
        notes = case when notes is not null then '[SUPRIMIDO - ADR-0001]' end,
        revocation_reason = case when revocation_reason is not null then '[SUPRIMIDO - ADR-0001]' end
    where person_id = p_person_id;

    update public.arco_request
    set requested_by_name = 'SOLICITANTE-' || substr(md5(id::text), 1, 8),
        details = '[SUPRIMIDO - ADR-0001]',
        reason = '[SUPRIMIDO - ADR-0001]',
        resolution_notes = case when resolution_notes is not null then '[SUPRIMIDO - ADR-0001]' end
    where person_id = p_person_id;

    -- 3. Estatus terminal 'anonymized': única vía (la marca vale sólo dentro de esta transacción)
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

        -- 4. Purga del cuerpo de entradas de bitácora preservando metadatos de actuación
        update public.journal_entry
        set body = '[CONTENIDO SUPRIMIDO POR EJERCICIO DE DERECHO ARCO DE CANCELACIÓN - ADR-0001]'
        where case_id = v_case.id;

        -- 5. Purga de evidencias adjuntas
        delete from public.attachment where case_id = v_case.id;
    end loop;
    perform set_config('bv.anonymizing', 'off', true);

    -- 6. Registro perpetuo (nunca se purga - ADR-0001): sin identificadores
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
$function$;

-- fn_apply_opposition(uuid,text) · 3 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_apply_opposition(p_person_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_org_id uuid;
    v_user_id uuid := auth.uid();
begin
    if v_user_id is null or not public.has_role('director') then
        raise exception 'Acceso denegado: El registro formal de oposición está reservado a dirección (BV-5.5).' using errcode = 'BV105';
    end if;
    perform public.fn_assert_same_org('person', p_person_id);

    if p_reason is null or trim(p_reason) = '' then
        raise exception 'El motivo de oposición es obligatorio e ineludible (Ethos C8).' using errcode = 'BV303';
    end if;

    select organization_id into v_org_id from public.person where id = p_person_id;
    if v_org_id is null then
        raise exception 'Persona no encontrada.' using errcode = 'BV202';
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
$function$;

-- fn_assert_same_org(text,uuid) · 2 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_assert_same_org(p_table text, p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_org uuid;
begin
    if p_table not in ('person', 'case', 'journal_entry', 'sharing_event') then
        raise exception 'Tabla no admitida para la comprobación de organización.' using errcode = 'BV701';
    end if;
    execute format('select organization_id from public.%I where id = $1', p_table) into v_org using p_id;
    -- Mismo mensaje si no existe o es ajeno: no se revela la existencia de registros de otra organización.
    if v_org is null or v_org is distinct from public.current_organization_id() then
        raise exception 'Registro no encontrado.' using errcode = 'BV201';
    end if;
end;
$function$;

-- fn_change_case_status(uuid,text,text,text) · 10 error(es) con código
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
    v_new_status_id uuid;
    v_user_id uuid;
begin
    if auth.uid() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: se requiere una sesión con rol operativo vigente.' using errcode = 'BV101';
    end if;
    perform public.fn_assert_same_org('case', p_case_id);
    v_user_id := auth.uid();

    if p_reason is null or trim(p_reason) = '' then
        raise exception 'Violación de integridad: Todo cambio de estatus exige un motivo explícito en texto (reason).' using errcode = 'BV305';
    end if;

    select organization_id into v_org_id from public.case where id = p_case_id;
    if v_org_id is null then
        raise exception 'Expediente no encontrado.' using errcode = 'BV203';
    end if;

    -- Compartimentación por área (BV-2.3)
    if p_axis_code = 'legal_status' then
        if not (public.has_role('director') or public.has_role_in_area('caseworker', 'legal')) then
            raise exception 'Permiso denegado: El estatus jurídico solo puede ser modificado por Dirección o personal adscrito al Área Jurídica.' using errcode = 'BV110';
        end if;
    end if;

    -- Cierre administrativo: facultad de Dirección
    if p_axis_code = 'record_status' and p_new_value_code = 'closed' then
        if not public.has_role('director') then
            raise exception 'Permiso denegado: El cierre administrativo del expediente es facultad exclusiva de Dirección.' using errcode = 'BV111';
        end if;
    end if;

    -- «anonymized» (terminal, irreversible) solo se alcanza anonimizando a la persona (ADR-0001)
    if p_new_value_code = 'anonymized'
       and coalesce(current_setting('bv.anonymizing', true), '') <> 'on' then
        raise exception 'Violación de Ethos C7: el estatus «anonymized» solo se alcanza anonimizando a la persona (fn_anonymize_person).' using errcode = 'BV502';
    end if;

    select id into v_axis_id from public.status_axis where organization_id = v_org_id and code = p_axis_code;
    if v_axis_id is null then
        raise exception 'Eje de estatus no válido para esta organización.' using errcode = 'BV206';
    end if;

    select id into v_new_val_id
    from public.status_value
    where axis_id = v_axis_id and code = p_new_value_code;

    if v_new_val_id is null then
        raise exception 'Valor de estatus destino no encontrado en el catálogo.' using errcode = 'BV207';
    end if;

    select cs.id, sv.code into v_old_status_id, v_old_val_code
    from public.case_status cs
    join public.status_value sv on sv.id = cs.value_id
    where cs.case_id = p_case_id and cs.axis_id = v_axis_id and cs.valid_to is null;

    if v_old_val_code = 'anonymized' then
        raise exception 'Violación de Ethos: Un expediente en estatus anonimizado es terminal e irreversible.' using errcode = 'BV503';
    end if;

    -- Reapertura: salir de «cerrado» es facultad de Dirección (BV-2.3)
    if p_axis_code = 'record_status' and v_old_val_code = 'closed' and p_new_value_code <> 'closed' then
        if not public.has_role('director') then
            raise exception 'Permiso denegado: Reabrir un expediente cerrado es facultad exclusiva de Dirección.' using errcode = 'BV112';
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
$function$;

-- fn_create_case_with_person(text,text,text,text,date,boolean,integer,integer,text,integer,text,text,text,boolean,integer,integer,integer,integer,text,uuid,text[],jsonb) · 2 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_create_case_with_person(p_given_name text, p_paternal_family_name text, p_maternal_family_name text, p_preferred_name text, p_birth_date date, p_birth_date_is_estimated boolean, p_sex_id integer, p_nationality_country_id integer, p_other_nationality text, p_primary_language_id integer, p_other_language text, p_phone_number text, p_intake_window_type text, p_travels_with_family boolean, p_intake_state_id integer, p_intake_municipality_id integer, p_intake_channel_id integer, p_entry_route_id integer, p_entry_date_str text, p_assigned_area_id uuid, p_vulnerability_codes text[], p_consents jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
    -- Antes lo decidía la política de INSERT (intake_officer y director); ahora lo exige la función.
    if auth.uid() is null
       or public.current_organization_id() is null
       or not (public.has_role('intake_officer') or public.has_role('director')) then
        raise exception 'Acceso denegado: solo ingreso y dirección abren expedientes (BV-3.1).' using errcode = 'BV113';
    end if;

    -- El área asignada, si se indica, debe ser de la misma organización
    if p_assigned_area_id is not null and not exists (
        select 1 from public.area a
        where a.id = p_assigned_area_id and a.organization_id = public.current_organization_id()
    ) then
        raise exception 'Área no válida para esta organización.' using errcode = 'BV208';
    end if;

    return public.fn_create_case_with_person_impl(
        p_given_name, p_paternal_family_name, p_maternal_family_name, p_preferred_name,
        p_birth_date, p_birth_date_is_estimated, p_sex_id, p_nationality_country_id,
        p_other_nationality, p_primary_language_id, p_other_language, p_phone_number,
        p_intake_window_type, p_travels_with_family, p_intake_state_id, p_intake_municipality_id,
        p_intake_channel_id, p_entry_route_id, p_entry_date_str, p_assigned_area_id,
        p_vulnerability_codes, p_consents
    );
end;
$function$;

-- fn_create_case_with_person_impl(text,text,text,text,date,boolean,integer,integer,text,integer,text,text,text,boolean,integer,integer,integer,integer,text,uuid,text[],jsonb) · 7 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_create_case_with_person_impl(p_given_name text, p_paternal_family_name text, p_maternal_family_name text, p_preferred_name text, p_birth_date date, p_birth_date_is_estimated boolean, p_sex_id integer, p_nationality_country_id integer, p_other_nationality text, p_primary_language_id integer, p_other_language text, p_phone_number text, p_intake_window_type text, p_travels_with_family boolean, p_intake_state_id integer, p_intake_municipality_id integer, p_intake_channel_id integer, p_entry_route_id integer, p_entry_date_str text, p_assigned_area_id uuid, p_vulnerability_codes text[], p_consents jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_user_id uuid := auth.uid();
    v_org_id uuid;
    v_person_id uuid;
    v_case_id uuid;
    v_code text;
    v_consent jsonb;
    v_has_general boolean;
    v_has_sensitive boolean;
    v_has_authority boolean;
    v_has_minor_assent boolean;
    v_has_guardian boolean;
begin
    v_org_id := public.current_organization_id();
    if v_user_id is null or v_org_id is null then
        raise exception 'Acceso denegado: sesion sin organizacion asociada.' using errcode = 'BV102';
    end if;

    if p_given_name is null or trim(p_given_name) = ''
       or p_paternal_family_name is null or trim(p_paternal_family_name) = '' then
        raise exception 'Nombre y primer apellido son obligatorios.' using errcode = 'BV307';
    end if;

    if jsonb_typeof(coalesce(p_consents, 'null'::jsonb)) is distinct from 'array' then
        raise exception 'Los consentimientos deben enviarse como arreglo.' using errcode = 'BV308';
    end if;

    select
        coalesce(bool_or(c->>'consent_type' = 'general_care' and coalesce(c->>'status', 'granted') = 'granted'), false),
        coalesce(bool_or(c->>'consent_type' = 'sensitive_data' and coalesce(c->>'status', 'granted') = 'granted'), false),
        coalesce(bool_or(coalesce(c->>'authority_letter_ref', '') <> '' and coalesce(c->>'legal_guardian_name', '') <> ''), false),
        coalesce(bool_or(coalesce((c->>'is_minor_assent')::boolean, false)), false),
        coalesce(bool_or(coalesce(c->>'legal_guardian_name', '') <> ''), false)
    into v_has_general, v_has_sensitive, v_has_authority, v_has_minor_assent, v_has_guardian
    from jsonb_array_elements(p_consents) c;

    if not v_has_general then
        raise exception 'Sin consentimiento general informado no se abre expediente; el auxilio humanitario inmediato no se condiciona (Ethos C2, BV-5.1).' using errcode = 'BV401';
    end if;

    if coalesce(array_length(p_vulnerability_codes, 1), 0) > 0 and not v_has_sensitive then
        raise exception 'Control P-06: no se capturan marcadores de vulnerabilidad sin consentimiento expreso para datos sensibles.' using errcode = 'BV402';
    end if;

    if p_birth_date > current_date - interval '18 years' and not (v_has_minor_assent and v_has_guardian) then
        raise exception 'Persona menor de 18 años: el consentimiento exige asentimiento y la identidad de su representante (BV-5.1).' using errcode = 'BV403';
    end if;

    if 'unaccompanied_child' = any (coalesce(p_vulnerability_codes, '{}'::text[])) and not v_has_authority then
        raise exception 'Niñez no acompañada: se requiere la identidad de la autoridad o tutor y la referencia de su oficio (BV-5.1).' using errcode = 'BV404';
    end if;

    insert into public.person (
        organization_id, given_name, paternal_family_name, maternal_family_name,
        preferred_name, birth_date, birth_date_is_estimated, sex_id,
        nationality_country_id, other_nationality, primary_language_id,
        other_language, phone_number
    ) values (
        v_org_id, trim(p_given_name), trim(p_paternal_family_name), nullif(trim(p_maternal_family_name), ''),
        nullif(trim(p_preferred_name), ''), p_birth_date, coalesce(p_birth_date_is_estimated, false), p_sex_id,
        p_nationality_country_id, p_other_nationality, p_primary_language_id,
        p_other_language, nullif(trim(p_phone_number), '')
    ) returning id into v_person_id;

    insert into public."case" (
        organization_id, case_number, titular_person_id, intake_state_id,
        intake_municipality_id, intake_channel_id, intake_window_type,
        entry_route_id, entry_date_str, travels_with_family, opened_by,
        assigned_area_id, assigned_user_id
    ) values (
        v_org_id, public.fn_generate_case_number(v_org_id), v_person_id, p_intake_state_id,
        p_intake_municipality_id, p_intake_channel_id, p_intake_window_type,
        p_entry_route_id, p_entry_date_str, coalesce(p_travels_with_family, false), v_user_id,
        p_assigned_area_id, v_user_id
    ) returning id into v_case_id;

    foreach v_code in array coalesce(p_vulnerability_codes, '{}'::text[]) loop
        insert into public.case_vulnerability_marker (
            organization_id, case_id, marker_code, affirmed_by
        ) values (v_org_id, v_case_id, v_code, v_user_id);
    end loop;

    for v_consent in select * from jsonb_array_elements(p_consents) loop
        perform public.fn_register_consent(
            v_person_id,
            v_consent->>'consent_type',
            coalesce(v_consent->>'status', 'granted'),
            v_case_id,
            coalesce((v_consent->>'is_minor_assent')::boolean, false),
            nullif(v_consent->>'legal_guardian_name', ''),
            nullif(v_consent->>'legal_guardian_role', ''),
            nullif(v_consent->>'authority_letter_ref', ''),
            nullif(v_consent->>'notes', '')
        );
    end loop;

    return v_case_id;
end;
$function$;

-- fn_create_clarification_note(uuid,text,timestamp with time zone,boolean) · 5 error(es) con código
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
    v_work_note boolean;
    v_inherited int := 0;
begin
    if auth.uid() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: se requiere una sesión con rol operativo vigente.' using errcode = 'BV101';
    end if;
    perform public.fn_assert_same_org('journal_entry', p_superseded_entry_id);
    v_user_id := auth.uid();

    if not public.fn_can_act_on_entry(p_superseded_entry_id) then
        raise exception 'Permiso denegado: solo la persona autora, el área de la entrada o Dirección pueden aclararla.' using errcode = 'BV115';
    end if;

    if p_body is null or trim(p_body) = '' then
        raise exception 'El texto de la aclaración es obligatorio.' using errcode = 'BV309';
    end if;

    select * into v_old_entry from public.journal_entry where id = p_superseded_entry_id;
    if v_old_entry.id is null then
        raise exception 'El registro de bitácora original a corregir no existe.' using errcode = 'BV204';
    end if;

    if v_old_entry.superseded_by_id is not null then
        raise exception 'Este registro de bitácora ya ha sido superado por una aclaración previa.' using errcode = 'BV504';
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

    -- La aclaración le llega a quien recibió la original (y hereda el estado real de su acuse)
    if v_old_entry.visibility = 'shared' and not v_work_note then
        insert into public.sharing_event (
            organization_id, journal_entry_id, case_id, from_area_id, to_area_id,
            from_visibility, to_visibility, reason, shared_by_user_id, shared_at,
            acknowledged_by_user_id, acknowledged_at
        )
        select s.organization_id, v_new_entry_id, s.case_id, s.from_area_id, s.to_area_id,
               s.from_visibility, s.to_visibility, 'Hereda la compartición de la entrada que aclara',
               v_user_id, now(), s.acknowledged_by_user_id, s.acknowledged_at
        from public.sharing_event s
        where s.journal_entry_id = p_superseded_entry_id;
        get diagnostics v_inherited = row_count;
    end if;

    update public.journal_entry
    set superseded_by_id = v_new_entry_id
    where id = p_superseded_entry_id;

    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_old_entry.organization_id, v_user_id, 'CLARIFICATION', 'journal_entry', v_new_entry_id,
        jsonb_build_object(
            'case_id', v_old_entry.case_id,
            'superseded_entry_id', p_superseded_entry_id,
            'is_work_note', v_work_note,
            'inherited_sharing_events', v_inherited
        ));

    return v_new_entry_id;
end;
$function$;

-- fn_create_journal_entry(uuid,text,text,timestamp with time zone,boolean,uuid) · 7 error(es) con código
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
    v_area_code text;
begin
    if auth.uid() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: se requiere una sesión con rol operativo vigente.' using errcode = 'BV101';
    end if;
    perform public.fn_assert_same_org('case', p_case_id);
    v_user_id := auth.uid();

    if p_body is null or trim(p_body) = '' then
        raise exception 'El texto de la intervención en bitácora es obligatorio.' using errcode = 'BV310';
    end if;

    select organization_id into v_org_id from public.case where id = p_case_id;
    if v_org_id is null then
        raise exception 'Expediente no encontrado.' using errcode = 'BV203';
    end if;

    if p_area_id is not null then
        -- Escribir a nombre de un área exige ser de esa área (o dirección) y que sea de la misma
        -- organización. Quien no tiene área asignada (ingreso) solo escribe en coordinación.
        select a.code into v_area_code
        from public.area a
        where a.id = p_area_id and a.organization_id = v_org_id and a.active;
        if v_area_code is null then
            raise exception 'Área no válida para esta organización.' using errcode = 'BV208';
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
                    raise exception 'Permiso denegado: solo se escribe a nombre del propio área (Ethos C2, C4).' using errcode = 'BV117';
                end if;
            elsif v_area_code <> 'coordinacion' then
                raise exception 'Permiso denegado: sin área asignada solo se escribe a nombre de coordinación.' using errcode = 'BV118';
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
        raise exception 'No se pudo determinar el área operativa para el registro de bitácora.' using errcode = 'BV702';
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
$function$;

-- fn_create_subfolio(uuid,text,text,text,text,date,boolean,integer,integer,text,integer,text,text,text,text[],jsonb) · 15 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_create_subfolio(p_parent_case_id uuid, p_given_name text, p_paternal_family_name text, p_maternal_family_name text, p_preferred_name text, p_birth_date date, p_birth_date_is_estimated boolean, p_sex_id integer, p_nationality_country_id integer, p_other_nationality text, p_primary_language_id integer, p_other_language text, p_guardian_role text, p_justification text, p_vulnerability_codes text[], p_consents jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_user_id uuid := auth.uid();
    v_org_id uuid;
    v_parent public."case"%rowtype;
    v_titular public.person%rowtype;
    v_guardian_name text;
    v_person_id uuid;
    v_case_id uuid;
    v_number text;
    v_next int;
    v_code text;
    v_consent jsonb;
    v_has_general boolean;
    v_has_sensitive boolean;
    v_area_id uuid;
    v_entry_id uuid;
begin
    v_org_id := public.current_organization_id();
    if v_user_id is null or v_org_id is null then
        raise exception 'Acceso denegado: sesion sin organizacion asociada.' using errcode = 'BV102';
    end if;
    if not (public.has_role('intake_officer') or public.has_role('director')) then
        raise exception 'Permiso denegado: solo ingreso y dirección crean subfolios (BV-3.2).' using errcode = 'BV114';
    end if;

    -- El caso padre: de la misma organización, abierto y principal. Se bloquea para que dos altas
    -- simultáneas no tomen el mismo número de subfolio.
    perform public.fn_assert_same_org('case', p_parent_case_id);
    select * into v_parent from public."case" where id = p_parent_case_id for update;
    if v_parent.id is null then
        raise exception 'Expediente no encontrado.' using errcode = 'BV203';
    end if;
    if v_parent.parent_case_id is not null then
        raise exception 'Un subfolio no admite subfolios (profundidad máxima 1).' using errcode = 'BV505';
    end if;
    if v_parent.closed_at is not null then
        raise exception 'El caso padre está cerrado: no se le pueden abrir subfolios.' using errcode = 'BV506';
    end if;

    -- Quien representa es la persona titular del caso padre, y debe ser adulta
    select * into v_titular from public.person where id = v_parent.titular_person_id;
    if v_titular.birth_date is not null and v_titular.birth_date > current_date - interval '18 years' then
        raise exception 'Quien representa a la persona menor debe ser una persona adulta.' using errcode = 'BV405';
    end if;
    v_guardian_name := concat_ws(' ', v_titular.given_name, v_titular.paternal_family_name, v_titular.maternal_family_name);

    if p_given_name is null or trim(p_given_name) = '' or p_paternal_family_name is null or trim(p_paternal_family_name) = '' then
        raise exception 'Nombre y primer apellido son obligatorios.' using errcode = 'BV307';
    end if;
    if p_birth_date is null or p_birth_date <= current_date - interval '18 years' then
        raise exception 'El subfolio es para niñez y adolescencia: la persona debe ser menor de 18 años.' using errcode = 'BV406';
    end if;
    if p_guardian_role is null or trim(p_guardian_role) = '' then
        raise exception 'Indica el parentesco de quien representa a la persona menor.' using errcode = 'BV311';
    end if;
    if p_justification is null or length(trim(p_justification)) < 10 then
        raise exception 'La nota de justificación es obligatoria (mínimo 10 caracteres).' using errcode = 'BV312';
    end if;
    if jsonb_typeof(coalesce(p_consents, 'null'::jsonb)) is distinct from 'array' then
        raise exception 'Los consentimientos deben enviarse como arreglo.' using errcode = 'BV308';
    end if;

    select
        coalesce(bool_or(c->>'consent_type' = 'general_care' and coalesce(c->>'status', 'granted') = 'granted'), false),
        coalesce(bool_or(c->>'consent_type' = 'sensitive_data' and coalesce(c->>'status', 'granted') = 'granted'), false)
    into v_has_general, v_has_sensitive
    from jsonb_array_elements(p_consents) c;

    if not v_has_general then
        raise exception 'Sin consentimiento general informado no se abre expediente; el auxilio humanitario inmediato no se condiciona (Ethos C2, BV-5.1).' using errcode = 'BV401';
    end if;
    if coalesce(array_length(p_vulnerability_codes, 1), 0) > 0 and not v_has_sensitive then
        raise exception 'Control P-06: no se capturan marcadores de vulnerabilidad sin consentimiento expreso para datos sensibles.' using errcode = 'BV402';
    end if;
    if 'unaccompanied_child' = any (coalesce(p_vulnerability_codes, '{}'::text[])) then
        raise exception 'El subfolio es para niñez acompañada: el marcador de niñez no acompañada va en un expediente propio con su autoridad.' using errcode = 'BV407';
    end if;

    -- Folio: el del caso padre con el siguiente sufijo libre
    select coalesce(max(substring(case_number from '-S([0-9]+)$')::int), 0) + 1
      into v_next
      from public."case" where parent_case_id = p_parent_case_id;
    v_number := v_parent.case_number || '-S' || v_next;

    insert into public.person (
        organization_id, given_name, paternal_family_name, maternal_family_name, preferred_name,
        birth_date, birth_date_is_estimated, sex_id, nationality_country_id, other_nationality, primary_language_id, other_language
    ) values (
        v_org_id, trim(p_given_name), trim(p_paternal_family_name), nullif(trim(p_maternal_family_name), ''),
        nullif(trim(p_preferred_name), ''), p_birth_date, coalesce(p_birth_date_is_estimated, false), p_sex_id,
        p_nationality_country_id, nullif(trim(p_other_nationality), ''), p_primary_language_id, nullif(trim(p_other_language), '')
    ) returning id into v_person_id;

    insert into public."case" (
        organization_id, case_number, parent_case_id, titular_person_id, intake_state_id,
        intake_municipality_id, intake_channel_id, intake_window_type, entry_route_id, entry_date_str,
        travels_with_family, opened_by, assigned_area_id, assigned_user_id
    ) values (
        v_org_id, v_number, p_parent_case_id, v_person_id, v_parent.intake_state_id,
        v_parent.intake_municipality_id, v_parent.intake_channel_id, v_parent.intake_window_type, v_parent.entry_route_id, v_parent.entry_date_str,
        true, v_user_id, v_parent.assigned_area_id, v_user_id
    ) returning id into v_case_id;

    foreach v_code in array coalesce(p_vulnerability_codes, '{}'::text[]) loop
        insert into public.case_vulnerability_marker (organization_id, case_id, marker_code, affirmed_by)
        values (v_org_id, v_case_id, v_code, v_user_id);
    end loop;

    -- Cada decisión de consentimiento la da quien representa: nombre tomado del caso padre, nunca del cliente
    for v_consent in select * from jsonb_array_elements(p_consents) loop
        perform public.fn_register_consent(
            v_person_id,
            v_consent->>'consent_type',
            coalesce(v_consent->>'status', 'granted'),
            v_case_id,
            true,
            v_guardian_name,
            trim(p_guardian_role),
            null,
            nullif(v_consent->>'notes', '')
        );
    end loop;

    -- La justificación queda en la bitácora del subfolio, con quien la escribió y cuándo
    -- Área de la nota: la del caso padre (el subfolio la hereda); si no tiene, la de quien lo crea, coordinación
    -- o, en último caso, cualquier área activa de la organización. La nota nace area_private como toda entrada.
    select coalesce(
        v_parent.assigned_area_id,
        (select ur.area_id from public.user_role ur where ur.user_id = v_user_id and ur.revoked_at is null and ur.area_id is not null limit 1),
        (select a.id from public.area a where a.organization_id = v_org_id and a.code = 'coordinacion' and a.active limit 1),
        (select a.id from public.area a where a.organization_id = v_org_id and a.active order by a.created_at limit 1)
    ) into v_area_id;
    if v_area_id is null then
        raise exception 'No se pudo determinar el área operativa para la nota de justificación.' using errcode = 'BV702';
    end if;

    insert into public.journal_entry (
        organization_id, case_id, area_id, author_user_id, entry_type_key, body, is_work_note, occurred_at, created_at, visibility
    ) values (
        v_org_id, v_case_id, v_area_id, v_user_id, 'note',
        'Alta de subfolio de ' || v_parent.case_number || '. Justificación: ' || trim(p_justification),
        false, now(), now(), 'area_private'
    ) returning id into v_entry_id;

    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_org_id, v_user_id, 'INSERT', 'journal_entry', v_entry_id,
        jsonb_build_object('case_id', v_case_id, 'entry_type_key', 'note', 'is_work_note', false, 'area_id', v_area_id));

    return v_case_id;
end;
$function$;

-- fn_enforce_case_status_append_only() · 4 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_enforce_case_status_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
    if old.valid_to is not null then
        raise exception 'Violación de Regla Dura 7: un estatus ya cerrado es inmutable.' using errcode = 'BV601';
    end if;

    if new.valid_to is null then
        raise exception 'Violación de Regla Dura 7: el estatus no se sobrescribe. Cierre la vigencia y abra uno nuevo con fn_change_case_status.' using errcode = 'BV602';
    end if;

    if (to_jsonb(new) - 'valid_to') is distinct from (to_jsonb(old) - 'valid_to') then
        raise exception 'Violación de Regla Dura 7: de un estatus solo puede cambiar el cierre de su vigencia (valid_to).' using errcode = 'BV603';
    end if;

    if new.valid_to < old.valid_from then
        raise exception 'El cierre de vigencia no puede ser anterior a su inicio.' using errcode = 'BV319';
    end if;

    return new;
end;
$function$;

-- fn_generate_arco_access_extract(uuid) · 2 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_generate_arco_access_extract(p_person_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        raise exception 'Acceso denegado: La emisión de extractos formales ARCO está reservada a dirección (BV-5.2).' using errcode = 'BV106';
    end if;
    perform public.fn_assert_same_org('person', p_person_id);

    select * into v_person from public.person where id = p_person_id;
    if v_person is null then
        raise exception 'Persona no encontrada.' using errcode = 'BV202';
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
$function$;

-- fn_journal_work_note_born_private() · 1 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_journal_work_note_born_private()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
    if new.is_work_note and new.visibility is distinct from 'area_private' then
        raise exception 'Violación de Ethos E-02: una nota de trabajo protegida nace y permanece privada al área.' using errcode = 'BV604';
    end if;
    return new;
end;
$function$;

-- fn_prevent_audit_tampering() · 1 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_prevent_audit_tampering()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
    raise exception 'Violación de Ethos: La tabla audit_event es estrictamente append-only. UPDATE o DELETE están prohibidos en el motor de base de datos.' using errcode = 'BV605';
end;
$function$;

-- fn_prevent_delete_arco() · 1 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_prevent_delete_arco()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
    raise exception 'Violación de integridad: Los registros de consentimiento y solicitudes ARCO son inmutables; no se permite su eliminación (Reglas Duras 2 y 3 / Ethos C7).' using errcode = 'BV606';
end;
$function$;

-- fn_prevent_delete_journal() · 1 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_prevent_delete_journal()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
    raise exception 'Violación de integridad: La bitácora y sus evidencias son estrictamente inmutables; no se permite borrar registros (Regla Dura 3 / ADR-0005).' using errcode = 'BV607';
end;
$function$;

-- fn_prevent_update_journal_entry() · 4 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_prevent_update_journal_entry()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
    if old.is_work_note is distinct from new.is_work_note then
        raise exception 'Violación de Ethos E-02: una nota de trabajo protegida no deja de serlo (ni una entrada ordinaria pasa a serlo).' using errcode = 'BV608';
    end if;
    if new.is_work_note and new.visibility is distinct from old.visibility then
        raise exception 'Violación de Ethos E-02: una nota de trabajo protegida no se comparte.' using errcode = 'BV609';
    end if;

    -- Purga estricta por ejercicio de derecho ARCO de cancelación (ADR-0001)
    if new.body = '[CONTENIDO SUPRIMIDO POR EJERCICIO DE DERECHO ARCO DE CANCELACIÓN - ADR-0001]' then
        if not public.has_role('director') then
            raise exception 'Violación de seguridad: La purga por anonimización de bitácora está reservada exclusivamente al rol director (ADR-0001).' using errcode = 'BV610';
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
        raise exception 'Violación de integridad: El contenido original de un registro de bitácora no admite edición. Utilice una fe de erratas (BV-4.2).' using errcode = 'BV611';
    end if;

    return new;
end;
$function$;

-- fn_publish_consent_text(text,text,text,boolean) · 5 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_publish_consent_text(p_consent_type text, p_title text, p_description text, p_required boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_org uuid;
    v_version int;
    v_prev uuid;
    v_id uuid;
begin
    if auth.uid() is null or not public.has_role('director') then
        raise exception 'Acceso denegado: solo la dirección define los textos de consentimiento.' using errcode = 'BV107';
    end if;
    v_org := public.current_organization_id();
    if v_org is null then
        raise exception 'Acceso denegado: sin organización.' using errcode = 'BV102';
    end if;
    if p_consent_type is null or p_consent_type not in ('general_care', 'sensitive_data', 'internal_sharing', 'secondary_use_research') then
        raise exception 'Tipo de consentimiento no válido.' using errcode = 'BV210';
    end if;
    if coalesce(btrim(p_title), '') = '' or coalesce(btrim(p_description), '') = '' then
        raise exception 'El título y la descripción del consentimiento son obligatorios.' using errcode = 'BV313';
    end if;
    if p_consent_type = 'general_care' and coalesce(p_required, false) is not true then
        raise exception 'El consentimiento general es obligatorio y no puede configurarse como opcional.' using errcode = 'BV314';
    end if;

    select coalesce(max(version), 0) + 1 into v_version from public.consent_text
    where organization_id = v_org and consent_type = p_consent_type;
    select id into v_prev from public.consent_text
    where organization_id = v_org and consent_type = p_consent_type and active order by version desc limit 1;

    update public.consent_text set active = false
    where organization_id = v_org and consent_type = p_consent_type and active;

    insert into public.consent_text (organization_id, consent_type, version, title, description, required, active, created_by)
    values (v_org, p_consent_type, v_version, btrim(p_title), btrim(p_description), coalesce(p_required, false), true, auth.uid())
    returning id into v_id;

    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_org, auth.uid(), 'INSERT', 'consent_text', v_id,
            jsonb_build_object('consent_type', p_consent_type, 'version', v_version, 'required', coalesce(p_required, false), 'replaces', v_prev));

    return v_id;
end;
$function$;

-- fn_publish_privacy_notice(text,text,text,date) · 4 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_publish_privacy_notice(p_title text, p_summary text, p_full_text text, p_effective_date date DEFAULT CURRENT_DATE)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_org uuid;
    v_n int;
    v_version text;
    v_prev uuid;
    v_id uuid;
begin
    if auth.uid() is null or not public.has_role('director') then
        raise exception 'Acceso denegado: solo la dirección publica el aviso de privacidad.' using errcode = 'BV108';
    end if;
    v_org := public.current_organization_id();
    if v_org is null then
        raise exception 'Acceso denegado: sin organización.' using errcode = 'BV102';
    end if;
    if coalesce(btrim(p_title), '') = '' or coalesce(btrim(p_summary), '') = '' or coalesce(btrim(p_full_text), '') = '' then
        raise exception 'El título, el resumen y el texto completo del aviso son obligatorios.' using errcode = 'BV315';
    end if;
    if p_effective_date is null or p_effective_date > current_date then
        raise exception 'La vigencia no puede ser una fecha futura: el aviso entra en vigor al publicarse.' using errcode = 'BV316';
    end if;

    select count(*) + 1 into v_n from public.privacy_notice where organization_id = v_org;
    v_version := v_n::text || '.0';
    select id into v_prev from public.privacy_notice where organization_id = v_org and active order by created_at desc limit 1;

    update public.privacy_notice set active = false where organization_id = v_org and active;

    insert into public.privacy_notice (organization_id, version, title, summary, full_text, effective_date, active)
    values (v_org, v_version, btrim(p_title), btrim(p_summary), btrim(p_full_text), p_effective_date, true)
    returning id into v_id;

    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_org, auth.uid(), 'INSERT', 'privacy_notice', v_id,
            jsonb_build_object('version', v_version, 'replaces', v_prev, 'effective_date', p_effective_date));

    return v_id;
end;
$function$;

-- fn_rectify_person(uuid,text,text,text,text,date,boolean,integer,integer,text,text,text) · 4 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_rectify_person(p_person_id uuid, p_given_name text, p_paternal_family_name text, p_maternal_family_name text, p_preferred_name text, p_birth_date date, p_birth_date_is_estimated boolean, p_sex_id integer, p_nationality_country_id integer, p_phone_number text, p_email text, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_person record;
    v_after record;
    v_changed jsonb;
    v_user_id uuid := auth.uid();
begin
    if v_user_id is null or not (public.has_role('director') or public.has_role('intake_officer')) then
        raise exception 'Acceso denegado: La rectificación de datos biográficos está reservada a dirección o personal de ingreso (BV-5.4).' using errcode = 'BV119';
    end if;
    perform public.fn_assert_same_org('person', p_person_id);

    if p_reason is null or trim(p_reason) = '' then
        raise exception 'El motivo de rectificación es obligatorio e ineludible (Ethos C8).' using errcode = 'BV304';
    end if;

    select * into v_person from public.person where id = p_person_id;
    if v_person is null then
        raise exception 'Persona no encontrada.' using errcode = 'BV202';
    end if;

    if v_person.is_anonymized then
        raise exception 'Operación no permitida: Una persona anonimizada no admite rectificación (ADR-0001).' using errcode = 'BV507';
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
$function$;

-- fn_register_consent(uuid,text,text,uuid,boolean,text,text,text,text) · 2 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_register_consent(p_person_id uuid, p_consent_type text, p_status text DEFAULT 'granted'::text, p_case_id uuid DEFAULT NULL::uuid, p_is_minor_assent boolean DEFAULT false, p_legal_guardian_name text DEFAULT NULL::text, p_legal_guardian_role text DEFAULT NULL::text, p_authority_letter_ref text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_org_id uuid;
    v_user_id uuid := auth.uid();
    v_notice_id uuid;
    v_consent_id uuid;
begin

    -- Regla Dura 1: la función repite la regla de acceso (se ejecuta saltándose RLS)
    if auth.uid() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: se requiere una sesión con rol operativo vigente.' using errcode = 'BV101';
    end if;
    perform public.fn_assert_same_org('person', p_person_id);
    -- Obtener organización de la persona
    select organization_id into v_org_id from public.person where id = p_person_id;
    if v_org_id is null then
        raise exception 'Persona no encontrada.' using errcode = 'BV202';
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

-- fn_share_journal_entry(uuid,uuid,text) · 7 error(es) con código
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
    if auth.uid() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: se requiere una sesión con rol operativo vigente.' using errcode = 'BV101';
    end if;
    perform public.fn_assert_same_org('journal_entry', p_journal_entry_id);
    v_user_id := auth.uid();

    if not public.fn_can_act_on_entry(p_journal_entry_id) then
        raise exception 'Permiso denegado: solo la persona autora, el área de la entrada o Dirección pueden compartirla (Ethos C3).' using errcode = 'BV116';
    end if;

    if p_reason is null or trim(p_reason) = '' then
        raise exception 'Violación de Ethos C3: Compartir un registro con otra área exige asentar un motivo explícito.' using errcode = 'BV306';
    end if;

    select * into v_entry from public.journal_entry where id = p_journal_entry_id;
    if v_entry.id is null then
        raise exception 'Registro de bitácora no encontrado.' using errcode = 'BV205';
    end if;

    if v_entry.is_work_note then
        raise exception 'Violación de Ethos E-02: una nota de trabajo protegida no se comparte; solo la ven su autoría, su área y Dirección.' using errcode = 'BV609';
    end if;

    if not exists (
        select 1 from public.area a
        where a.id = p_to_area_id and a.organization_id = v_entry.organization_id and a.active
    ) then
        raise exception 'Área destino no válida.' using errcode = 'BV209';
    end if;

    if v_entry.area_id = p_to_area_id then
        raise exception 'El registro ya pertenece a esta área.' using errcode = 'BV508';
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
$function$;

-- fn_update_organization_identity(text,text,text,text,text,text,text,text) · 4 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_update_organization_identity(p_display_name text, p_legal_name text, p_folio_prefix text, p_about_text text, p_responsible_name text, p_responsible_address text, p_responsible_contact text, p_arco_contact text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_org uuid;
    v_prefix text;
begin
    if auth.uid() is null or not public.has_role('director') then
        raise exception 'Acceso denegado: solo la dirección configura la organización.' using errcode = 'BV109';
    end if;
    v_org := public.current_organization_id();
    if v_org is null then
        raise exception 'Acceso denegado: sin organización.' using errcode = 'BV102';
    end if;
    if coalesce(btrim(p_display_name), '') = '' or coalesce(btrim(p_legal_name), '') = '' then
        raise exception 'El nombre y la razón social son obligatorios.' using errcode = 'BV317';
    end if;
    v_prefix := nullif(upper(btrim(coalesce(p_folio_prefix, ''))), '');
    if v_prefix is not null and v_prefix !~ '^[A-Z]{2,5}$' then
        raise exception 'El prefijo del folio debe tener de 2 a 5 letras (A–Z).' using errcode = 'BV318';
    end if;

    update public.organization set
        display_name = btrim(p_display_name),
        legal_name = btrim(p_legal_name),
        folio_prefix = v_prefix,
        about_text = nullif(btrim(coalesce(p_about_text, '')), ''),
        responsible_name = nullif(btrim(coalesce(p_responsible_name, '')), ''),
        responsible_address = nullif(btrim(coalesce(p_responsible_address, '')), ''),
        responsible_contact = nullif(btrim(coalesce(p_responsible_contact, '')), ''),
        arco_contact = nullif(btrim(coalesce(p_arco_contact, '')), ''),
        updated_at = now()
    where id = v_org;

    -- La auditoría la escribe el disparador trg_audit_organization (un evento por cambio, con antes y después).

    return v_org;
end;
$function$;

-- fn_validate_subfolio_depth() · 1 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_validate_subfolio_depth()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
    v_grandparent_id uuid;
begin
    if new.parent_case_id is not null then
        select parent_case_id into v_grandparent_id 
        from public.case 
        where id = new.parent_case_id;

        if v_grandparent_id is not null then
            raise exception 'Violación de jerarquía: Un subfolio no puede tener subfolios dependientes (profundidad máxima 1).' using errcode = 'BV505';
        end if;
    end if;
    return new;
end;
$function$;

-- fn_versioned_row_guard() · 2 error(es) con código
CREATE OR REPLACE FUNCTION public.fn_versioned_row_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
    if tg_op = 'DELETE' then
        raise exception 'Violación de integridad: las versiones publicadas son inmutables y no se eliminan (Reglas Duras 2 y 3).' using errcode = 'BV612';
    end if;
    if (to_jsonb(new) - 'active') is distinct from (to_jsonb(old) - 'active') or not (old.active and not new.active) then
        raise exception 'Violación de integridad: una versión publicada no se edita; se publica una nueva (Ethos C7).' using errcode = 'BV613';
    end if;
    return new;
end;
$function$;
