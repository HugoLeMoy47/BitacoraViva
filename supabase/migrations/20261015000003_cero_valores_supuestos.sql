-- ==============================================================================
-- E14 fase 1b · Cero valores supuestos y bloqueo de campos sensibles (D-14)
--
-- Decisión del Product Owner (15 oct 2026): para acercarse a operación real, ningún dato por defecto. Si un campo
-- es obligatorio y no está resuelto, el sistema detiene; si no es obligatorio, queda vacío («No registrado» en
-- pantalla). Inventario: 30_entrega/inventario-valores-supuestos-2026-10-15.md.
--
-- Qué hace
--  * Quita los valores por defecto y el NOT NULL de los datos de la persona y del contexto de ingreso del caso:
--    sexo, nacionalidad, lengua, «se considera migrante», estado, canal, vía de ingreso y «viaja con familia».
--    El tipo de ventanilla y el estado de un consentimiento se vuelven obligatorios SIN valor por defecto.
--  * Contexto de ingreso real: estado (INEGI), municipio (clave INEGI de 5 dígitos, `intake_municipality_key`),
--    canal y vía de ingreso (catálogos por organización que editan dirección y Trabajo Social). La columna
--    `intake_municipality_id` (identificador de MAP-OIM, con valor inventado) se elimina.
--  * Candado D-14: sexo, nacionalidad, lengua y teléfono solo se aceptan con consentimiento sensible vigente
--    (BV402), en el alta, en el subfolio y al rectificar (solo si el valor CAMBIA).
--  * Un consentimiento sin estado ya no se guarda como «concedido» (BV322). El asentimiento de la niña o el niño
--    en el subfolio ya no se fuerza a «sí»: se toma de lo que se capturó, y sin asentimiento no se abre (BV403).
--  * Indicadores: el sexo vacío cuenta como «sin dato».
--  * Errores con código estable (E13): BV214, BV215, BV216, BV217, BV322, BV323, BV324.
--
-- Los datos que ya estaban guardados no se tocan: no hay forma de saber cuáles fueron supuestos.
-- Idempotente: el reinicio de la demo reaplica todas las migraciones.
-- ==============================================================================

-- ---------------------------------------------------------------- 1. Catálogos de ingreso por organización
create table if not exists public.intake_channel (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    code int not null check (code > 0),
    label_es text not null check (char_length(btrim(label_es)) between 1 and 80),
    is_active boolean not null default true,
    sort_order int not null default 0,
    unique (organization_id, code)
);
create table if not exists public.entry_route (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    code int not null check (code > 0),
    label_es text not null check (char_length(btrim(label_es)) between 1 and 80),
    is_active boolean not null default true,
    sort_order int not null default 0,
    unique (organization_id, code)
);

do $$
declare
    t text;
