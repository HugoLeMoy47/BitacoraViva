-- ==============================================================================
-- E15 fase 1 · Ficha de la persona completa
--
-- Contexto: la matriz de Trabajo Social (22 oct 2026) trae nivel de estudios, ocupación en su lugar de origen, estado civil
-- y departamento. Esos cuatro campos de MAP-OIM v3 existían como columna desde la migración inicial, pero sin lista de
-- valores, sin captura y sin pantalla (se había dado por integrados solo por la columna). Esta fase los integra de verdad.
--
-- Decisiones del Product Owner (22 oct 2026)
--  * Escolaridad, estado civil y ocupación son diccionarios editables por dirección y Trabajo Social, sembrados con las
--    listas de MAP-OIM v3. «No menciona» de MAP-OIM equivale a «La persona no quiso responder» (valor del sistema).
--  * La ocupación en su lugar de origen es **obligatoria en el alta** (la matriz la marca así), con «no quiso responder» como
--    salida; admite hasta 3 opciones. Si el diccionario no tiene opciones activas, no se puede exigir.
--  * El departamento de origen depende del país de la nacionalidad; se usan los países que ya existen en la lista (Honduras,
--    Guatemala y «otro»). Se siembran las divisiones oficiales de Honduras y Guatemala; el área agrega más.
--  * El **departamento se trata como dato sensible**: es una subdivisión de la nacionalidad, que ya lo es (D-14).
--    Escolaridad, estado civil y ocupación no están en la matriz sensible.
--  * «Número de referencia»: un folio manual, texto corto, en el expediente.
--
-- Cómo
--  * `catalog_item` admite `education_level`, `marital_status`, `occupation` y `department`; el departamento lleva `country_id`.
--  * `person` recibe `education_level_item_id`, `marital_status_item_id` y `origin_department_item_id`; las ocupaciones van
--    en `person_occupation` (versionada: lo quitado se cierra con motivo, nada se borra). Las columnas numéricas antiguas
--    (`education_level_id`, `marital_status_id`, `occupations`, `origin_department_id`) quedan sin uso.
--  * `fn_set_person_profile_item` (estudios, estado civil, departamento), `fn_set_person_occupations` y
--    `fn_set_case_reference_number`; el alta y la anonimización y el extracto ARCO se extienden.
--  * Errores con código estable: BV337 (departamento y país), BV338 (ocupaciones), BV339 (ocupación obligatoria).
--
-- Idempotente: el reinicio de la demo reaplica todas las migraciones.
-- ==============================================================================

-- ---------------------------------------------------------------- 1. Diccionarios nuevos
alter table public.catalog_item add column if not exists country_id integer;

alter table public.catalog_item drop constraint if exists catalog_item_catalog_check;
alter table public.catalog_item add constraint catalog_item_catalog_check
    check (catalog in ('language', 'religion', 'specific_need', 'service_line', 'education_level', 'marital_status', 'occupation', 'department'));

-- Solo el departamento lleva país (el valor del sistema «no quiso responder» sirve para cualquiera)
alter table public.catalog_item drop constraint if exists catalog_item_country_check;
alter table public.catalog_item add constraint catalog_item_country_check
    check ((catalog = 'department' and (country_id is not null or is_system)) or (catalog <> 'department' and country_id is null));
create index if not exists idx_catalog_item_country on public.catalog_item (organization_id, catalog, country_id);

insert into public.catalog_item (organization_id, catalog, key, label_es, is_system, sort_order)
select o.id, v.catalog, v.key, v.label_es, v.is_system, v.sort_order
from public.organization o
cross join (values
    ('education_level', 'no_schooling', 'Sin estudios', false, 1),
    ('education_level', 'primary', 'Primaria', false, 2),
    ('education_level', 'secondary', 'Secundaria', false, 3),
    ('education_level', 'upper_secondary', 'Bachillerato / técnico', false, 4),
    ('education_level', 'university', 'Universidad', false, 5),
    ('education_level', 'postgraduate', 'Posgrado', false, 6),
    ('education_level', 'no_response', 'La persona no quiso responder', true, 99),
    ('marital_status', 'married', 'Casado(a)', false, 1),
    ('marital_status', 'divorced', 'Divorciado(a)', false, 2),
    ('marital_status', 'separated', 'Separado(a)', false, 3),
    ('marital_status', 'single', 'Soltero(a)', false, 4),
    ('marital_status', 'free_union', 'Unión libre', false, 5),
    ('marital_status', 'widowed', 'Viudo(a)', false, 6),
    ('marital_status', 'no_response', 'La persona no quiso responder', true, 99),
    ('occupation', 'agriculture_commerce', 'Agricultura / comercio', false, 1),
    ('occupation', 'construction', 'Construcción', false, 2),
    ('occupation', 'student', 'Estudiante', false, 3),
    ('occupation', 'trades', 'Oficios', false, 4),
    ('occupation', 'professional', 'Profesionista', false, 5),
    ('occupation', 'services', 'Servicios', false, 6),
    ('occupation', 'household', 'Trabajo del hogar', false, 7),
    ('occupation', 'no_response', 'La persona no quiso responder', true, 99),
    ('department', 'no_response', 'La persona no quiso responder', true, 99)
) as v(catalog, key, label_es, is_system, sort_order)
on conflict (organization_id, catalog, key) do nothing;

