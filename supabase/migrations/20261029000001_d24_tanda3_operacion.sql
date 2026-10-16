-- ==============================================================================
-- D-24 tanda 3 · Operación como capacidades
--
-- Contexto: tres permisos de trabajo diario seguían escritos por nombre de rol. Decisión del Product Owner (23 oct 2026):
-- migrarlos a capacidades configurables **sin cambiar el comportamiento por omisión**.
--
-- Capacidades nuevas (el catálogo pasa de nueve a doce):
--  * `open_cases`           abrir expedientes y subfolios (`fn_create_case_with_person`, `fn_create_subfolio`).
--                           Por omisión: los roles de dirección e ingreso.
--  * `rectify_person_data`  rectificar los datos de una persona y registrar su religión (`fn_rectify_person`,
--                           `fn_set_person_religion`). Por omisión: los roles de dirección e ingreso.
--  * `change_legal_status`  cambiar el estatus jurídico (`fn_change_case_status`, solo el eje `legal_status`).
--                           Por omisión: el rol de dirección y el **área jurídica**.
--
-- Notas
--  * Se nombró `change_legal_status` y no `change_case_status` porque cubre solo el estatus jurídico: **cerrar y reabrir el
--    expediente siguen siendo facultad exclusiva de dirección** (BV111, BV112), sin permiso configurable.
--  * Un permiso concedido a un área vale para quien tiene un rol operativo (dirección, ingreso o atención) en ella. Antes, el
--    estatus jurídico lo cambiaba solo el rol de atención del área jurídica; ahora, quien tenga cualquier rol operativo en esa
--    área. La dirección puede acotarlo desde la pantalla de permisos.
--  * Los textos de error de BV110, BV113, BV114, BV119 y BV121 ahora hablan del permiso y no del rol.
-- ==============================================================================

insert into public.capability (code, description_es, sort_order) values
    ('open_cases', 'Abrir expedientes y subfolios', 10),
    ('rectify_person_data', 'Rectificar los datos de una persona y registrar su religión', 11),
    ('change_legal_status', 'Cambiar el estatus jurídico de un expediente (cerrar y reabrir siguen siendo de dirección)', 12)
on conflict (code) do update set description_es = excluded.description_es, sort_order = excluded.sort_order;

create or replace function public.fn_seed_default_capabilities(p_org uuid)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_code text;
    v_area uuid;
begin
    -- Dirección: todas las capacidades
    foreach v_code in array array['manage_catalogs', 'manage_team', 'view_audit', 'manage_authority_requests', 'manage_org_settings',
                                  'manage_areas', 'manage_status_catalog', 'manage_task_catalogs', 'manage_task_settings',
                                  'open_cases', 'rectify_person_data', 'change_legal_status'] loop
        insert into public.capability_grant (organization_id, capability_code, role_name, grant_reason)
        select p_org, v_code, 'director', 'Valor por omisión'
        where not exists (
            select 1 from public.capability_grant g
            where g.organization_id = p_org and g.capability_code = v_code and g.role_name = 'director' and g.revoked_at is null
        );
    end loop;
    -- Ingreso abre y rectifica (como antes)
    foreach v_code in array array['open_cases', 'rectify_person_data'] loop
        insert into public.capability_grant (organization_id, capability_code, role_name, grant_reason)
        select p_org, v_code, 'intake_officer', 'Valor por omisión'
        where not exists (
            select 1 from public.capability_grant g
            where g.organization_id = p_org and g.capability_code = v_code and g.role_name = 'intake_officer' and g.revoked_at is null
        );
    end loop;
    -- Áreas: Trabajo Social administra diccionarios; el área jurídica cambia el estatus jurídico
    select id into v_area from public.area where organization_id = p_org and code = 'trabajo_social' limit 1;
    if v_area is not null then
        insert into public.capability_grant (organization_id, capability_code, area_id, grant_reason)
        select p_org, 'manage_catalogs', v_area, 'Valor por omisión'
        where not exists (
            select 1 from public.capability_grant g
            where g.organization_id = p_org and g.capability_code = 'manage_catalogs' and g.area_id = v_area and g.revoked_at is null
        );
    end if;
    select id into v_area from public.area where organization_id = p_org and code = 'legal' limit 1;
    if v_area is not null then
        insert into public.capability_grant (organization_id, capability_code, area_id, grant_reason)
        select p_org, 'change_legal_status', v_area, 'Valor por omisión'
        where not exists (
            select 1 from public.capability_grant g
            where g.organization_id = p_org and g.capability_code = 'change_legal_status' and g.area_id = v_area and g.revoked_at is null
        );
    end if;
