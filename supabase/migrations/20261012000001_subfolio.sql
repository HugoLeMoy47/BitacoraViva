-- ==============================================================================
-- BV-3.2 · Subfolio de niñez y adolescencia acompañadas
--
-- Un subfolio es un expediente propio (bitácora y estatus propios) colgado del caso de la persona
-- adulta responsable. Decisiones del Product Owner (12 oct 2026):
--   * Lo crean solo ingreso y dirección.
--   * El folio es el del caso padre con sufijo: -S1, -S2, -S3… (nunca se reutiliza un número).
--   * Quien representa a la persona menor es quien tiene el folio principal (madre, padre o tutor):
--     la base toma su nombre del caso padre; el cliente solo dice el parentesco.
--   * Los consentimientos llegan prellenados con la decisión de la persona representante y se pueden
--     ajustar, pero la nota de justificación es obligatoria y queda en la bitácora del subfolio.
--
-- Una sola función con las mismas guardas que el alta (sesión, rol, organización, consentimiento
-- general, P-06 para marcadores) más las propias del subfolio. Como el alta, escribe con los
-- privilegios del propietario porque las tablas núcleo ya no admiten INSERT directo (migración 02).
-- ==============================================================================

create or replace function public.fn_create_subfolio(
    p_parent_case_id uuid,
    p_given_name text,
    p_paternal_family_name text,
    p_maternal_family_name text,
    p_preferred_name text,
    p_birth_date date,
    p_birth_date_is_estimated boolean,
    p_sex_id int,
    p_nationality_country_id int,
    p_other_nationality text,
    p_primary_language_id int,
    p_other_language text,
    p_guardian_role text,
    p_justification text,
    p_vulnerability_codes text[],
    p_consents jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
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
        raise exception 'Acceso denegado: sesion sin organizacion asociada.';
    end if;
    if not (public.has_role('intake_officer') or public.has_role('director')) then
        raise exception 'Permiso denegado: solo ingreso y dirección crean subfolios (BV-3.2).';
    end if;

    -- El caso padre: de la misma organización, abierto y principal. Se bloquea para que dos altas
    -- simultáneas no tomen el mismo número de subfolio.
    perform public.fn_assert_same_org('case', p_parent_case_id);
    select * into v_parent from public."case" where id = p_parent_case_id for update;
    if v_parent.id is null then
        raise exception 'Expediente no encontrado.';
    end if;
    if v_parent.parent_case_id is not null then
        raise exception 'Un subfolio no admite subfolios (profundidad máxima 1).';
    end if;
    if v_parent.closed_at is not null then
        raise exception 'El caso padre está cerrado: no se le pueden abrir subfolios.';
    end if;

    -- Quien representa es la persona titular del caso padre, y debe ser adulta
    select * into v_titular from public.person where id = v_parent.titular_person_id;
    if v_titular.birth_date is not null and v_titular.birth_date > current_date - interval '18 years' then
        raise exception 'Quien representa a la persona menor debe ser una persona adulta.';
    end if;
    v_guardian_name := concat_ws(' ', v_titular.given_name, v_titular.paternal_family_name, v_titular.maternal_family_name);

    if p_given_name is null or trim(p_given_name) = '' or p_paternal_family_name is null or trim(p_paternal_family_name) = '' then
        raise exception 'Nombre y primer apellido son obligatorios.';
    end if;
    if p_birth_date is null or p_birth_date <= current_date - interval '18 years' then
        raise exception 'El subfolio es para niñez y adolescencia: la persona debe ser menor de 18 años.';
    end if;
    if p_guardian_role is null or trim(p_guardian_role) = '' then
        raise exception 'Indica el parentesco de quien representa a la persona menor.';
    end if;
    if p_justification is null or length(trim(p_justification)) < 10 then
        raise exception 'La nota de justificación es obligatoria (mínimo 10 caracteres).';
    end if;
    if jsonb_typeof(coalesce(p_consents, 'null'::jsonb)) is distinct from 'array' then
        raise exception 'Los consentimientos deben enviarse como arreglo.';
    end if;

    select
        coalesce(bool_or(c->>'consent_type' = 'general_care' and coalesce(c->>'status', 'granted') = 'granted'), false),
        coalesce(bool_or(c->>'consent_type' = 'sensitive_data' and coalesce(c->>'status', 'granted') = 'granted'), false)
    into v_has_general, v_has_sensitive
    from jsonb_array_elements(p_consents) c;

    if not v_has_general then
        raise exception 'Sin consentimiento general informado no se abre expediente; el auxilio humanitario inmediato no se condiciona (Ethos C2, BV-5.1).';
    end if;
    if coalesce(array_length(p_vulnerability_codes, 1), 0) > 0 and not v_has_sensitive then
        raise exception 'Control P-06: no se capturan marcadores de vulnerabilidad sin consentimiento expreso para datos sensibles.';
    end if;
    if 'unaccompanied_child' = any (coalesce(p_vulnerability_codes, '{}'::text[])) then
        raise exception 'El subfolio es para niñez acompañada: el marcador de niñez no acompañada va en un expediente propio con su autoridad.';
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
        raise exception 'No se pudo determinar el área operativa para la nota de justificación.';
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
$$;

revoke execute on function public.fn_create_subfolio(
    uuid, text, text, text, text, date, boolean, int, int, text, int, text, text, text, text[], jsonb
) from public, anon;
grant execute on function public.fn_create_subfolio(
    uuid, text, text, text, text, date, boolean, int, int, text, int, text, text, text, text[], jsonb
) to authenticated;