-- Divisiones oficiales: Honduras (id 93 en la lista de países) y Guatemala (id 86)
insert into public.catalog_item (organization_id, catalog, key, label_es, is_system, sort_order, country_id)
select o.id, 'department', v.key, v.label_es, false, v.sort_order, v.country_id
from public.organization o
cross join (values
    (93, 'hn_atlantida', 'Atlántida', 1), (93, 'hn_choluteca', 'Choluteca', 2), (93, 'hn_colon', 'Colón', 3),
    (93, 'hn_comayagua', 'Comayagua', 4), (93, 'hn_copan', 'Copán', 5), (93, 'hn_cortes', 'Cortés', 6),
    (93, 'hn_el_paraiso', 'El Paraíso', 7), (93, 'hn_francisco_morazan', 'Francisco Morazán', 8),
    (93, 'hn_gracias_a_dios', 'Gracias a Dios', 9), (93, 'hn_intibuca', 'Intibucá', 10),
    (93, 'hn_islas_de_la_bahia', 'Islas de la Bahía', 11), (93, 'hn_la_paz', 'La Paz', 12),
    (93, 'hn_lempira', 'Lempira', 13), (93, 'hn_ocotepeque', 'Ocotepeque', 14), (93, 'hn_olancho', 'Olancho', 15),
    (93, 'hn_santa_barbara', 'Santa Bárbara', 16), (93, 'hn_valle', 'Valle', 17), (93, 'hn_yoro', 'Yoro', 18),
    (86, 'gt_alta_verapaz', 'Alta Verapaz', 1), (86, 'gt_baja_verapaz', 'Baja Verapaz', 2),
    (86, 'gt_chimaltenango', 'Chimaltenango', 3), (86, 'gt_chiquimula', 'Chiquimula', 4),
    (86, 'gt_el_progreso', 'El Progreso', 5), (86, 'gt_escuintla', 'Escuintla', 6),
    (86, 'gt_guatemala', 'Guatemala', 7), (86, 'gt_huehuetenango', 'Huehuetenango', 8),
    (86, 'gt_izabal', 'Izabal', 9), (86, 'gt_jalapa', 'Jalapa', 10), (86, 'gt_jutiapa', 'Jutiapa', 11),
    (86, 'gt_peten', 'Petén', 12), (86, 'gt_quetzaltenango', 'Quetzaltenango', 13), (86, 'gt_quiche', 'Quiché', 14),
    (86, 'gt_retalhuleu', 'Retalhuleu', 15), (86, 'gt_sacatepequez', 'Sacatepéquez', 16),
    (86, 'gt_san_marcos', 'San Marcos', 17), (86, 'gt_santa_rosa', 'Santa Rosa', 18), (86, 'gt_solola', 'Sololá', 19),
    (86, 'gt_suchitepequez', 'Suchitepéquez', 20), (86, 'gt_totonicapan', 'Totonicapán', 21), (86, 'gt_zacapa', 'Zacapa', 22)
) as v(country_id, key, label_es, sort_order)
on conflict (organization_id, catalog, key) do nothing;

-- ---------------------------------------------------------------- 2. Columnas de la persona y del caso; ocupaciones versionadas
alter table public.person
    add column if not exists education_level_item_id uuid references public.catalog_item(id) on delete restrict,
    add column if not exists marital_status_item_id uuid references public.catalog_item(id) on delete restrict,
    add column if not exists origin_department_item_id uuid references public.catalog_item(id) on delete restrict;
alter table public."case" add column if not exists reference_number text;

