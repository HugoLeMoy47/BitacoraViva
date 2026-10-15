-- ==============================================================================
-- E14 fase 4a · Diccionarios editables: idioma y religión (y siembra de documentos)
--
-- Decisiones del Product Owner (17 oct 2026), a partir de los desplegables de la hoja de casos de CAFEMIN:
--  * Los diccionarios los editan dirección y el área de Trabajo Social (`can_manage_catalogs()`).
--  * Idioma y religión pasan de texto libre a un **valor del diccionario + detalle** (la religión conserva su texto como
--    detalle). Siguen siendo datos sensibles (D-14): solo con consentimiento sensible vigente (`BV408`).
--  * Existe un valor explícito **«La persona no quiso responder»** (distinto de «No registrado», que es lo vacío): es una
--    respuesta, no un dato sensible, así que se registra sin consentimiento sensible. Es un valor del sistema (`is_system`):
--    no se desactiva ni cambia de clave (`BV614`); su etiqueta sí se puede editar.
--
-- Cómo
--  * `catalog_item`: un solo registro común de diccionarios por organización (`catalog` ∈ language, religion; las
--    próximas fases agregan los suyos). `legacy_code` guarda el texto de la hoja para homologar la importación.
--  * `person.primary_language_item_id` y `person.religion_item_id` apuntan al diccionario; `person.religion` pasa a
--    llamarse `religion_detail` y el detalle del idioma sigue en `other_language`. El detalle sin valor no se acepta (`BV333`).
--  * `fn_set_person_religion` (dirección o ingreso) y `fn_set_person_language` (roles que operan expedientes); el alta y el
--    subfolio reciben el idioma como valor del diccionario. Un valor ajeno, retirado o de otro diccionario se rechaza (`BV220`).
--  * Siembra de documentos: se agrega «TRP» y el tipo de identificación se llama «Documento de identidad / Cédula ID»
--    (solo si conservaba el nombre inicial; lo que ya editó la organización no se pisa).
--  * Errores con código estable: BV220, BV333, BV614.
--
-- Lo ya guardado no se toca (el texto de religión pasa a ser el detalle). Idempotente: el reinicio de la demo reaplica todo.
-- ==============================================================================

-- ---------------------------------------------------------------- 1. Registro común de diccionarios
create table if not exists public.catalog_item (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    catalog text not null check (catalog in ('language', 'religion')),
    key text not null check (key ~ '^[a-z][a-z0-9_]{1,39}$'),
    label_es text not null check (char_length(btrim(label_es)) between 1 and 80),
    legacy_code text check (legacy_code is null or char_length(legacy_code) <= 60),
    is_active boolean not null default true,
    is_system boolean not null default false,
    sort_order int not null default 0,
    unique (organization_id, catalog, key)
);

alter table public.catalog_item enable row level security;
revoke all on public.catalog_item from anon;
revoke delete on public.catalog_item from authenticated;

drop policy if exists "Roles vigentes ven los diccionarios" on public.catalog_item;
create policy "Roles vigentes ven los diccionarios" on public.catalog_item for select to authenticated
    using (organization_id = public.current_organization_id() and public.has_any_role());
drop policy if exists "Dirección y Trabajo Social agregan valores a los diccionarios" on public.catalog_item;
create policy "Dirección y Trabajo Social agregan valores a los diccionarios" on public.catalog_item for insert to authenticated
    with check (organization_id = public.current_organization_id() and public.can_manage_catalogs() and not is_system);
drop policy if exists "Dirección y Trabajo Social editan los diccionarios" on public.catalog_item;
create policy "Dirección y Trabajo Social editan los diccionarios" on public.catalog_item for update to authenticated
    using (organization_id = public.current_organization_id() and public.can_manage_catalogs())
    with check (organization_id = public.current_organization_id() and public.can_manage_catalogs());

-- Los valores del sistema no se desactivan, ni cambian de clave, de diccionario o de organización (su etiqueta sí se edita)
create or replace function public.fn_catalog_item_guard()
returns trigger
language plpgsql as $$
begin
    if old.is_system and (
        new.key is distinct from old.key or new.catalog is distinct from old.catalog
        or new.organization_id is distinct from old.organization_id
        or new.is_active is not true or new.is_system is not true
    ) then
        raise exception 'Este valor es del sistema: no se puede retirar ni cambiar de clave.' using errcode = 'BV614';
    end if;
    return new;
