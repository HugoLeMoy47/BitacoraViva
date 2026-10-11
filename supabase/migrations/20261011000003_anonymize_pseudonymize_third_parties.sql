-- ==============================================================================
-- Anonimizar también pseudonimiza a terceros en consentimientos y solicitudes ARCO
-- (Ethos C7, ADR-0001) · hallazgo L-1 de la auditoría del 11 oct 2026
--
-- Decisión del Product Owner (11 oct 2026): pseudonimizar. Al anonimizar a una persona,
-- los nombres y referencias que identifican a terceros (tutor, representante, solicitante)
-- o a la propia persona dentro de sus consentimientos y solicitudes ARCO dejan de ser
-- legibles, pero el registro SIGUE existiendo como evidencia de que hubo un consentimiento,
-- de qué tipo, cuándo y con qué estado:
--   consent      · legal_guardian_name, authority_letter_ref  -> seudónimo estable (huella corta)
--                · notes, revocation_reason                   -> texto suprimido
--   arco_request · requested_by_name                          -> seudónimo estable
--                · details, reason, resolution_notes          -> texto suprimido
-- El seudónimo es una huella del identificador del propio registro (no del nombre), así que
-- no se puede revertir al valor original.
--
-- Es la única vía: fn_anonymize_person es security definer y los roles de aplicación ya no
-- escriben estas tablas directamente (migración 000002).
-- ==============================================================================

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
$$;