create table if not exists public.person_occupation (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    person_id uuid not null references public.person(id) on delete restrict,
    catalog_item_id uuid not null references public.catalog_item(id) on delete restrict,
    created_at timestamptz not null default now(),
    created_by uuid not null references public.user_profile(id),
    valid_to timestamptz,
    closed_by uuid references public.user_profile(id),
    change_reason text
);
create unique index if not exists uq_person_occupation_current on public.person_occupation (person_id, catalog_item_id) where valid_to is null;
create index if not exists idx_person_occupation_person on public.person_occupation (person_id);

alter table public.person_occupation enable row level security;
revoke all on public.person_occupation from anon;
revoke insert, update, delete on public.person_occupation from authenticated;
drop policy if exists tenant_operational_select on public.person_occupation;
create policy tenant_operational_select on public.person_occupation for select to authenticated
    using (organization_id = public.current_organization_id() and public.has_operational_role());
drop trigger if exists trg_audit_person_occupation on public.person_occupation;
create trigger trg_audit_person_occupation after insert or update on public.person_occupation
for each row execute function public.fn_audit_trigger_fields();

-- ---------------------------------------------------------------- 3. Escritura
-- Núcleo común (alta y corrección): valida el conjunto de ocupaciones. Interna: no la ejecutan los roles de aplicación.
create or replace function public.fn_assert_occupation_set(p_org uuid, p_item_ids uuid[])
returns uuid[]
security definer
set search_path = public
language plpgsql as $$
declare
    v_ids uuid[];
    v_id uuid;
    v_has_no_response boolean := false;
begin
    if exists (select 1 from unnest(coalesce(p_item_ids, '{}'::uuid[])) as t(x) where x is null) then
        raise exception 'Ese valor no está disponible en el diccionario.' using errcode = 'BV220';
    end if;
    select coalesce(array_agg(distinct x), '{}'::uuid[]) into v_ids from unnest(coalesce(p_item_ids, '{}'::uuid[])) as t(x);
    foreach v_id in array v_ids loop
        perform public.fn_assert_catalog_item(p_org, 'occupation', v_id);
        if public.fn_catalog_item_is_no_response(v_id) then
            v_has_no_response := true;
        end if;
    end loop;
    if array_length(v_ids, 1) > 3 or (v_has_no_response and array_length(v_ids, 1) > 1) then
        raise exception 'La ocupación admite hasta 3 opciones, y «no quiso responder» no se combina con otras.' using errcode = 'BV338';
    end if;
    -- Obligatoria cuando el diccionario tiene opciones activas (con «no quiso responder» como salida)
    if coalesce(array_length(v_ids, 1), 0) = 0 and exists (
        select 1 from public.catalog_item c where c.organization_id = p_org and c.catalog = 'occupation' and c.is_active
    ) then
        raise exception 'La ocupación en su lugar de origen es obligatoria: elige una opción o «La persona no quiso responder».' using errcode = 'BV339';
    end if;
    return v_ids;
end;
$$;
revoke execute on function public.fn_assert_occupation_set(uuid, uuid[]) from public, anon, authenticated;

-- Aplica el conjunto (agrega lo nuevo y cierra lo quitado con motivo). Interna.
create or replace function public.fn_apply_person_occupations(p_person_id uuid, p_org uuid, p_item_ids uuid[], p_reason text)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_ids uuid[] := public.fn_assert_occupation_set(p_org, p_item_ids);
    v_id uuid;
    v_current uuid[];
    v_added uuid[];
    v_removed uuid[];
begin
    select coalesce(array_agg(catalog_item_id), '{}'::uuid[]) into v_current
    from public.person_occupation where person_id = p_person_id and valid_to is null;
    select coalesce(array_agg(x), '{}'::uuid[]) into v_added from unnest(v_ids) as t(x) where x <> all (v_current);
    select coalesce(array_agg(x), '{}'::uuid[]) into v_removed from unnest(v_current) as t(x) where x <> all (v_ids);
    if coalesce(array_length(v_added, 1), 0) = 0 and coalesce(array_length(v_removed, 1), 0) = 0 then
        return;
    end if;
    if coalesce(array_length(v_removed, 1), 0) > 0 and (p_reason is null or btrim(p_reason) = '') then
        raise exception 'El motivo es obligatorio al quitar una ocupación ya registrada (Ethos C8).' using errcode = 'BV304';
    end if;
    if coalesce(array_length(v_removed, 1), 0) > 0 then
        update public.person_occupation set valid_to = now(), closed_by = v_user, change_reason = btrim(p_reason)
        where person_id = p_person_id and valid_to is null and catalog_item_id = any (v_removed);
    end if;
    foreach v_id in array v_added loop
        insert into public.person_occupation (organization_id, person_id, catalog_item_id, created_by)
        values (p_org, p_person_id, v_id, v_user);
    end loop;