end;
$$;
drop trigger if exists trg_catalog_item_guard on public.catalog_item;
create trigger trg_catalog_item_guard before update on public.catalog_item
for each row execute function public.fn_catalog_item_guard();

drop trigger if exists trg_audit_catalog_item on public.catalog_item;
create trigger trg_audit_catalog_item after insert or update on public.catalog_item
for each row execute function public.fn_audit_trigger_fields();

-- Valores de la hoja de casos de CAFEMIN (idioma y religión), con el texto original en `legacy_code`
insert into public.catalog_item (organization_id, catalog, key, label_es, legacy_code, is_system, sort_order)
select o.id, v.catalog, v.key, v.label_es, v.legacy_code, v.is_system, v.sort_order
from public.organization o
cross join (values
    ('language', 'spanish', 'Español', 'ESPAÑOL', false, 1),
    ('language', 'indigenous', 'Lengua indígena', 'LENGUA INDIGENA', false, 2),
    ('language', 'english', 'Inglés', 'INGLES', false, 3),
    ('language', 'french', 'Francés', 'FRANCES', false, 4),
    ('language', 'persian', 'Persa', 'PERSA', false, 5),
    ('language', 'indie', 'Indie', 'INDIE', false, 6),
    ('language', 'creole', 'Criolle', 'CRIOLLE', false, 7),
    ('language', 'other_languages', 'Otros idiomas', 'OTROS IDIOMAS', false, 8),
    ('language', 'no_response', 'La persona no quiso responder', null, true, 99),
    ('religion', 'catholic_christian', 'Católico/cristiano', 'CATÓLICO/CRISTIANO', false, 1),
    ('religion', 'christian_non_catholic', 'Cristiano (no católico)', 'CRISTIANO ( NO CATOLICO)', false, 2),
    ('religion', 'protestant', 'Protestante', 'PROTESTANTE', false, 3),
    ('religion', 'evangelical', 'Evangélico', 'EVANGELICO', false, 4),
    ('religion', 'jehovahs_witness', 'Testigo de Jehová', 'TESTIGO DE JEHOVA', false, 5),
    ('religion', 'mormon', 'Mormón', 'MORMÓN', false, 6),
    ('religion', 'islam', 'Islam', 'ISLAM', false, 7),
    ('religion', 'orthodox', 'Ortodoxa', 'ORTODOXA', false, 8),
    ('religion', 'believer', 'Creyente', 'CREYENTE', false, 9),
    ('religion', 'non_believer', 'No creyente', 'NO CREYENTE', false, 10),
    ('religion', 'other', 'Otro', 'OTRO', false, 11),
    ('religion', 'no_response', 'La persona no quiso responder', null, true, 99)
) as v(catalog, key, label_es, legacy_code, is_system, sort_order)
on conflict (organization_id, catalog, key) do nothing;

-- ---------------------------------------------------------------- 2. Documentos: sigla de la hoja y valores nuevos
alter table public.document_type add column if not exists legacy_code text;
alter table public.document_type drop constraint if exists document_type_legacy_code_length;
alter table public.document_type add constraint document_type_legacy_code_length
    check (legacy_code is null or char_length(legacy_code) <= 60);

-- El tipo de identificación se llama como en la hoja, solo si conservaba el nombre inicial
update public.document_type set label_es = 'Documento de identidad / Cédula ID'
where key = 'national_id' and label_es = 'Identificación oficial de su país';
update public.document_type set legacy_code = 'Documento de identidad/ Cédula ID' where key = 'national_id' and legacy_code is null;
update public.document_type set legacy_code = 'Pasaporte' where key = 'passport' and legacy_code is null;

insert into public.document_type (organization_id, key, label_es, legacy_code, sort_order)
select o.id, 'trp', 'TRP', 'TRP', 7 from public.organization o
on conflict (organization_id, key) do nothing;

-- ---------------------------------------------------------------- 3. La persona: idioma y religión como valor del diccionario
alter table public.person
    add column if not exists primary_language_item_id uuid references public.catalog_item(id) on delete restrict,
    add column if not exists religion_item_id uuid references public.catalog_item(id) on delete restrict;

