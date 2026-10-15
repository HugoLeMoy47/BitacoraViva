-- ==============================================================================
-- E14 fase 2 · Las cuatro fechas del caso, con precisión flexible
--
-- Decisión del Product Owner (14 y 15 oct 2026): la hoja de casos de CAFEMIN captura cuatro fechas y el sistema
-- debe poder guardarlas todas, aunque estén incompletas (solo mes o solo año):
--   nation_entry  ingreso a la nación        nation_exit  egreso de la nación
--   shelter_entry ingreso al albergue        shelter_exit egreso del albergue
--
-- Cómo
--  * `case_date`: una fila por fecha, con su precisión (`day`, `month` o `year`). Con precisión de mes se guarda el
--    primer día del mes y con precisión de año el 1 de enero; la precisión dice cuánto se sabe realmente.
--  * Lo corregido o quitado se CIERRA con motivo (`valid_to`); nada se borra ni se sobrescribe. Un solo valor
--    vigente por tipo y caso.
--  * Solo se escribe por `fn_set_case_date` (roles que operan expedientes) y por el alta (`p_dates`, en la misma
--    transacción). El log guarda nombres de campos, nunca los valores.
--  * Validaciones: tipo y precisión válidos (BV325); nada futuro (BV326); coherencia (BV327): un ingreso no puede
--    ser posterior al egreso del mismo lugar ni anterior al nacimiento. Con fechas incompletas solo se rechaza lo
--    IMPOSIBLE: se compara el periodo entero que cubre cada fecha.
--  * Las fechas son parte del esqueleto del folio: sobreviven a la anonimización. El extracto de acceso ARCO las incluye.
--  * `case.entry_date_str` (texto «Mmmm, yyyy» de MAP-OIM) se conserva solo para lo ya guardado.
--  * Independientes del estatus de alojamiento: la relación entre «egreso del albergue» y los estatus se decide después.
--
-- Idempotente: el reinicio de la demo reaplica todas las migraciones.
-- ==============================================================================

create table if not exists public.case_date (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    case_id uuid not null references public."case"(id) on delete restrict,
    kind text not null check (kind in ('nation_entry', 'nation_exit', 'shelter_entry', 'shelter_exit')),
    value date not null,
    precision text not null check (precision in ('day', 'month', 'year')),
    created_at timestamptz not null default now(),
    created_by uuid not null references public.user_profile(id),
    valid_to timestamptz,
    closed_by uuid references public.user_profile(id),
    change_reason text,
    -- La fecha guardada es siempre el inicio del periodo que dice la precisión
    check (precision = 'day'
           or (precision = 'month' and value = date_trunc('month', value)::date)
           or (precision = 'year' and value = date_trunc('year', value)::date))
);
create unique index if not exists uq_case_date_current on public.case_date (case_id, kind) where valid_to is null;
create index if not exists idx_case_date_case on public.case_date (case_id);

alter table public.case_date enable row level security;
revoke all on public.case_date from anon;
revoke insert, update, delete on public.case_date from authenticated;

drop policy if exists tenant_operational_select on public.case_date;
create policy tenant_operational_select on public.case_date for select to authenticated
    using (organization_id = public.current_organization_id() and public.has_operational_role());

drop trigger if exists trg_audit_case_date on public.case_date;
create trigger trg_audit_case_date
after insert or update on public.case_date
for each row execute function public.fn_audit_trigger_fields();

-- Último día que puede ser lo que dice una fecha con su precisión (cota superior del periodo)
create or replace function public.fn_date_upper_bound(p_value date, p_precision text)
returns date
immutable
language sql as $$
    select case p_precision
        when 'month' then (date_trunc('month', p_value) + interval '1 month - 1 day')::date
        when 'year' then (date_trunc('year', p_value) + interval '1 year - 1 day')::date
        else p_value
    end;
$$;

-- Valida una fecha por sí sola: tipo, precisión, no futura, no anterior al nacimiento. Interna.
create or replace function public.fn_assert_case_date_value(p_kind text, p_value date, p_precision text, p_birth date)
returns date
security definer
set search_path = public
language plpgsql as $$
declare
    v_norm date;