end;
$$;
revoke execute on function public.fn_apply_person_occupations(uuid, uuid, uuid[], text) from public, anon, authenticated;

create or replace function public.fn_set_person_occupations(p_person_id uuid, p_item_ids uuid[], p_reason text default null)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_person record;
begin
    if auth.uid() is null or public.current_organization_id() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: registrar la ocupación exige un rol que opere expedientes (E15).' using errcode = 'BV120';
    end if;
    perform public.fn_assert_same_org('person', p_person_id);
    select * into v_person from public.person where id = p_person_id;
    if v_person.is_anonymized then
        raise exception 'Operación no permitida: una persona anonimizada no admite este dato (ADR-0001).' using errcode = 'BV507';
    end if;
    perform public.fn_apply_person_occupations(p_person_id, v_person.organization_id, p_item_ids, p_reason);
end;
$$;
revoke execute on function public.fn_set_person_occupations(uuid, uuid[], text) from public, anon;
grant execute on function public.fn_set_person_occupations(uuid, uuid[], text) to authenticated;

-- Estudios, estado civil y departamento de origen: un valor del diccionario (o vacío)
create or replace function public.fn_set_person_profile_item(p_person_id uuid, p_field text, p_item_id uuid, p_reason text default null)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_person record;
    v_catalog text;
    v_current uuid;
    v_item record;
begin
    if v_user is null or public.current_organization_id() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: este dato de la ficha exige un rol que opere expedientes (E15).' using errcode = 'BV120';
    end if;
    v_catalog := case p_field
        when 'education_level' then 'education_level'
        when 'marital_status' then 'marital_status'
        when 'origin_department' then 'department'
        else null end;
    if v_catalog is null then
        raise exception 'Ese valor no está disponible en el diccionario.' using errcode = 'BV220';
    end if;
    perform public.fn_assert_same_org('person', p_person_id);
    select * into v_person from public.person where id = p_person_id;
    if v_person.is_anonymized then
        raise exception 'Operación no permitida: una persona anonimizada no admite este dato (ADR-0001).' using errcode = 'BV507';
    end if;

    if p_item_id is not null then
        perform public.fn_assert_catalog_item(v_person.organization_id, v_catalog, p_item_id);
        if v_catalog = 'department' and not public.fn_catalog_item_is_no_response(p_item_id) then
            select * into v_item from public.catalog_item where id = p_item_id;
            -- El departamento es una subdivisión de la nacionalidad: sin ella, o de otro país, no corresponde
            if v_person.nationality_country_id is null or v_item.country_id is distinct from v_person.nationality_country_id then
                raise exception 'Ese departamento no corresponde al país de nacionalidad de la persona.' using errcode = 'BV337';
            end if;
            if not public.fn_person_has_sensitive_consent(p_person_id) then
                raise exception 'Control P-06: el departamento de origen es un dato sensible y exige consentimiento sensible vigente (D-14).' using errcode = 'BV408';
            end if;
        end if;
    end if;

    v_current := case p_field
        when 'education_level' then v_person.education_level_item_id
        when 'marital_status' then v_person.marital_status_item_id
        else v_person.origin_department_item_id end;
    if p_item_id is not distinct from v_current then
        return;
    end if;
    if v_current is not null and (p_reason is null or btrim(p_reason) = '') then
        raise exception 'El motivo es obligatorio al cambiar o quitar un dato ya registrado (Ethos C8).' using errcode = 'BV304';
    end if;

    update public.person set
        education_level_item_id = case when p_field = 'education_level' then p_item_id else education_level_item_id end,
        marital_status_item_id = case when p_field = 'marital_status' then p_item_id else marital_status_item_id end,
        origin_department_item_id = case when p_field = 'origin_department' then p_item_id else origin_department_item_id end,
        updated_at = now()
    where id = p_person_id;

    if v_current is not null then
        insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
        values (v_person.organization_id, v_user, 'RECTIFICATION', 'person', p_person_id,
                jsonb_build_object('changed_fields', jsonb_build_array(
                    case p_field when 'education_level' then 'education_level_item_id'
                                 when 'marital_status' then 'marital_status_item_id'
                                 else 'origin_department_item_id' end), 'reason', btrim(p_reason)));
    end if;
