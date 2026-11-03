-- ==============================================================================
-- Ronda 2 de ciberseguridad: catalogo completo de anonimizacion y texto libre fuera de la auditoria
--
-- Hallazgos (30_entrega/ronda-2-ciberseguridad-2026-11.md):
--  * S-01 (media): `fn_audit_trigger` guarda la fila completa en `audit_event` (que es solo de anadir y se conserva 5 anos) para
--    `case`, `case_status` y `task`. Sus textos libres (`closure_reason`, `legacy_reference`, `reference_number`; `reason`;
--    `name`, `details`) quedaban en el registro de auditoria sin forma de anonimizarlos. Ahora esas tres tablas usan la variante
--    "redactada", que deja fuera esas columnas (el resto de la fila se audita igual).
--  * S-02 (media): `fn_anonymize_person` no limpiaba `case.closure_reason`, `case.legacy_reference`, `case.reference_number`,
--    `case_date.change_reason`, `sharing_event.reason`, `authority_request.official_letter_ref/response_summary`,
--    `case_status.reason`, ni los espejos heredados `person.occupations`, `education_level_id`, `marital_status_id`,
--    `origin_department_id`. Ahora si.
--  * La guarda de estatus (Regla Dura 7) sigue impidiendo todo cambio de un estatus cerrado, con una sola excepcion: mientras
--    corre la anonimizacion (marca `bv.anonymizing`) puede cambiar `reason`, y nada mas.
--  * Pendiente de decision (D-26): `task.name` y `task.details` de tareas ligadas a un expediente.
-- ==============================================================================

-- ---------------------------------------------------------------- 1. Auditoria redactada: varias columnas
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
    i int;
begin
    if tg_op in ('INSERT', 'UPDATE') then
        v_new := to_jsonb(new);
        v_rec := new.id;
        v_org := new.organization_id;
    end if;
    if tg_op in ('UPDATE', 'DELETE') then
        v_old := to_jsonb(old);
        v_rec := old.id;
        v_org := old.organization_id;
    end if;
    -- Cada argumento del disparador es una columna que no debe quedar en el registro de auditoria
    for i in 0 .. tg_nargs - 1 loop
        v_new := v_new - tg_argv[i];
        v_old := v_old - tg_argv[i];
    end loop;
    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, old_values, new_values)
    values (v_org, auth.uid(), tg_op, tg_table_name, v_rec, v_old, v_new);
    return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists trg_audit_case on public."case";
create trigger trg_audit_case after insert or update on public."case"
    for each row execute function public.fn_audit_trigger_redacted('closure_reason', 'legacy_reference', 'reference_number');

drop trigger if exists trg_audit_case_status on public.case_status;
create trigger trg_audit_case_status after insert or update on public.case_status
    for each row execute function public.fn_audit_trigger_redacted('reason');

drop trigger if exists trg_audit_task on public.task;
create trigger trg_audit_task after insert or update on public.task
    for each row execute function public.fn_audit_trigger_redacted('name', 'details');

-- ---------------------------------------------------------------- 2. Guarda de estatus: `reason` solo durante la anonimizacion
create or replace function public.fn_enforce_case_status_append_only()
returns trigger
language plpgsql as $$
begin
    -- Unica excepcion (ronda 2): durante la anonimizacion se puede suprimir el motivo (texto libre) de un estatus.
    -- Cualquier otro cambio sigue prohibido.
    if current_setting('bv.anonymizing', true) = 'on'
       and (to_jsonb(new) - 'reason') is not distinct from (to_jsonb(old) - 'reason') then
        return new;
    end if;
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
$$;

