-- ==============================================================================
-- E17 fase 3 · Áreas administrables
--
-- Contexto: la pantalla «Áreas» solo listaba. Además, la base limitaba el código de área a cinco valores fijos y parte de la
-- lógica se apoyaba en ellos: «coordinacion» era el área donde escribe quien no tiene área, y «trabajo_social» la que se propone
-- al abrir un expediente. Decisión del Product Owner (24 oct 2026, «de acuerdo con tus recomendaciones»): crear, renombrar,
-- desactivar y reactivar áreas (nunca borrar) y que la dirección elija esas dos.
--
-- Cómo
--  * El código interno de un área deja de estar limitado a cinco valores: solo tiene forma válida (minúsculas, números y guion
--    bajo). Es estable: renombrar no lo cambia. Las cinco actuales conservan el suyo.
--  * Dos marcas, **una por organización como máximo**: `is_general` (el área donde escribe quien no tiene área; antes el código
--    fijo `coordinacion`) e `is_default_intake` (la que se propone al abrir un expediente; antes `trabajo_social`). Las áreas con
--    esos códigos históricos nacen marcadas si la organización aún no tiene otra, y las existentes se marcan ahora.
--  * `fn_create_area`, `fn_rename_area`, `fn_set_area_active` y `fn_set_default_area`, con la capacidad `manage_areas`
--    (BV359). Nombre válido (BV360) y no repetido (BV361); el área debe ser de la organización (BV362); no se desactiva un área
--    marcada (BV363); solo un área activa puede marcarse (BV364); desactivar pide motivo (BV365). Nada se borra.
--  * Las áreas ya no se escriben por la API directa (D-20): se quitan sus permisos de escritura y sus dos políticas. Quien
--    administra áreas ve también las inactivas (política de lectura nueva).
--  * `fn_create_journal_entry` y `fn_create_subfolio` usan `is_general` en lugar del código fijo.
-- ==============================================================================

-- ---------------------------------------------------------------- 1. Estructura
alter table public.area drop constraint if exists area_code_check;
alter table public.area add constraint area_code_form check (code ~ '^[a-z][a-z0-9_]{0,63}$');
alter table public.area add column if not exists is_general boolean not null default false;
alter table public.area add column if not exists is_default_intake boolean not null default false;
create unique index if not exists uq_area_general on public.area (organization_id) where is_general;
create unique index if not exists uq_area_default_intake on public.area (organization_id) where is_default_intake;

-- Las existentes: coordinación es el área general y Trabajo Social la de apertura (como funcionaba hasta hoy)
update public.area a set is_general = true
where a.code = 'coordinacion' and not exists (select 1 from public.area x where x.organization_id = a.organization_id and x.is_general);
update public.area a set is_default_intake = true
where a.code = 'trabajo_social' and not exists (select 1 from public.area x where x.organization_id = a.organization_id and x.is_default_intake);

-- Las nuevas con esos códigos históricos nacen marcadas si la organización aún no tiene otra (compatibilidad con la semilla)
create or replace function public.fn_area_default_marks()
returns trigger
language plpgsql as $$
begin
    if new.code = 'coordinacion' and not new.is_general
       and not exists (select 1 from public.area a where a.organization_id = new.organization_id and a.is_general) then
        new.is_general := true;
    end if;
    if new.code = 'trabajo_social' and not new.is_default_intake
       and not exists (select 1 from public.area a where a.organization_id = new.organization_id and a.is_default_intake) then
        new.is_default_intake := true;
    end if;
    return new;
end;
$$;
drop trigger if exists trg_area_default_marks on public.area;
create trigger trg_area_default_marks before insert on public.area
for each row execute function public.fn_area_default_marks();

-- ---------------------------------------------------------------- 2. Funciones de administración
create or replace function public.fn_create_area(p_name text)
returns uuid
security definer
set search_path = public
language plpgsql as $$
declare
    v_org uuid := public.current_organization_id();
    v_name text := btrim(coalesce(p_name, ''));
    v_base text;
    v_code text;
    v_n int := 1;
    v_id uuid;
begin
    if auth.uid() is null or v_org is null or not public.has_capability('manage_areas') then
        raise exception 'Acceso denegado: administrar las áreas requiere ese permiso (por omisión, la dirección).' using errcode = 'BV359';
    end if;
    if v_name = '' or char_length(v_name) > 80 then
        raise exception 'El nombre del área es obligatorio y no puede pasar de 80 caracteres.' using errcode = 'BV360';
    end if;
    if exists (select 1 from public.area a where a.organization_id = v_org and lower(btrim(a.name)) = lower(v_name)) then
        raise exception 'Ya existe un área con ese nombre.' using errcode = 'BV361';
    end if;

    -- Código interno estable a partir del nombre: sin acentos, minúsculas, guion bajo, único en la organización
    v_base := lower(translate(v_name, 'áéíóúüñÁÉÍÓÚÜÑ', 'aeiouunaeiouun'));
    v_base := btrim(regexp_replace(v_base, '[^a-z0-9]+', '_', 'g'), '_');
    if v_base = '' or v_base !~ '^[a-z]' then
        v_base := 'area_' || v_base;
    end if;
    v_base := btrim(left(v_base, 56), '_');
    v_code := v_base;
    while exists (select 1 from public.area a where a.organization_id = v_org and a.code = v_code) loop
        v_n := v_n + 1;
        v_code := v_base || '_' || v_n;
    end loop;

    insert into public.area (organization_id, code, name, active) values (v_org, v_code, v_name, true) returning id into v_id;
    return v_id;