begin
    if p_kind is null or p_kind not in ('nation_entry', 'nation_exit', 'shelter_entry', 'shelter_exit')
       or p_precision is null or p_precision not in ('day', 'month', 'year') or p_value is null then
        raise exception 'Tipo de fecha, precisión o valor no válidos.' using errcode = 'BV325';
    end if;
    v_norm := case p_precision when 'month' then date_trunc('month', p_value)::date
                               when 'year' then date_trunc('year', p_value)::date
                               else p_value end;
    if v_norm > current_date then
        raise exception 'La fecha no puede ser futura.' using errcode = 'BV326';
    end if;
    if p_birth is not null and public.fn_date_upper_bound(v_norm, p_precision) < p_birth then
        raise exception 'La fecha es anterior al nacimiento de la persona.' using errcode = 'BV327';
    end if;
    return v_norm;
end;
$$;
revoke execute on function public.fn_assert_case_date_value(text, date, text, date) from public, anon, authenticated;

-- Escribe (o corrige, o quita) una fecha del caso
create or replace function public.fn_set_case_date(
    p_case_id uuid,
    p_kind text,
    p_value date,
    p_precision text,
    p_reason text default null
)
returns uuid
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_case record;
    v_birth date;
    v_norm date;
    v_cur record;
    v_other record;
    v_other_kind text;
    v_id uuid;
begin
    if v_user is null or public.current_organization_id() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: registrar fechas exige un rol que opere expedientes (E14).' using errcode = 'BV120';
    end if;
    perform public.fn_assert_same_org('case', p_case_id);

    select c.organization_id, p.birth_date into v_case
    from public."case" c join public.person p on p.id = c.titular_person_id
    where c.id = p_case_id;
    v_birth := v_case.birth_date;

    if p_kind is null or p_kind not in ('nation_entry', 'nation_exit', 'shelter_entry', 'shelter_exit') then
        raise exception 'Tipo de fecha no válido.' using errcode = 'BV325';
    end if;

    select * into v_cur from public.case_date where case_id = p_case_id and kind = p_kind and valid_to is null;

    -- Quitar la fecha
    if p_value is null then
        if not found then
            return null;
        end if;
        if p_reason is null or btrim(p_reason) = '' then
            raise exception 'El motivo es obligatorio al quitar una fecha ya registrada (Ethos C8).' using errcode = 'BV304';
        end if;
        update public.case_date set valid_to = now(), closed_by = v_user, change_reason = btrim(p_reason) where id = v_cur.id;
        return null;
    end if;

    v_norm := public.fn_assert_case_date_value(p_kind, p_value, p_precision, v_birth);

    -- Coherencia con la fecha pareja del mismo lugar: solo se rechaza lo imposible (periodos que no se tocan)
    v_other_kind := case p_kind when 'nation_entry' then 'nation_exit' when 'nation_exit' then 'nation_entry'
                                when 'shelter_entry' then 'shelter_exit' else 'shelter_entry' end;
    select * into v_other from public.case_date where case_id = p_case_id and kind = v_other_kind and valid_to is null;
    if found then
        if p_kind in ('nation_entry', 'shelter_entry')
           and public.fn_date_upper_bound(v_other.value, v_other.precision) < v_norm then
            raise exception 'El ingreso no puede ser posterior al egreso.' using errcode = 'BV327';
        end if;
        if p_kind in ('nation_exit', 'shelter_exit')
           and public.fn_date_upper_bound(v_norm, p_precision) < v_other.value then
            raise exception 'El egreso no puede ser anterior al ingreso.' using errcode = 'BV327';
        end if;
    end if;

    if v_cur.id is not null then
        if v_cur.value = v_norm and v_cur.precision = p_precision then
            return v_cur.id;
        end if;
        if p_reason is null or btrim(p_reason) = '' then
            raise exception 'El motivo es obligatorio al cambiar una fecha ya registrada (Ethos C8).' using errcode = 'BV304';
        end if;
        update public.case_date set valid_to = now(), closed_by = v_user, change_reason = btrim(p_reason) where id = v_cur.id;
    end if;

    insert into public.case_date (organization_id, case_id, kind, value, precision, created_by)
    values (v_case.organization_id, p_case_id, p_kind, v_norm, p_precision, v_user)
    returning id into v_id;
    return v_id;
