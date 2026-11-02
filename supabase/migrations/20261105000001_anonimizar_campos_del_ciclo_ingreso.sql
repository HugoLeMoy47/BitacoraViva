-- ==============================================================================
-- La anonimización también limpia lo que agregó el ciclo «Ingreso y expediente» (migración 20261103000001)
--
-- `fn_anonymize_person` (ADR-0001) destruye los identificadores directos, pero se escribió antes de que existieran el segundo
-- teléfono, su etiqueta y los documentos con que se identifica la persona: una persona anonimizada conservaba su segundo
-- teléfono. Aquí se redefine la función igual que la versión vigente (migración 20261023000001) más esas tres columnas.
--
--  * Se limpian: `secondary_phone`, `secondary_phone_label` (la etiqueta exige número: `person_secondary_phone_label_check`)
--    e `identity_documents_presented`.
--  * Se conserva `nationality_iso`: es esqueleto estadístico, como `nationality_country_id` (ADR-0001, punto 2: «nacionalidad»).
--
-- Pendiente aparte (fase de fotografía, D-19): cuando exista la lectura de fotografías, anonimizar deberá borrar también los
-- archivos de `dossier-photos` del caso. Hoy no hay interfaz que los suba.
-- ==============================================================================

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