begin
    foreach t in array array['intake_channel', 'entry_route'] loop
        execute format('alter table public.%I enable row level security', t);
        execute format('revoke all on public.%I from anon', t);
        execute format('revoke delete on public.%I from authenticated', t);
        execute format('drop policy if exists "Roles vigentes ven el catálogo" on public.%I', t);
        execute format('create policy "Roles vigentes ven el catálogo" on public.%I for select to authenticated
                        using (organization_id = public.current_organization_id() and public.has_any_role())', t);
        execute format('drop policy if exists "Dirección y Trabajo Social administran el catálogo" on public.%I', t);
        execute format('create policy "Dirección y Trabajo Social administran el catálogo" on public.%I for all to authenticated
                        using (organization_id = public.current_organization_id() and public.can_manage_catalogs())
                        with check (organization_id = public.current_organization_id() and public.can_manage_catalogs())', t);
        execute format('drop trigger if exists trg_audit_%s on public.%I', t, t);
        execute format('create trigger trg_audit_%s after insert or update on public.%I
                        for each row execute function public.fn_audit_trigger_fields()', t, t);
    end loop;
end $$;

-- Valores de MAP-OIM v3 (map-oim-v3-spec.md), los mismos números que ya usaban los casos. Dirección y Trabajo Social los editan.
insert into public.intake_channel (organization_id, code, label_es, sort_order)
select o.id, v.code, v.label_es, v.code
from public.organization o
cross join (values (1, 'Empresa'), (2, 'Gobierno'), (3, 'Organización de la sociedad civil'),
                   (4, 'Organismo internacional'), (5, 'Ventanilla'), (6, 'Ninguna')) as v(code, label_es)
on conflict (organization_id, code) do nothing;

insert into public.entry_route (organization_id, code, label_es, sort_order)
select o.id, v.code, v.label_es, v.code
from public.organization o
cross join (values (1, 'Aérea'), (2, 'Marítima'), (3, 'Terrestre')) as v(code, label_es)
on conflict (organization_id, code) do nothing;

-- ---------------------------------------------------------------- 2. Sin valores por defecto
alter table public.person
    alter column sex_id drop not null, alter column sex_id drop default,
    alter column nationality_country_id drop not null, alter column nationality_country_id drop default,
    alter column primary_language_id drop not null, alter column primary_language_id drop default,
    alter column is_self_identified_migrant drop not null, alter column is_self_identified_migrant drop default;

alter table public."case"
    alter column intake_state_id drop not null, alter column intake_state_id drop default,
    alter column intake_channel_id drop not null, alter column intake_channel_id drop default,
    alter column entry_route_id drop not null, alter column entry_route_id drop default,
    alter column travels_with_family drop not null, alter column travels_with_family drop default,
    alter column intake_window_type drop default;

alter table public."case" drop column if exists intake_municipality_id;
alter table public."case" add column if not exists intake_municipality_key text references public.geo_municipality(cvegeo);

alter table public.consent alter column status drop default;

-- ---------------------------------------------------------------- 3. Validación del contexto de ingreso
-- Interna: la usa el alta. No ejecutable por los roles de aplicación.
create or replace function public.fn_assert_intake_context(
    p_org uuid, p_state int, p_municipality text, p_channel int, p_route int
)
returns void
security definer
set search_path = public
language plpgsql as $$
begin
    if p_state is not null and not exists (select 1 from public.geo_state s where s.cve_ent = lpad(p_state::text, 2, '0')) then
        raise exception 'El estado no existe en el catálogo oficial.' using errcode = 'BV214';
    end if;
    if p_municipality is not null then
        if not exists (select 1 from public.geo_municipality m where m.cvegeo = p_municipality) then
            raise exception 'El municipio no existe en el catálogo oficial.' using errcode = 'BV215';
        end if;
        if p_state is not null and left(p_municipality, 2) <> lpad(p_state::text, 2, '0') then
            raise exception 'El municipio no pertenece al estado indicado.' using errcode = 'BV215';
        end if;
    end if;
    if p_channel is not null and not exists (
        select 1 from public.intake_channel c where c.organization_id = p_org and c.code = p_channel and c.is_active
    ) then
        raise exception 'El canal de procedencia no existe o está retirado.' using errcode = 'BV216';
    end if;
    if p_route is not null and not exists (
        select 1 from public.entry_route r where r.organization_id = p_org and r.code = p_route and r.is_active
    ) then
        raise exception 'La vía de ingreso no existe o está retirada.' using errcode = 'BV217';
    end if;
end;
$$;
revoke execute on function public.fn_assert_intake_context(uuid, int, text, int, int) from public, anon, authenticated;

-- Estado de cada consentimiento recibido: siempre explícito (antes, sin estado, se guardaba como «concedido»)
create or replace function public.fn_assert_consent_statuses(p_consents jsonb)
returns void
security definer
set search_path = public
language plpgsql as $$
begin
    if exists (
        select 1 from jsonb_array_elements(p_consents) c
        where c->>'status' is null or c->>'status' not in ('granted', 'revoked', 'opposed')
    ) then
        raise exception 'Cada consentimiento debe indicar su estado (concedido, retirado o con oposición).' using errcode = 'BV322';
    end if;
end;
$$;
revoke execute on function public.fn_assert_consent_statuses(jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------- 4. Funciones (a partir de la definición vigente, 20261014000001)

-- El alta cambia de firma (el municipio pasa de identificador de MAP-OIM a clave del INEGI): se retiran las anteriores
drop function if exists public.fn_create_case_with_person(text, text, text, text, date, boolean, int, int, text, int, text, text, text, boolean, int, int, int, int, text, uuid, text[], jsonb);
drop function if exists public.fn_create_case_with_person_impl(text, text, text, text, date, boolean, int, int, text, int, text, text, text, boolean, int, int, int, int, text, uuid, text[], jsonb);

CREATE OR REPLACE FUNCTION public.fn_create_case_with_person_impl(p_given_name text, p_paternal_family_name text, p_maternal_family_name text, p_preferred_name text, p_birth_date date, p_birth_date_is_estimated boolean, p_sex_id integer, p_nationality_country_id integer, p_other_nationality text, p_primary_language_id integer, p_other_language text, p_phone_number text, p_intake_window_type text, p_travels_with_family boolean, p_intake_state_id integer, p_intake_municipality_key text, p_intake_channel_id integer, p_entry_route_id integer, p_entry_date_str text, p_assigned_area_id uuid, p_vulnerability_codes text[], p_consents jsonb DEFAULT '[]'::jsonb)
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
    perform public.fn_assert_consent_statuses(p_consents);

    if p_birth_date is null then
        raise exception 'La fecha de nacimiento es obligatoria.' using errcode = 'BV324';
    end if;
    if p_intake_window_type is null or p_intake_window_type not in ('fija', 'movil', 'transaccional') then
        raise exception 'El tipo de ventanilla es obligatorio.' using errcode = 'BV323';
    end if;
    perform public.fn_assert_intake_context(v_org_id, p_intake_state_id, p_intake_municipality_key, p_intake_channel_id, p_entry_route_id);

    select
        coalesce(bool_or(c->>'consent_type' = 'general_care' and (c->>'status') = 'granted'), false),
        coalesce(bool_or(c->>'consent_type' = 'sensitive_data' and (c->>'status') = 'granted'), false),
        coalesce(bool_or(coalesce(c->>'authority_letter_ref', '') <> '' and coalesce(c->>'legal_guardian_name', '') <> ''), false),
        coalesce(bool_or(coalesce((c->>'is_minor_assent')::boolean, false)), false),
        coalesce(bool_or(coalesce(c->>'legal_guardian_name', '') <> ''), false)
    into v_has_general, v_has_sensitive, v_has_authority, v_has_minor_assent, v_has_guardian
    from jsonb_array_elements(p_consents) c;

    if not v_has_general then
        raise exception 'Sin consentimiento general informado no se abre expediente; el auxilio humanitario inmediato no se condiciona (Ethos C2, BV-5.1).' using errcode = 'BV401';
    end if;

    -- D-14: sexo, nacionalidad, lengua y teléfono solo con consentimiento sensible vigente; sin él, no se aceptan
    if not v_has_sensitive and (
        p_sex_id is not null
        or p_nationality_country_id is not null or nullif(trim(coalesce(p_other_nationality, '')), '') is not null
        or p_primary_language_id is not null or nullif(trim(coalesce(p_other_language, '')), '') is not null
        or nullif(trim(coalesce(p_phone_number, '')), '') is not null
    ) then
        raise exception 'Control P-06: sexo, nacionalidad, lengua y teléfono son datos sensibles y exigen consentimiento sensible.' using errcode = 'BV402';
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
        intake_municipality_key, intake_channel_id, intake_window_type,
        entry_route_id, entry_date_str, travels_with_family, opened_by,
        assigned_area_id, assigned_user_id
    ) values (
        v_org_id, public.fn_generate_case_number(v_org_id), v_person_id, p_intake_state_id,
        p_intake_municipality_key, p_intake_channel_id, p_intake_window_type,
        p_entry_route_id, p_entry_date_str, p_travels_with_family, v_user_id,
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
            v_consent->>'status',
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

revoke execute on function public.fn_create_case_with_person_impl(text, text, text, text, date, boolean, int, int, text, int, text, text, text, boolean, int, text, int, int, text, uuid, text[], jsonb) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_create_case_with_person(p_given_name text, p_paternal_family_name text, p_maternal_family_name text, p_preferred_name text, p_birth_date date, p_birth_date_is_estimated boolean, p_sex_id integer, p_nationality_country_id integer, p_other_nationality text, p_primary_language_id integer, p_other_language text, p_phone_number text, p_intake_window_type text, p_travels_with_family boolean, p_intake_state_id integer, p_intake_municipality_key text, p_intake_channel_id integer, p_entry_route_id integer, p_entry_date_str text, p_assigned_area_id uuid, p_vulnerability_codes text[], p_consents jsonb DEFAULT '[]'::jsonb)
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
        p_intake_window_type, p_travels_with_family, p_intake_state_id, p_intake_municipality_key,
        p_intake_channel_id, p_entry_route_id, p_entry_date_str, p_assigned_area_id,
        p_vulnerability_codes, p_consents
    );
end;
$function$;

revoke execute on function public.fn_create_case_with_person(text, text, text, text, date, boolean, int, int, text, int, text, text, text, boolean, int, text, int, int, text, uuid, text[], jsonb) from public, anon;
grant execute on function public.fn_create_case_with_person(text, text, text, text, date, boolean, int, int, text, int, text, text, text, boolean, int, text, int, int, text, uuid, text[], jsonb) to authenticated;

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
    perform public.fn_assert_consent_statuses(p_consents);

    select
        coalesce(bool_or(c->>'consent_type' = 'general_care' and (c->>'status') = 'granted'), false),
        coalesce(bool_or(c->>'consent_type' = 'sensitive_data' and (c->>'status') = 'granted'), false)
    into v_has_general, v_has_sensitive
    from jsonb_array_elements(p_consents) c;

    if not v_has_general then
        raise exception 'Sin consentimiento general informado no se abre expediente; el auxilio humanitario inmediato no se condiciona (Ethos C2, BV-5.1).' using errcode = 'BV401';
    end if;
    -- D-14: sexo, nacionalidad y lengua solo con consentimiento sensible vigente; sin él, no se aceptan
    if not v_has_sensitive and (
        p_sex_id is not null
        or p_nationality_country_id is not null or nullif(trim(coalesce(p_other_nationality, '')), '') is not null
        or p_primary_language_id is not null or nullif(trim(coalesce(p_other_language, '')), '') is not null
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
        birth_date, birth_date_is_estimated, sex_id, nationality_country_id, other_nationality, primary_language_id, other_language
    ) values (
        v_org_id, trim(p_given_name), trim(p_paternal_family_name), nullif(trim(p_maternal_family_name), ''),
        nullif(trim(p_preferred_name), ''), p_birth_date, coalesce(p_birth_date_is_estimated, false), p_sex_id,
        p_nationality_country_id, nullif(trim(p_other_nationality), ''), p_primary_language_id, nullif(trim(p_other_language), '')
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

CREATE OR REPLACE FUNCTION public.fn_register_consent(p_person_id uuid, p_consent_type text, p_status text DEFAULT NULL::text, p_case_id uuid DEFAULT NULL::uuid, p_is_minor_assent boolean DEFAULT false, p_legal_guardian_name text DEFAULT NULL::text, p_legal_guardian_role text DEFAULT NULL::text, p_authority_letter_ref text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
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
    if p_status is null or p_status not in ('granted', 'revoked', 'opposed') then
        raise exception 'Cada consentimiento debe indicar su estado (concedido, retirado o con oposición).' using errcode = 'BV322';
    end if;
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

-- Indicadores: el sexo vacío cuenta como «sin dato»
create or replace function public.fn_metric_rows(p_org uuid, p_from date, p_to date)
returns table (metric text, bucket text, n int, val numeric, ord int, by_freq boolean)
language sql
stable
security definer
set search_path = public
as $$
    with elig as (
        select c.id as case_id, c.opened_at, c.intake_window_type, c.intake_date, p.sex_id,
               coalesce(nullif(trim(p.other_nationality), ''), 'Sin dato') as nationality,
               extract(year from age(c.intake_date, p.birth_date))::int as age_at_intake
        from public."case" c
        join public.person p on p.id = c.titular_person_id
        where c.organization_id = p_org
          and not exists (
              select 1 from public.consent k
              where k.person_id = p.id
                and k.consent_type = 'secondary_use_research'
                and k.status = 'opposed'
          )
    ),
    base as (
        select * from elig
        where (p_from is null or intake_date >= p_from)
          and (p_to is null or intake_date <= p_to)
    ),
    cur as (
        select cs.case_id, ax.code as axis, sv.label_es, sv.sort_order
        from public.case_status cs
        join public.status_axis ax on ax.id = cs.axis_id
        join public.status_value sv on sv.id = cs.value_id
        where cs.valid_to is null and cs.organization_id = p_org
    ),
    milestone as (
        select cs.case_id, sv.code as stage_code, min(cs.valid_from) as t
        from public.case_status cs
        join public.status_axis ax on ax.id = cs.axis_id and ax.code = 'case_stage'
        join public.status_value sv on sv.id = cs.value_id and sv.code in ('case_plan', 'closure')
        where cs.organization_id = p_org
        group by cs.case_id, sv.code
    )
    select 'total_cases'::text, 'all'::text, count(*)::int, count(*)::numeric, 0, true from base
    union all
    select 'intake_window_type', b.intake_window_type, count(*)::int, count(*)::numeric, 0, false from base b group by 2
    union all
    select 'intake_month', to_char(b.intake_date, 'YYYY-MM'), count(*)::int, count(*)::numeric, 0, false from base b group by 2
    union all
    select 'egress_month', to_char(m.t, 'YYYY-MM'), count(*)::int, count(*)::numeric, 0, false
    from milestone m
    join elig e on e.case_id = m.case_id
    where m.stage_code = 'closure'
      and (p_from is null or m.t::date >= p_from)
      and (p_to is null or m.t::date <= p_to)
    group by 2
    union all
    select 'sex', coalesce(b.sex_id::text, 'sin_dato'), count(*)::int, count(*)::numeric, 0, false from base b group by 2
    union all
    select 'age_band',
           case when b.age_at_intake < 12 then '0-11'
                when b.age_at_intake < 18 then '12-17'
                when b.age_at_intake < 30 then '18-29'
                when b.age_at_intake < 45 then '30-44'
                else '45+' end,
           count(*)::int, count(*)::numeric, 0, false
    from base b group by 2
    union all
    select 'nationality', b.nationality, count(*)::int, count(*)::numeric, 0, true from base b group by 2
    union all
    select 'vulnerability', mk.marker_code, count(distinct mk.case_id)::int, count(distinct mk.case_id)::numeric, 0, true
    from public.case_vulnerability_marker mk
    join base b on b.case_id = mk.case_id
    where mk.removed_at is null group by 2
    union all
    select 'case_stage', cur.label_es, count(*)::int, count(*)::numeric, min(cur.sort_order), false
    from base b join cur on cur.case_id = b.case_id and cur.axis = 'case_stage' group by cur.label_es
    union all
    select 'legal_status', cur.label_es, count(*)::int, count(*)::numeric, min(cur.sort_order), false
    from base b join cur on cur.case_id = b.case_id and cur.axis = 'legal_status' group by cur.label_es
    union all
    select 'engagement_status', cur.label_es, count(*)::int, count(*)::numeric, min(cur.sort_order), false
    from base b join cur on cur.case_id = b.case_id and cur.axis = 'engagement_status' group by cur.label_es
    union all
    select 'shelter_status', cur.label_es, count(*)::int, count(*)::numeric, min(cur.sort_order), false
    from base b join cur on cur.case_id = b.case_id and cur.axis = 'shelter_status' group by cur.label_es
    union all
    -- Duraciones: promedio en días sobre los casos de la cohorte que ya alcanzaron el hito
    select 'duration', 'to_case_plan', count(*)::int,
           avg(extract(epoch from (m.t - b.opened_at)) / 86400.0), 0, false
    from base b join milestone m on m.case_id = b.case_id and m.stage_code = 'case_plan'
    union all
    select 'duration', 'to_closure', count(*)::int,
           avg(extract(epoch from (m.t - b.opened_at)) / 86400.0), 1, false
    from base b join milestone m on m.case_id = b.case_id and m.stage_code = 'closure'
$$;
