-- ==============================================================================
-- BV-3.1 Alta atomica de persona + caso + marcadores de vulnerabilidad
-- SECURITY INVOKER: las politicas RLS de person, case y
-- case_vulnerability_marker siguen decidiendo quien puede abrir casos
-- (intake_officer y director). La funcion solo aporta la atomicidad: o se crea
-- todo, o no se crea nada. Los disparadores de auditoria y de estatus inicial
-- actuan igual que con inserts directos (Reglas Duras 5 y 7).
-- ==============================================================================

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
    p_vulnerability_codes text[]
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
begin
    v_org_id := public.current_organization_id();
    if v_user_id is null or v_org_id is null then
        raise exception 'Acceso denegado: sesion sin organizacion asociada.';
    end if;

    if p_given_name is null or trim(p_given_name) = ''
       or p_paternal_family_name is null or trim(p_paternal_family_name) = '' then
        raise exception 'Nombre y primer apellido son obligatorios.';
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

    return v_case_id;
end;
$$;

revoke execute on function public.fn_create_case_with_person from public, anon;
grant execute on function public.fn_create_case_with_person to authenticated;