end;
$$;
revoke execute on function public.fn_set_case_date(uuid, text, date, text, text) from public, anon;
grant execute on function public.fn_set_case_date(uuid, text, date, text, text) to authenticated;

-- ---------------------------------------------------------------- Alta con fechas y extracto de acceso ARCO
-- Se redefinen a partir de la definición vigente (20261015000003 y 20261015000001); solo se agregan los pasos marcados «E14 f2».

-- El alta gana un parámetro (las fechas): se retiran las firmas anteriores
drop function if exists public.fn_create_case_with_person(text, text, text, text, date, boolean, int, int, text, int, text, text, text, boolean, int, text, int, int, text, uuid, text[], jsonb);
drop function if exists public.fn_create_case_with_person_impl(text, text, text, text, date, boolean, int, int, text, int, text, text, text, boolean, int, text, int, int, text, uuid, text[], jsonb);

CREATE OR REPLACE FUNCTION public.fn_create_case_with_person_impl(p_given_name text, p_paternal_family_name text, p_maternal_family_name text, p_preferred_name text, p_birth_date date, p_birth_date_is_estimated boolean, p_sex_id integer, p_nationality_country_id integer, p_other_nationality text, p_primary_language_id integer, p_other_language text, p_phone_number text, p_intake_window_type text, p_travels_with_family boolean, p_intake_state_id integer, p_intake_municipality_key text, p_intake_channel_id integer, p_entry_route_id integer, p_entry_date_str text, p_assigned_area_id uuid, p_vulnerability_codes text[], p_consents jsonb DEFAULT '[]'::jsonb, p_dates jsonb DEFAULT '[]'::jsonb)
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

revoke execute on function public.fn_create_case_with_person_impl(text, text, text, text, date, boolean, int, int, text, int, text, text, text, boolean, int, text, int, int, text, uuid, text[], jsonb, jsonb) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_create_case_with_person(p_given_name text, p_paternal_family_name text, p_maternal_family_name text, p_preferred_name text, p_birth_date date, p_birth_date_is_estimated boolean, p_sex_id integer, p_nationality_country_id integer, p_other_nationality text, p_primary_language_id integer, p_other_language text, p_phone_number text, p_intake_window_type text, p_travels_with_family boolean, p_intake_state_id integer, p_intake_municipality_key text, p_intake_channel_id integer, p_entry_route_id integer, p_entry_date_str text, p_assigned_area_id uuid, p_vulnerability_codes text[], p_consents jsonb DEFAULT '[]'::jsonb, p_dates jsonb DEFAULT '[]'::jsonb)
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
        p_vulnerability_codes, p_consents, p_dates
    );
end;
$function$;

revoke execute on function public.fn_create_case_with_person(text, text, text, text, date, boolean, int, int, text, int, text, text, text, boolean, int, text, int, int, text, uuid, text[], jsonb, jsonb) from public, anon;
grant execute on function public.fn_create_case_with_person(text, text, text, text, date, boolean, int, int, text, int, text, text, text, boolean, int, text, int, int, text, uuid, text[], jsonb, jsonb) to authenticated;

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
            'religion', v_person.religion,
            'is_anonymized', v_person.is_anonymized
        ),
        'cases', v_cases,
        'journal_entries', v_entries,
        'consents', v_consents,
        'documents', v_docs,
        'vulnerability_markers', v_markers,
        'dates', v_dates
    );

    -- Auditoría obligatoria de emisión: la persona se identifica por record_id, no por su nombre
    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_person.organization_id, v_user_id, 'ARCO_ACCESS_EXTRACT_ISSUED', 'person', p_person_id,
            jsonb_build_object('emitted_at', now()));

    return v_result;
end;
$function$;