end;
$$;
revoke execute on function public.fn_create_area(text) from public, anon;
grant execute on function public.fn_create_area(text) to authenticated;

create or replace function public.fn_rename_area(p_area_id uuid, p_name text)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_org uuid := public.current_organization_id();
    v_name text := btrim(coalesce(p_name, ''));
begin
    if auth.uid() is null or v_org is null or not public.has_capability('manage_areas') then
        raise exception 'Acceso denegado: administrar las áreas requiere ese permiso (por omisión, la dirección).' using errcode = 'BV359';
    end if;
    if not exists (select 1 from public.area a where a.id = p_area_id and a.organization_id = v_org) then
        raise exception 'Esa área no existe en tu organización o la marca no es válida.' using errcode = 'BV362';
    end if;
    if v_name = '' or char_length(v_name) > 80 then
        raise exception 'El nombre del área es obligatorio y no puede pasar de 80 caracteres.' using errcode = 'BV360';
    end if;
    if exists (select 1 from public.area a where a.organization_id = v_org and a.id <> p_area_id and lower(btrim(a.name)) = lower(v_name)) then
        raise exception 'Ya existe un área con ese nombre.' using errcode = 'BV361';
    end if;
    update public.area set name = v_name where id = p_area_id and name is distinct from v_name;
end;
$$;
revoke execute on function public.fn_rename_area(uuid, text) from public, anon;
grant execute on function public.fn_rename_area(uuid, text) to authenticated;

create or replace function public.fn_set_area_active(p_area_id uuid, p_active boolean, p_reason text default null)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_org uuid := public.current_organization_id();
    v_area public.area%rowtype;
begin
    if auth.uid() is null or v_org is null or not public.has_capability('manage_areas') then
        raise exception 'Acceso denegado: administrar las áreas requiere ese permiso (por omisión, la dirección).' using errcode = 'BV359';
    end if;
    select * into v_area from public.area a where a.id = p_area_id and a.organization_id = v_org;
    if v_area.id is null or p_active is null then
        raise exception 'Esa área no existe en tu organización o la marca no es válida.' using errcode = 'BV362';
    end if;
    if p_active = v_area.active then
        return;
    end if;
    if not p_active then
        if v_area.is_general or v_area.is_default_intake then
            raise exception 'Esta área es la general o la de apertura de expedientes: elige primero otra y luego desactívala.' using errcode = 'BV363';
        end if;
        if p_reason is null or btrim(p_reason) = '' then
            raise exception 'Indica el motivo: es obligatorio al desactivar un área.' using errcode = 'BV365';
        end if;
    end if;

    update public.area set active = p_active where id = p_area_id;
    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_org, auth.uid(), 'RECTIFICATION', 'area', p_area_id,
            jsonb_build_object('changed_fields', jsonb_build_array('active'), 'reason', nullif(btrim(coalesce(p_reason, '')), '')));
end;
$$;
revoke execute on function public.fn_set_area_active(uuid, boolean, text) from public, anon;
grant execute on function public.fn_set_area_active(uuid, boolean, text) to authenticated;

-- Elegir cuál es el área general (donde escribe quien no tiene área) y cuál se propone al abrir un expediente: una de cada una
create or replace function public.fn_set_default_area(p_kind text, p_area_id uuid)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_org uuid := public.current_organization_id();
    v_area public.area%rowtype;
begin
    if auth.uid() is null or v_org is null or not public.has_capability('manage_areas') then
        raise exception 'Acceso denegado: administrar las áreas requiere ese permiso (por omisión, la dirección).' using errcode = 'BV359';
    end if;
    if p_kind is null or p_kind not in ('general', 'default_intake') then
        raise exception 'Esa área no existe en tu organización o la marca no es válida.' using errcode = 'BV362';
    end if;
    select * into v_area from public.area a where a.id = p_area_id and a.organization_id = v_org;
    if v_area.id is null then
        raise exception 'Esa área no existe en tu organización o la marca no es válida.' using errcode = 'BV362';
    end if;
    if not v_area.active then
        raise exception 'Solo un área activa puede ser la general o la de apertura de expedientes.' using errcode = 'BV364';
    end if;

    if p_kind = 'general' then
        update public.area set is_general = false where organization_id = v_org and is_general and id <> p_area_id;
        update public.area set is_general = true where id = p_area_id and not is_general;
    else
        update public.area set is_default_intake = false where organization_id = v_org and is_default_intake and id <> p_area_id;
        update public.area set is_default_intake = true where id = p_area_id and not is_default_intake;
    end if;