end;
$$;
revoke execute on function public.fn_set_person_profile_item(uuid, text, uuid, text) from public, anon;
grant execute on function public.fn_set_person_profile_item(uuid, text, uuid, text) to authenticated;

-- Número de referencia: folio manual, texto corto (mismo patrón que la referencia heredada)
create or replace function public.fn_set_case_reference_number(p_case_id uuid, p_reference text, p_reason text default null)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_case record;
    v_ref text := nullif(btrim(coalesce(p_reference, '')), '');
begin
    if v_user is null or public.current_organization_id() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: el número de referencia exige un rol que opere expedientes (E15).' using errcode = 'BV120';
    end if;
    perform public.fn_assert_same_org('case', p_case_id);
    select * into v_case from public."case" where id = p_case_id;
    if v_ref is not null and char_length(v_ref) > 120 then
        raise exception 'La referencia excede los 120 caracteres.' using errcode = 'BV321';
    end if;
    if v_ref is not distinct from v_case.reference_number then
        return;
    end if;
    if v_case.reference_number is not null and (p_reason is null or btrim(p_reason) = '') then
        raise exception 'El motivo es obligatorio al cambiar o quitar un dato ya registrado (Ethos C8).' using errcode = 'BV304';
    end if;
    update public."case" set reference_number = v_ref where id = p_case_id;
    if v_case.reference_number is not null then
        insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
        values (v_case.organization_id, v_user, 'RECTIFICATION', 'case', p_case_id,
                jsonb_build_object('changed_fields', jsonb_build_array('reference_number'), 'reason', btrim(p_reason)));
    end if;
end;
$$;
revoke execute on function public.fn_set_case_reference_number(uuid, text, text) from public, anon;
grant execute on function public.fn_set_case_reference_number(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------- 4. Alta, anonimización y extracto ARCO
-- Se redefinen a partir de las definiciones vigentes (alta: 20261018000001; anonimización y extracto: 20261019000001).
-- Solo cambian los pasos marcados «E15».

drop function if exists public.fn_create_case_with_person(text, text, text, text, date, boolean, int, int, text, uuid, text, text, text, boolean, int, text, int, int, text, uuid, text[], jsonb, jsonb);
drop function if exists public.fn_create_case_with_person_impl(text, text, text, text, date, boolean, int, int, text, uuid, text, text, text, boolean, int, text, int, int, text, uuid, text[], jsonb, jsonb);

CREATE OR REPLACE FUNCTION public.fn_create_case_with_person_impl(p_given_name text, p_paternal_family_name text, p_maternal_family_name text, p_preferred_name text, p_birth_date date, p_birth_date_is_estimated boolean, p_sex_id integer, p_nationality_country_id integer, p_other_nationality text, p_primary_language_item_id uuid, p_other_language text, p_phone_number text, p_intake_window_type text, p_travels_with_family boolean, p_intake_state_id integer, p_intake_municipality_key text, p_intake_channel_id integer, p_entry_route_id integer, p_entry_date_str text, p_assigned_area_id uuid, p_vulnerability_codes text[], p_consents jsonb DEFAULT '[]'::jsonb, p_dates jsonb DEFAULT '[]'::jsonb, p_education_level_item_id uuid DEFAULT NULL::uuid, p_marital_status_item_id uuid DEFAULT NULL::uuid, p_origin_department_item_id uuid DEFAULT NULL::uuid, p_occupation_item_ids uuid[] DEFAULT NULL::uuid[])
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
    v_occ uuid[];   -- E15 f1
    v_dept record;  -- E15 f1
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

    -- E15 f1: estudios, estado civil, departamento de origen y ocupación (obligatoria si el diccionario tiene opciones)
    if p_education_level_item_id is not null then
        perform public.fn_assert_catalog_item(v_org_id, 'education_level', p_education_level_item_id);
    end if;
    if p_marital_status_item_id is not null then
        perform public.fn_assert_catalog_item(v_org_id, 'marital_status', p_marital_status_item_id);
    end if;
    if p_origin_department_item_id is not null then
        perform public.fn_assert_catalog_item(v_org_id, 'department', p_origin_department_item_id);
        if not public.fn_catalog_item_is_no_response(p_origin_department_item_id) then
            if not v_has_sensitive then
                raise exception 'Control P-06: el departamento de origen es un dato sensible y exige consentimiento sensible.' using errcode = 'BV402';
            end if;
            select * into v_dept from public.catalog_item where id = p_origin_department_item_id;
            if p_nationality_country_id is null or v_dept.country_id is distinct from p_nationality_country_id then
                raise exception 'Ese departamento no corresponde al país de nacionalidad de la persona.' using errcode = 'BV337';
            end if;
        end if;
    end if;
    v_occ := public.fn_assert_occupation_set(v_org_id, p_occupation_item_ids);

    insert into public.person (
        organization_id, given_name, paternal_family_name, maternal_family_name,
        preferred_name, birth_date, birth_date_is_estimated, sex_id,
        nationality_country_id, other_nationality, primary_language_item_id,
        other_language, phone_number,
        education_level_item_id, marital_status_item_id, origin_department_item_id
    ) values (
        v_org_id, trim(p_given_name), trim(p_paternal_family_name), nullif(trim(p_maternal_family_name), ''),
        nullif(trim(p_preferred_name), ''), p_birth_date, coalesce(p_birth_date_is_estimated, false), p_sex_id,
        p_nationality_country_id, p_other_nationality, p_primary_language_item_id,
        p_other_language, nullif(trim(p_phone_number), ''),
        p_education_level_item_id, p_marital_status_item_id, p_origin_department_item_id
    ) returning id into v_person_id;

    perform public.fn_apply_person_occupations(v_person_id, v_org_id, v_occ, null);

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
        p_vulnerability_codes, p_consents, p_dates,
        p_education_level_item_id, p_marital_status_item_id, p_origin_department_item_id, p_occupation_item_ids
    );
