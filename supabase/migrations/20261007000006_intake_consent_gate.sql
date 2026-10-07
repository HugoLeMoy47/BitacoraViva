-- ==============================================================================
-- Paso cero del alta: aviso de privacidad y consentimiento explícito (BV-5.1, P-06)
--
-- El alta ya no presupone consentimientos: la función recibe los que la persona
-- otorgó (p_consents) y los asienta en la MISMA transacción que la persona y el caso.
-- Reglas que impone la base (no la interfaz):
--   * sin consentimiento general informado no se abre expediente (el auxilio humanitario
--     inmediato no se condiciona; Ethos C2) -> la organización lo atiende sin registro;
--   * sin consentimiento EXPRESO para datos sensibles no se capturan marcadores de
--     vulnerabilidad (control P-06). Alcance por ahora: marcadores del alta;
--     la lista completa de "campos sensibles" queda por definir con Producto;
--   * persona menor de 18 años: el consentimiento exige asentimiento y representante;
--   * marcador de niñez no acompañada: exige identidad de la autoridad/tutor y oficio.
--
-- p_consents: arreglo JSON de objetos
--   { consent_type, status?, is_minor_assent?, legal_guardian_name?,
--     legal_guardian_role?, authority_letter_ref?, notes? }
-- SECURITY INVOKER: RLS sigue decidiendo quién abre casos (intake_officer y director).
-- ==============================================================================

drop function if exists public.fn_create_case_with_person(
    text, text, text, text, date, boolean, int, int, text, int, text, text,
    text, boolean, int, int, int, int, text, uuid, text[]
);

create or replace function public.fn_create_case_with_person(
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
    p_phone_number text,
    p_intake_window_type text,
    p_travels_with_family boolean,
    p_intake_state_id int,
    p_intake_municipality_id int,
    p_intake_channel_id int,
    p_entry_route_id int,
    p_entry_date_str text,
    p_assigned_area_id uuid,
    p_vulnerability_codes text[],
    p_consents jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
set search_path = public
as $$
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
        raise exception 'Acceso denegado: sesion sin organizacion asociada.';
    end if;

    if p_given_name is null or trim(p_given_name) = ''
       or p_paternal_family_name is null or trim(p_paternal_family_name) = '' then
        raise exception 'Nombre y primer apellido son obligatorios.';
    end if;

    if jsonb_typeof(coalesce(p_consents, 'null'::jsonb)) is distinct from 'array' then
        raise exception 'Los consentimientos deben enviarse como arreglo.';
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
        raise exception 'Sin consentimiento general informado no se abre expediente; el auxilio humanitario inmediato no se condiciona (Ethos C2, BV-5.1).';
    end if;

    if coalesce(array_length(p_vulnerability_codes, 1), 0) > 0 and not v_has_sensitive then
        raise exception 'Control P-06: no se capturan marcadores de vulnerabilidad sin consentimiento expreso para datos sensibles.';
    end if;

    if p_birth_date > current_date - interval '18 years' and not (v_has_minor_assent and v_has_guardian) then
        raise exception 'Persona menor de 18 años: el consentimiento exige asentimiento y la identidad de su representante (BV-5.1).';
    end if;

    if 'unaccompanied_child' = any (coalesce(p_vulnerability_codes, '{}'::text[])) and not v_has_authority then
        raise exception 'Niñez no acompañada: se requiere la identidad de la autoridad o tutor y la referencia de su oficio (BV-5.1).';
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
$$;

revoke execute on function public.fn_create_case_with_person(
    text, text, text, text, date, boolean, int, int, text, int, text, text,
    text, boolean, int, int, int, int, text, uuid, text[], jsonb
) from public, anon;
grant execute on function public.fn_create_case_with_person(
    text, text, text, text, date, boolean, int, int, text, int, text, text,
    text, boolean, int, int, int, int, text, uuid, text[], jsonb
) to authenticated;