-- `religion` (texto) pasa a ser el detalle. Si el reinicio de la demo reaplicó la migración anterior, la columna
-- vieja reaparece: se copia su contenido y se retira.
do $$
begin
    if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'person' and column_name = 'religion') then
        if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'person' and column_name = 'religion_detail') then
            alter table public.person rename column religion to religion_detail;
        else
            update public.person set religion_detail = coalesce(religion_detail, religion) where religion is not null;
            alter table public.person drop column religion;
        end if;
    end if;
end $$;
alter table public.person drop constraint if exists person_religion_length;
alter table public.person drop constraint if exists person_religion_detail_length;
alter table public.person add constraint person_religion_detail_length
    check (religion_detail is null or char_length(religion_detail) <= 120);

-- ---------------------------------------------------------------- 4. Funciones internas
-- El valor existe, es de esta organización, de ese diccionario y está activo
create or replace function public.fn_assert_catalog_item(p_org uuid, p_catalog text, p_item uuid)
returns void
security definer
set search_path = public
language plpgsql as $$
begin
    if not exists (
        select 1 from public.catalog_item c
        where c.id = p_item and c.organization_id = p_org and c.catalog = p_catalog and c.is_active
    ) then
        raise exception 'Ese valor no está disponible en el diccionario.' using errcode = 'BV220';
    end if;
end;
$$;
revoke execute on function public.fn_assert_catalog_item(uuid, text, uuid) from public, anon, authenticated;