end;
$function$;

revoke execute on function public.fn_create_case_with_person(text, text, text, text, date, boolean, int, int, text, uuid, text, text, text, boolean, int, text, int, int, text, uuid, text[], jsonb, jsonb, uuid, uuid, uuid, uuid[]) from public, anon;
grant execute on function public.fn_create_case_with_person(text, text, text, text, date, boolean, int, int, text, uuid, text, text, text, boolean, int, text, int, int, text, uuid, text[], jsonb, jsonb, uuid, uuid, uuid, uuid[]) to authenticated;
revoke execute on function public.fn_create_case_with_person_impl(text, text, text, text, date, boolean, int, int, text, uuid, text, text, text, boolean, int, text, int, int, text, uuid, text[], jsonb, jsonb, uuid, uuid, uuid, uuid[]) from public, anon, authenticated;

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
    v_needs jsonb;     -- E14 f4b
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
        'legacy_reference', c.legacy_reference,
        'reference_number', c.reference_number
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

    -- E14 f4b: las necesidades específicas marcadas (con historial) también son datos de la persona
    select coalesce(jsonb_agg(jsonb_build_object(
        'case_number', c.case_number,
        'need', ci.label_es,
        'registered_at', n.created_at,
        'closed_at', n.valid_to
    ) order by c.case_number, n.created_at), '[]'::jsonb) into v_needs
    from public.case_need n
    join public.catalog_item ci on ci.id = n.catalog_item_id
    join public.case c on c.id = n.case_id
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
            'education_level', (select ci.label_es from public.catalog_item ci where ci.id = v_person.education_level_item_id),
            'marital_status', (select ci.label_es from public.catalog_item ci where ci.id = v_person.marital_status_item_id),
            'origin_department', (select ci.label_es from public.catalog_item ci where ci.id = v_person.origin_department_item_id),
            'occupations', (select coalesce(jsonb_agg(jsonb_build_object('occupation', ci.label_es, 'registered_at', po.created_at, 'closed_at', po.valid_to) order by po.created_at), '[]'::jsonb)
                            from public.person_occupation po join public.catalog_item ci on ci.id = po.catalog_item_id where po.person_id = v_person.id),
            'is_anonymized', v_person.is_anonymized
        ),
        'cases', v_cases,
        'journal_entries', v_entries,
        'consents', v_consents,
        'documents', v_docs,
        'vulnerability_markers', v_markers,
        'dates', v_dates,
        'family', v_family,
        'specific_needs', v_needs
    );

    -- Auditoría obligatoria de emisión: la persona se identifica por record_id, no por su nombre
    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_person.organization_id, v_user_id, 'ARCO_ACCESS_EXTRACT_ISSUED', 'person', p_person_id,
            jsonb_build_object('emitted_at', now()));

    return v_result;
end;
$function$;