end;
$$;
revoke execute on function public.fn_seed_default_capabilities(uuid) from public, anon, authenticated;

select public.fn_seed_default_capabilities(o.id) from public.organization o;

-- ---------------------------------------------------------------- fn_create_case_with_person
CREATE OR REPLACE FUNCTION public.fn_create_case_with_person(p_given_name text, p_paternal_family_name text, p_maternal_family_name text, p_preferred_name text, p_birth_date date, p_birth_date_is_estimated boolean, p_sex_id integer, p_nationality_country_id integer, p_other_nationality text, p_primary_language_item_id uuid, p_other_language text, p_phone_number text, p_intake_window_type text, p_travels_with_family boolean, p_intake_state_id integer, p_intake_municipality_key text, p_intake_channel_id integer, p_entry_route_id integer, p_entry_date_str text, p_assigned_area_id uuid, p_vulnerability_codes text[], p_consents jsonb DEFAULT '[]'::jsonb, p_dates jsonb DEFAULT '[]'::jsonb, p_education_level_item_id uuid DEFAULT NULL::uuid, p_marital_status_item_id uuid DEFAULT NULL::uuid, p_origin_department_item_id uuid DEFAULT NULL::uuid, p_occupation_item_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
    -- Antes lo decidía la política de INSERT (intake_officer y director); ahora lo exige la función.
    if auth.uid() is null
       or public.current_organization_id() is null
       or not public.has_capability('open_cases') then
        raise exception 'Acceso denegado: se requiere el permiso de abrir expedientes (por omisión, ingreso y dirección).' using errcode = 'BV113';
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
        p_other_nationality, p_primary_language_item_id, p_other_language, p_phone_number,
        p_intake_window_type, p_travels_with_family, p_intake_state_id, p_intake_municipality_key,
        p_intake_channel_id, p_entry_route_id, p_entry_date_str, p_assigned_area_id,
        p_vulnerability_codes, p_consents, p_dates,
        p_education_level_item_id, p_marital_status_item_id, p_origin_department_item_id, p_occupation_item_ids
    );
end;
$function$;