-- «La persona no quiso responder» es una respuesta, no un dato sensible
create or replace function public.fn_catalog_item_is_no_response(p_item uuid)
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select coalesce((select c.key = 'no_response' from public.catalog_item c where c.id = p_item), false);
$$;
revoke execute on function public.fn_catalog_item_is_no_response(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- 5. Religión e idioma de la persona
drop function if exists public.fn_set_person_religion(uuid, text, text);

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
       or not (public.has_role('director') or public.has_role('intake_officer')) then
        raise exception 'Acceso denegado: la religión la registran dirección o ingreso (D-14).' using errcode = 'BV121';
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
revoke execute on function public.fn_set_person_religion(uuid, uuid, text, text) from public, anon;
grant execute on function public.fn_set_person_religion(uuid, uuid, text, text) to authenticated;

create or replace function public.fn_set_person_language(
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
    if v_user is null or public.current_organization_id() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: registrar el idioma exige un rol que opere expedientes (E14).' using errcode = 'BV120';
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
        perform public.fn_assert_catalog_item(v_person.organization_id, 'language', p_item_id);
        if not public.fn_catalog_item_is_no_response(p_item_id) and not public.fn_person_has_sensitive_consent(p_person_id) then
            raise exception 'Control P-06: el idioma es un dato sensible y exige consentimiento sensible vigente (D-14).' using errcode = 'BV408';
        end if;
    end if;
    if p_item_id is not distinct from v_person.primary_language_item_id and v_detail is not distinct from v_person.other_language then
        return;
    end if;
    if (v_person.primary_language_item_id is not null or v_person.other_language is not null) and (p_reason is null or btrim(p_reason) = '') then
        raise exception 'El motivo es obligatorio al cambiar o quitar un dato ya registrado (Ethos C8).' using errcode = 'BV304';
    end if;

    update public.person set primary_language_item_id = p_item_id, other_language = v_detail, updated_at = now() where id = p_person_id;

    if v_person.primary_language_item_id is not null or v_person.other_language is not null then
        insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
        values (v_person.organization_id, v_user, 'RECTIFICATION', 'person', p_person_id,
                jsonb_build_object('changed_fields', jsonb_build_array('primary_language_item_id', 'other_language'), 'reason', btrim(p_reason)));
    end if;
end;
$$;
revoke execute on function public.fn_set_person_language(uuid, uuid, text, text) from public, anon;
grant execute on function public.fn_set_person_language(uuid, uuid, text, text) to authenticated;

-- ---------------------------------------------------------------- 6. Alta, subfolio, anonimización y extracto de acceso ARCO
-- Se redefinen a partir de la definición vigente (20261016000001, 20261015000003 y 20261017000001); solo se agregan los pasos marcados «E14 f4a».

-- El alta y el subfolio cambian de firma (el idioma pasa de identificador numérico a valor del diccionario)
drop function if exists public.fn_create_case_with_person(text, text, text, text, date, boolean, int, int, text, int, text, text, text, boolean, int, text, int, int, text, uuid, text[], jsonb, jsonb);
drop function if exists public.fn_create_case_with_person_impl(text, text, text, text, date, boolean, int, int, text, int, text, text, text, boolean, int, text, int, int, text, uuid, text[], jsonb, jsonb);
drop function if exists public.fn_create_subfolio(uuid, text, text, text, text, date, boolean, int, int, text, int, text, text, text, text[], jsonb);

CREATE OR REPLACE FUNCTION public.fn_create_case_with_person_impl(p_given_name text, p_paternal_family_name text, p_maternal_family_name text, p_preferred_name text, p_birth_date date, p_birth_date_is_estimated boolean, p_sex_id integer, p_nationality_country_id integer, p_other_nationality text, p_primary_language_item_id uuid, p_other_language text, p_phone_number text, p_intake_window_type text, p_travels_with_family boolean, p_intake_state_id integer, p_intake_municipality_key text, p_intake_channel_id integer, p_entry_route_id integer, p_entry_date_str text, p_assigned_area_id uuid, p_vulnerability_codes text[], p_consents jsonb DEFAULT '[]'::jsonb, p_dates jsonb DEFAULT '[]'::jsonb)
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
    v_date jsonb;   -- E14 f2
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
    -- E14 f2: las fechas llegan como arreglo de {kind, value, precision}
    if jsonb_typeof(coalesce(p_dates, '[]'::jsonb)) is distinct from 'array' then
        raise exception 'Las fechas deben enviarse como arreglo.' using errcode = 'BV325';
    end if;

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

    -- E14 f4a: el idioma es un valor del diccionario (el «no quiso responder» no es un dato sensible) y su detalle lo acompaña
    if p_primary_language_item_id is not null then
        perform public.fn_assert_catalog_item(v_org_id, 'language', p_primary_language_item_id);
    end if;
    if nullif(trim(coalesce(p_other_language, '')), '') is not null
       and (p_primary_language_item_id is null or public.fn_catalog_item_is_no_response(p_primary_language_item_id)) then
        raise exception 'El detalle del idioma necesita un valor del diccionario que lo explique.' using errcode = 'BV333';
    end if;

    -- D-14: sexo, nacionalidad, lengua y teléfono solo con consentimiento sensible vigente; sin él, no se aceptan
    if not v_has_sensitive and (
        p_sex_id is not null
        or p_nationality_country_id is not null or nullif(trim(coalesce(p_other_nationality, '')), '') is not null
        or (p_primary_language_item_id is not null and not public.fn_catalog_item_is_no_response(p_primary_language_item_id)) or nullif(trim(coalesce(p_other_language, '')), '') is not null
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
        nationality_country_id, other_nationality, primary_language_item_id,
        other_language, phone_number
    ) values (
        v_org_id, trim(p_given_name), trim(p_paternal_family_name), nullif(trim(p_maternal_family_name), ''),
        nullif(trim(p_preferred_name), ''), p_birth_date, coalesce(p_birth_date_is_estimated, false), p_sex_id,
        p_nationality_country_id, p_other_nationality, p_primary_language_item_id,
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

    -- E14 f2: las fechas del caso, en la misma transacción (cada una se valida como si se registrara después)
    for v_date in select * from jsonb_array_elements(coalesce(p_dates, '[]'::jsonb)) loop
        perform public.fn_set_case_date(
            v_case_id,
            v_date->>'kind',
            nullif(v_date->>'value', '')::date,
            v_date->>'precision',
            null
        );
    end loop;

    return v_case_id;
end;
$function$;

revoke execute on function public.fn_create_case_with_person_impl(text, text, text, text, date, boolean, int, int, text, uuid, text, text, text, boolean, int, text, int, int, text, uuid, text[], jsonb, jsonb) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_create_case_with_person(p_given_name text, p_paternal_family_name text, p_maternal_family_name text, p_preferred_name text, p_birth_date date, p_birth_date_is_estimated boolean, p_sex_id integer, p_nationality_country_id integer, p_other_nationality text, p_primary_language_item_id uuid, p_other_language text, p_phone_number text, p_intake_window_type text, p_travels_with_family boolean, p_intake_state_id integer, p_intake_municipality_key text, p_intake_channel_id integer, p_entry_route_id integer, p_entry_date_str text, p_assigned_area_id uuid, p_vulnerability_codes text[], p_consents jsonb DEFAULT '[]'::jsonb, p_dates jsonb DEFAULT '[]'::jsonb)
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
        p_other_nationality, p_primary_language_item_id, p_other_language, p_phone_number,
        p_intake_window_type, p_travels_with_family, p_intake_state_id, p_intake_municipality_key,
        p_intake_channel_id, p_entry_route_id, p_entry_date_str, p_assigned_area_id,
        p_vulnerability_codes, p_consents, p_dates
    );
end;
$function$;

revoke execute on function public.fn_create_case_with_person(text, text, text, text, date, boolean, int, int, text, uuid, text, text, text, boolean, int, text, int, int, text, uuid, text[], jsonb, jsonb) from public, anon;
grant execute on function public.fn_create_case_with_person(text, text, text, text, date, boolean, int, int, text, uuid, text, text, text, boolean, int, text, int, int, text, uuid, text[], jsonb, jsonb) to authenticated;

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

revoke execute on function public.fn_create_subfolio(uuid, text, text, text, text, date, boolean, int, int, text, uuid, text, text, text, text[], jsonb) from public, anon;
grant execute on function public.fn_create_subfolio(uuid, text, text, text, text, date, boolean, int, int, text, uuid, text, text, text, text[], jsonb) to authenticated;

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
    v_docs jsonb;      -- E14
    v_markers jsonb;   -- E14
    v_dates jsonb;     -- E14 f2
    v_family jsonb;    -- E14 f3
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
        'parent_case_id', c.parent_case_id,
        'legacy_reference', c.legacy_reference
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

    -- E14: documentos (con historial) y detalle de los marcadores: también son datos de la persona
    select coalesce(jsonb_agg(jsonb_build_object(
        'document_type', t.label_es,
        'document_number', d.document_number,
        'registered_at', d.created_at,
        'closed_at', d.valid_to
    ) order by d.created_at), '[]'::jsonb) into v_docs
    from public.person_document d
    join public.document_type t on t.id = d.document_type_id
    where d.person_id = p_person_id;

    select coalesce(jsonb_agg(jsonb_build_object(
        'case_number', c.case_number,
        'marker_code', m.marker_code,
        'detail', m.notes
    ) order by c.case_number, m.marker_code), '[]'::jsonb) into v_markers
    from public.case_vulnerability_marker m
    join public.case c on c.id = m.case_id
    where c.titular_person_id = p_person_id and m.removed_at is null;

    -- E14 f2: las fechas del caso (con historial) también son datos de la persona
    select coalesce(jsonb_agg(jsonb_build_object(
        'case_number', c.case_number,
        'kind', d.kind,
        'value', d.value,
        'precision', d.precision,
        'registered_at', d.created_at,
        'closed_at', d.valid_to
    ) order by c.case_number, d.created_at), '[]'::jsonb) into v_dates
    from public.case_date d
    join public.case c on c.id = d.case_id
    where c.titular_person_id = p_person_id;

    -- E14 f3: la familia del sistema paralelo (con historial) también es dato de la persona
    select coalesce(jsonb_agg(jsonb_build_object(
        'case_number', c.case_number,
        'family_number', f.family_number,
        'family_type', t.label_es,
        'member_order', m.member_order,
        'registered_at', m.created_at,
        'closed_at', m.valid_to
    ) order by c.case_number, m.created_at), '[]'::jsonb) into v_family
    from public.family_member m
    join public.family_unit f on f.id = m.family_unit_id
    left join public.family_type t on t.id = f.family_type_id
    join public.case c on c.id = m.case_id
    where c.titular_person_id = p_person_id;

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
            'religion', (select ci.label_es from public.catalog_item ci where ci.id = v_person.religion_item_id),
            'religion_detail', v_person.religion_detail,
            'language', (select ci.label_es from public.catalog_item ci where ci.id = v_person.primary_language_item_id),
            'language_detail', v_person.other_language,
            'is_anonymized', v_person.is_anonymized
        ),
        'cases', v_cases,
        'journal_entries', v_entries,
        'consents', v_consents,
        'documents', v_docs,
        'vulnerability_markers', v_markers,
        'dates', v_dates,
        'family', v_family
    );

    -- Auditoría obligatoria de emisión: la persona se identifica por record_id, no por su nombre
    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_person.organization_id, v_user_id, 'ARCO_ACCESS_EXTRACT_ISSUED', 'person', p_person_id,
            jsonb_build_object('emitted_at', now()));

    return v_result;
end;
$function$;
