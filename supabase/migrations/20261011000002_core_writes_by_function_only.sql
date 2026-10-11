-- ==============================================================================
-- Escritura del núcleo SOLO por funciones (Reglas Duras 1, 5 y 6; Ethos C3, C4, C5)
--
-- Hallazgo A-1 de la auditoría del 11 oct 2026
-- (30_entrega/reporte-auditoria-endurecimiento-2026-10-11.md): la interfaz escribe por
-- funciones, pero `authenticated` conservaba INSERT/UPDATE directos sobre las tablas del
-- núcleo. Quien tuviera la clave pública y una sesión podía llamar a la API sin pasar por
-- la interfaz y saltarse lo que sólo vive en las funciones: consentimiento previo (P-06),
-- motivo, compartir con sharing_event (P-09), autoría y auditoría.
--
-- Qué hace
--  * Revoca INSERT y UPDATE a anon y authenticated en las tablas de datos del núcleo.
--    Las funciones security definer (las únicas escritoras) siguen funcionando.
--  * fn_create_case_with_person era la única escritora con los privilegios de quien llama
--    (SECURITY INVOKER: dependía de las políticas de INSERT). Pasa a security definer
--    con su propia guarda de sesión y rol; el cuerpo existente se conserva como función
--    interna no ejecutable por los roles de aplicación.
--
-- Alcance. Quedan bajo RLS de dirección (sin cambio) las tablas de identidad y catálogo
-- (user_role, user_profile, area, status_axis, status_value, authority_request): hoy no
-- tienen función de escritura y su administración llega con E11 y BV-2.1, que las traerán
-- con sus funciones. Revocarlas ahora dejaría sin ruta la gestión de roles.
-- ==============================================================================

-- 1. fn_create_case_with_person: security definer con guarda propia
alter function public.fn_create_case_with_person(
    text, text, text, text, date, boolean, int, int, text, int, text, text,
    text, boolean, int, int, int, int, text, uuid, text[], jsonb
) rename to fn_create_case_with_person_impl;

alter function public.fn_create_case_with_person_impl(
    text, text, text, text, date, boolean, int, int, text, int, text, text,
    text, boolean, int, int, int, int, text, uuid, text[], jsonb
) security definer set search_path = public;

revoke execute on function public.fn_create_case_with_person_impl(
    text, text, text, text, date, boolean, int, int, text, int, text, text,
    text, boolean, int, int, int, int, text, uuid, text[], jsonb
) from public, anon, authenticated;

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
security definer
set search_path = public
language plpgsql as $$
begin
    -- Antes lo decidía la política de INSERT (intake_officer y director); ahora lo exige la función.
    if auth.uid() is null
       or public.current_organization_id() is null
       or not (public.has_role('intake_officer') or public.has_role('director')) then
        raise exception 'Acceso denegado: solo ingreso y dirección abren expedientes (BV-3.1).';
    end if;

    -- El área asignada, si se indica, debe ser de la misma organización
    if p_assigned_area_id is not null and not exists (
        select 1 from public.area a
        where a.id = p_assigned_area_id and a.organization_id = public.current_organization_id()
    ) then
        raise exception 'Área no válida para esta organización.';
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
$$;

revoke execute on function public.fn_create_case_with_person(
    text, text, text, text, date, boolean, int, int, text, int, text, text,
    text, boolean, int, int, int, int, text, uuid, text[], jsonb
) from public, anon;
grant execute on function public.fn_create_case_with_person(
    text, text, text, text, date, boolean, int, int, text, int, text, text,
    text, boolean, int, int, int, int, text, uuid, text[], jsonb
) to authenticated;

-- 2. Sin escritura directa en el núcleo
revoke insert, update on
    public.person,
    public."case",
    public.case_status,
    public.case_vulnerability_marker,
    public.journal_entry,
    public.sharing_event,
    public.attachment,
    public.consent,
    public.arco_request
from anon, authenticated;