end;
$$;
revoke execute on function public.fn_set_default_area(text, uuid) from public, anon;
grant execute on function public.fn_set_default_area(text, uuid) to authenticated;

-- ---------------------------------------------------------------- 3. Ya no se escribe directo (D-20)
revoke insert, update, delete on public.area from authenticated;
drop policy if exists area_manage_insert on public.area;
drop policy if exists area_manage_update on public.area;

-- Quien administra áreas ve también las inactivas (para poder reactivarlas). La política general solo muestra las activas; la
-- que daba esta lectura a la dirección se había perdido al repartir la política «for all» en dos de escritura (D-24 tanda 2).
drop policy if exists area_manage_select on public.area;
create policy area_manage_select on public.area for select to authenticated
    using (organization_id = public.current_organization_id() and (select public.has_capability('manage_areas')));

-- ---------------------------------------------------------------- 4. La lógica que dependía del código fijo
-- fn_create_journal_entry
create or replace function public.fn_create_journal_entry(
    p_case_id uuid, p_entry_type_key text, p_body text,
    p_occurred_at timestamptz default now(), p_is_work_note boolean default false,
    p_area_id uuid default null, p_service_line_item_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
    v_user_id uuid;
    v_org_id uuid;
    v_area_id uuid;
    v_new_entry_id uuid;
    v_area_code text;
    v_area_general boolean;
begin
    if auth.uid() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: se requiere una sesión con rol operativo vigente.' using errcode = 'BV101';
    end if;
    perform public.fn_assert_same_org('case', p_case_id);
    v_user_id := auth.uid();

    if p_body is null or trim(p_body) = '' then
        raise exception 'El texto de la intervención en bitácora es obligatorio.' using errcode = 'BV310';
    end if;

    select organization_id into v_org_id from public.case where id = p_case_id;
    if v_org_id is null then
        raise exception 'Expediente no encontrado.' using errcode = 'BV203';
    end if;

    -- E14 f4: la línea de servicio, si se indica, es un valor activo del diccionario de esta organización
    if p_service_line_item_id is not null then
        perform public.fn_assert_catalog_item(v_org_id, 'service_line', p_service_line_item_id);
    end if;

    if p_area_id is not null then
        -- Escribir a nombre de un área exige ser de esa área (o dirección) y que sea de la misma
        -- organización. Quien no tiene área asignada (ingreso) solo escribe en coordinación.
        select a.code, a.is_general into v_area_code, v_area_general
        from public.area a
        where a.id = p_area_id and a.organization_id = v_org_id and a.active;
        if v_area_code is null then
            raise exception 'Área no válida para esta organización.' using errcode = 'BV208';
        end if;

        if not public.has_role('director') then
            if exists (
                select 1 from public.user_role ur
                where ur.user_id = v_user_id and ur.revoked_at is null and ur.area_id is not null
            ) then
                if not exists (
                    select 1 from public.user_role ur
                    where ur.user_id = v_user_id and ur.revoked_at is null and ur.area_id = p_area_id
                ) then
                    raise exception 'Permiso denegado: solo se escribe a nombre del propio área (Ethos C2, C4).' using errcode = 'BV117';
                end if;
            elsif not v_area_general then
                raise exception 'Permiso denegado: sin área asignada solo se escribe a nombre del área general.' using errcode = 'BV118';
            end if;
        end if;
        v_area_id := p_area_id;
    else
        select area_id into v_area_id
        from public.user_role
        where user_id = v_user_id and revoked_at is null and area_id is not null
        limit 1;

        if v_area_id is null then
            select id into v_area_id
            from public.area
            where organization_id = v_org_id and is_general and active
            limit 1;
        end if;
    end if;

    if v_area_id is null then
        raise exception 'No se pudo determinar el área operativa para el registro de bitácora.' using errcode = 'BV702';
    end if;

    insert into public.journal_entry (
        organization_id, case_id, area_id, author_user_id, entry_type_key,
        body, is_work_note, occurred_at, created_at, visibility, service_line_item_id, source
    ) values (
        v_org_id, p_case_id, v_area_id, v_user_id, p_entry_type_key,
        p_body, p_is_work_note, coalesce(p_occurred_at, now()), now(), 'area_private', p_service_line_item_id, 'app'
    ) returning id into v_new_entry_id;

    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_org_id, v_user_id, 'INSERT', 'journal_entry', v_new_entry_id,
        jsonb_build_object(
            'case_id', p_case_id,
            'entry_type_key', p_entry_type_key,
            'is_work_note', p_is_work_note,
            'area_id', v_area_id,
            'occurred_at', p_occurred_at,
            'service_line_item_id', p_service_line_item_id
        ));

    return v_new_entry_id;
end;
$function$;

-- fn_create_subfolio
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
        (select a.id from public.area a where a.organization_id = v_org_id and a.is_general and a.active limit 1),
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