-- ---------------------------------------------------------------- 3. Anonimizacion con el catalogo completo
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
        religion_item_id = null,                          -- E14 f4a
        religion_detail = null,
        primary_language_item_id = null,
        education_level_item_id = null,                   -- E15 f1
        marital_status_item_id = null,
        origin_department_item_id = null,
        secondary_phone = null,                           -- ciclo Ingreso y expediente
        secondary_phone_label = null,
        identity_documents_presented = null,
        occupations = '{}',                               -- ronda 2: columna heredada
        education_level_id = null,                        -- ronda 2: espejos heredados de los *_item_id
        marital_status_id = null,
        origin_department_id = null,
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

    -- E14: el número de los documentos, la religión y el detalle de los marcadores se suprimen.
    -- Los documentos no se borran: quedan cerrados y sin número (el historial de que existieron).
    update public.person_document
    set document_number = '[SUPRIMIDO]',
        valid_to = coalesce(valid_to, now()),
        closed_by = coalesce(closed_by, v_user_id),
        change_reason = case when change_reason is not null then '[SUPRIMIDO - ADR-0001]' end
    where person_id = p_person_id;

    update public.case_vulnerability_marker
    set notes = null
    where case_id in (select id from public.case where titular_person_id = p_person_id);

    -- E15 f2: las respuestas de la ficha social se cierran y su texto y detalle se suprimen (pueden identificar)
    update public.social_answer
    set valid_to = coalesce(valid_to, now()),
        closed_by = coalesce(closed_by, v_user_id),
        change_reason = '[SUPRIMIDO - ADR-0001]',
        text_value = null,
        detail = null
    where case_id in (select id from public.case where titular_person_id = p_person_id);

    -- E15 f1: las ocupaciones se cierran; no se borran
    update public.person_occupation
    set valid_to = coalesce(valid_to, now()),
        closed_by = coalesce(closed_by, v_user_id),
        change_reason = '[SUPRIMIDO - ADR-0001]'
    where person_id = p_person_id;

    -- E14 f4b: las necesidades específicas (datos sensibles) se cierran; no se borran
    update public.case_need
    set valid_to = coalesce(valid_to, now()),
        closed_by = coalesce(closed_by, v_user_id),
        change_reason = '[SUPRIMIDO - ADR-0001]'
    where case_id in (select id from public.case where titular_person_id = p_person_id);

    -- E14 f3: la persona deja su familia (el folio de familia puede identificar a sus parientes). La pertenencia
    -- no se borra: queda cerrada, con el motivo suprimido.
    update public.family_member
    set valid_to = coalesce(valid_to, now()),
        closed_by = coalesce(closed_by, v_user_id),
        change_reason = '[SUPRIMIDO - ADR-0001]'
    where case_id in (select id from public.case where titular_person_id = p_person_id);

    -- Ronda 2 (ciberseguridad): texto libre del expediente y de sus registros, que puede nombrar a la persona o a sus parientes.
    update public.case
    set closure_reason = case when closure_reason is not null then '[SUPRIMIDO - ADR-0001]' end,
        legacy_reference = null,
        reference_number = null
    where titular_person_id = p_person_id;

    update public.case_date
    set change_reason = case when change_reason is not null then '[SUPRIMIDO - ADR-0001]' end
    where case_id in (select id from public.case where titular_person_id = p_person_id);

    update public.sharing_event
    set reason = '[SUPRIMIDO - ADR-0001]'
    where case_id in (select id from public.case where titular_person_id = p_person_id);

    update public.authority_request
    set official_letter_ref = 'REFERENCIA-' || substr(md5(id::text), 1, 8),
        response_summary = case when response_summary is not null then '[SUPRIMIDO - ADR-0001]' end
    where case_id in (select id from public.case where titular_person_id = p_person_id);

    -- Los motivos de los cambios de estatus son texto libre: se suprimen bajo la marca de anonimizacion (la guarda de
    -- estatus solo deja cambiar `reason` mientras esa marca esta encendida). Se hace ANTES de abrir los estatus terminales,
    -- cuyos motivos son textos fijos sin datos personales.
    perform set_config('bv.anonymizing', 'on', true);
    update public.case_status
    set reason = '[SUPRIMIDO - ADR-0001]'
    where case_id in (select id from public.case where titular_person_id = p_person_id);
    perform set_config('bv.anonymizing', 'off', true);

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