-- ---------------------------------------------------------------- fn_create_subfolio
CREATE OR REPLACE FUNCTION public.fn_create_subfolio(p_parent_case_id uuid, p_given_name text, p_paternal_family_name text, p_maternal_family_name text, p_preferred_name text, p_birth_date date, p_birth_date_is_estimated boolean, p_sex_id integer, p_nationality_country_id integer, p_other_nationality text, p_primary_language_item_id uuid, p_other_language text, p_guardian_role text, p_justification text, p_vulnerability_codes text[], p_consents jsonb)
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
    if not public.has_capability('open_cases') then
        raise exception 'Permiso denegado: se requiere el permiso de abrir expedientes (por omisión, ingreso y dirección).' using errcode = 'BV114';
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
    perform public.fn_assert_consent_statuses(p_consents);

    select
        coalesce(bool_or(c->>'consent_type' = 'general_care' and (c->>'status') = 'granted'), false),
        coalesce(bool_or(c->>'consent_type' = 'sensitive_data' and (c->>'status') = 'granted'), false)
    into v_has_general, v_has_sensitive
    from jsonb_array_elements(p_consents) c;

    if not v_has_general then
        raise exception 'Sin consentimiento general informado no se abre expediente; el auxilio humanitario inmediato no se condiciona (Ethos C2, BV-5.1).' using errcode = 'BV401';
    end if;
    -- E14 f4a: el idioma es un valor del diccionario (el «no quiso responder» no es un dato sensible) y su detalle lo acompaña
    if p_primary_language_item_id is not null then
        perform public.fn_assert_catalog_item(v_org_id, 'language', p_primary_language_item_id);
    end if;
    if nullif(trim(coalesce(p_other_language, '')), '') is not null
       and (p_primary_language_item_id is null or public.fn_catalog_item_is_no_response(p_primary_language_item_id)) then
        raise exception 'El detalle del idioma necesita un valor del diccionario que lo explique.' using errcode = 'BV333';
    end if;

    -- D-14: sexo, nacionalidad y lengua solo con consentimiento sensible vigente; sin él, no se aceptan
    if not v_has_sensitive and (
        p_sex_id is not null
        or p_nationality_country_id is not null or nullif(trim(coalesce(p_other_nationality, '')), '') is not null
        or (p_primary_language_item_id is not null and not public.fn_catalog_item_is_no_response(p_primary_language_item_id)) or nullif(trim(coalesce(p_other_language, '')), '') is not null
    ) then
        raise exception 'Control P-06: sexo, nacionalidad y lengua son datos sensibles y exigen consentimiento sensible.' using errcode = 'BV402';
    end if;
    -- El asentimiento de la niña o el niño es el que se capturó; ya no se da por hecho
    if not exists (select 1 from jsonb_array_elements(p_consents) c where coalesce((c->>'is_minor_assent')::boolean, false)) then
        raise exception 'Persona menor de 18 años: el consentimiento exige asentimiento y la identidad de su representante (BV-5.1).' using errcode = 'BV403';
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
        birth_date, birth_date_is_estimated, sex_id, nationality_country_id, other_nationality, primary_language_item_id, other_language
    ) values (
        v_org_id, trim(p_given_name), trim(p_paternal_family_name), nullif(trim(p_maternal_family_name), ''),
        nullif(trim(p_preferred_name), ''), p_birth_date, coalesce(p_birth_date_is_estimated, false), p_sex_id,
        p_nationality_country_id, nullif(trim(p_other_nationality), ''), p_primary_language_item_id, nullif(trim(p_other_language), '')
    ) returning id into v_person_id;

    insert into public."case" (
        organization_id, case_number, parent_case_id, titular_person_id, intake_state_id,
        intake_municipality_key, intake_channel_id, intake_window_type, entry_route_id, entry_date_str,
        travels_with_family, opened_by, assigned_area_id, assigned_user_id
    ) values (
        v_org_id, v_number, p_parent_case_id, v_person_id, v_parent.intake_state_id,
        v_parent.intake_municipality_key, v_parent.intake_channel_id, v_parent.intake_window_type, v_parent.entry_route_id, v_parent.entry_date_str,
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
            v_consent->>'status',
            v_case_id,
            coalesce((v_consent->>'is_minor_assent')::boolean, false),
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

-- ---------------------------------------------------------------- fn_rectify_person
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
    if v_user_id is null or not public.has_capability('rectify_person_data') then
        raise exception 'Acceso denegado: La rectificación de datos biográficos requiere el permiso de rectificar datos de una persona (por omisión, dirección e ingreso).' using errcode = 'BV119';
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

    -- D-14: sexo, nacionalidad, teléfono y correo solo cambian con consentimiento sensible vigente (si el valor cambia)
    if not public.fn_person_has_sensitive_consent(p_person_id) and (
        (p_sex_id is not null and p_sex_id is distinct from v_person.sex_id)
        or (p_nationality_country_id is not null and p_nationality_country_id is distinct from v_person.nationality_country_id)
        or (nullif(trim(coalesce(p_phone_number, '')), '') is not null and nullif(trim(coalesce(p_phone_number, '')), '') is distinct from v_person.phone_number)
        or (nullif(trim(coalesce(p_email, '')), '') is not null and nullif(trim(coalesce(p_email, '')), '') is distinct from v_person.email)
    ) then
        raise exception 'Control P-06: sexo, nacionalidad, teléfono y correo son datos sensibles y exigen consentimiento sensible.' using errcode = 'BV402';
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

-- ---------------------------------------------------------------- fn_set_person_religion
create or replace function public.fn_set_person_religion(
    p_person_id uuid,
    p_item_id uuid,
    p_detail text,
    p_reason text default null
)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_person record;
    v_detail text := nullif(btrim(coalesce(p_detail, '')), '');
begin
    if v_user is null or public.current_organization_id() is null
       or not public.has_capability('rectify_person_data') then
        raise exception 'Acceso denegado: registrar la religión requiere el permiso de rectificar datos de una persona (por omisión, dirección e ingreso; D-14).' using errcode = 'BV121';
    end if;
    perform public.fn_assert_same_org('person', p_person_id);

    select * into v_person from public.person where id = p_person_id;
    if v_person.is_anonymized then
        raise exception 'Operación no permitida: una persona anonimizada no admite este dato (ADR-0001).' using errcode = 'BV507';
    end if;
    if v_detail is not null and char_length(v_detail) > 120 then
        raise exception 'El detalle excede los 120 caracteres.' using errcode = 'BV321';
    end if;
    if v_detail is not null and (p_item_id is null or public.fn_catalog_item_is_no_response(p_item_id)) then
        raise exception 'El detalle necesita un valor del diccionario que lo explique.' using errcode = 'BV333';
    end if;
    if p_item_id is not null then
        perform public.fn_assert_catalog_item(v_person.organization_id, 'religion', p_item_id);
        if not public.fn_catalog_item_is_no_response(p_item_id) and not public.fn_person_has_sensitive_consent(p_person_id) then
            raise exception 'Control P-06: la religión es un dato sensible y exige consentimiento sensible vigente (D-14).' using errcode = 'BV408';
        end if;
    end if;
    if p_item_id is not distinct from v_person.religion_item_id and v_detail is not distinct from v_person.religion_detail then
        return;
    end if;
    if (v_person.religion_item_id is not null or v_person.religion_detail is not null) and (p_reason is null or btrim(p_reason) = '') then
        raise exception 'El motivo es obligatorio al cambiar o quitar un dato ya registrado (Ethos C8).' using errcode = 'BV304';
    end if;

    update public.person set religion_item_id = p_item_id, religion_detail = v_detail, updated_at = now() where id = p_person_id;

    if v_person.religion_item_id is not null or v_person.religion_detail is not null then
        insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
        values (v_person.organization_id, v_user, 'RECTIFICATION', 'person', p_person_id,
                jsonb_build_object('changed_fields', jsonb_build_array('religion_item_id', 'religion_detail'), 'reason', btrim(p_reason)));
    end if;
end;
$$;

-- ---------------------------------------------------------------- fn_change_case_status
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
        if not public.has_capability('change_legal_status') then
            raise exception 'Permiso denegado: El estatus jurídico requiere el permiso de cambiarlo (por omisión, dirección y el Área Jurídica).' using errcode = 'BV110';
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

    -- E14 f2b: «albergada» (ingreso) y «salida del albergue» (egreso) llevan la fecha del movimiento; solo se alcanzan
    -- por fn_change_shelter_status, que registra el estatus y la fecha en una sola operación
    if p_axis_code = 'shelter_status' and p_new_value_code in ('sheltered', 'left_shelter')
       and coalesce(current_setting('bv.shelter_date', true), '') <> 'on' then
        raise exception 'El ingreso y la salida del albergue llevan la fecha del movimiento: usa el cambio de alojamiento con fecha.' using errcode = 'BV328';
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
