-- ==============================================================================
-- E14 fase 3 · Unidad familiar paralela
--
-- Decisiones del Product Owner (14 y 15 oct 2026): la agrupación familiar sale de un sistema de seguimiento paralelo
-- al folio de caso (p. ej. el «Número Único de Familia» de la red de albergues), con su propio folio; **se mantiene paralela**:
-- no se mezcla con `parent_case_id` (el subfolio es otra cosa). El tipo de familia es un diccionario que editan
-- dirección y el área de Trabajo Social y es **solo informativo y estadístico**: manda el marcador de vulnerabilidad,
-- el tipo no se compara con él ni lo cambia.
--
-- Cómo
--  * `family_type`: catálogo por organización (`legacy_code` guarda la sigla de la hoja para homologar la importación).
--  * `family_unit`: la familia, con el folio del sistema paralelo (se captura, no se genera; único por organización sin
--    importar mayúsculas ni espacios) y su tipo opcional.
--  * `family_member`: la pertenencia de cada persona (por su expediente) con un consecutivo opcional. Una pertenencia
--    vigente por persona; cambiar, mover o quitar la CIERRA con motivo, nada se borra ni se sobrescribe.
--  * Todo se escribe por función (roles que operan expedientes); el log guarda nombres de campos, no el folio.
--  * Al anonimizar a la persona se cierra su pertenencia (el folio de familia puede identificar a sus parientes). El
--    extracto de acceso ARCO incluye la familia.
--  * Errores con código estable: BV218, BV219, BV330, BV331, BV332.
--
-- Idempotente: el reinicio de la demo reaplica todas las migraciones.
-- ==============================================================================

-- ---------------------------------------------------------------- 1. Tipos de familia
create table if not exists public.family_type (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    key text not null check (key ~ '^[a-z][a-z0-9_]{1,39}$'),
    label_es text not null check (char_length(btrim(label_es)) between 1 and 80),
    legacy_code text check (legacy_code is null or char_length(legacy_code) <= 40),
    is_active boolean not null default true,
    sort_order int not null default 0,
    unique (organization_id, key)
);

alter table public.family_type enable row level security;
revoke all on public.family_type from anon;
revoke delete on public.family_type from authenticated;

drop policy if exists "Roles vigentes ven los tipos de familia" on public.family_type;
create policy "Roles vigentes ven los tipos de familia" on public.family_type for select to authenticated
    using (organization_id = public.current_organization_id() and public.has_any_role());
drop policy if exists "Dirección y Trabajo Social administran los tipos de familia" on public.family_type;
create policy "Dirección y Trabajo Social administran los tipos de familia" on public.family_type for all to authenticated
    using (organization_id = public.current_organization_id() and public.can_manage_catalogs())
    with check (organization_id = public.current_organization_id() and public.can_manage_catalogs());

drop trigger if exists trg_audit_family_type on public.family_type;
create trigger trg_audit_family_type after insert or update on public.family_type
for each row execute function public.fn_audit_trigger_fields();

-- Valores de la hoja de casos de la organización piloto (lecturas confirmadas por el Product Owner); dirección y Trabajo Social los editan
insert into public.family_type (organization_id, key, label_es, legacy_code, sort_order)
select o.id, v.key, v.label_es, v.legacy_code, v.sort_order
from public.organization o
cross join (values
    ('nuclear', 'Familia nuclear', 'FAM-NUCL', 1),
    ('single_parent', 'Familia monoparental', 'FAM-MNP', 2),
    ('single_person', 'Persona sola', 'PERS-SOLA', 3),
    ('unaccompanied_minor', 'Niñez y adolescencia no acompañada', 'NNA NO ACOMPAÑADX', 4),
    ('reconstituted', 'Familia reconstituida', 'FAM-REC', 5),
    ('extended', 'Familia extensa', 'FAM-EXTENSA', 6)
) as v(key, label_es, legacy_code, sort_order)
on conflict (organization_id, key) do nothing;

-- ---------------------------------------------------------------- 2. La familia
create table if not exists public.family_unit (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    family_number text not null check (char_length(family_number) between 1 and 60),
    family_type_id uuid references public.family_type(id) on delete restrict,
    created_at timestamptz not null default now(),
    created_by uuid not null references public.user_profile(id)
);
-- El folio de la familia no se repite en la organización (sin distinguir mayúsculas ni espacios)
create unique index if not exists uq_family_unit_number on public.family_unit (organization_id, lower(btrim(family_number)));

alter table public.family_unit enable row level security;
revoke all on public.family_unit from anon;
revoke insert, update, delete on public.family_unit from authenticated;
drop policy if exists tenant_operational_select on public.family_unit;
create policy tenant_operational_select on public.family_unit for select to authenticated
    using (organization_id = public.current_organization_id() and public.has_operational_role());
drop trigger if exists trg_audit_family_unit on public.family_unit;
create trigger trg_audit_family_unit after insert or update on public.family_unit
for each row execute function public.fn_audit_trigger_fields();

-- ---------------------------------------------------------------- 3. La pertenencia de cada persona
create table if not exists public.family_member (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    family_unit_id uuid not null references public.family_unit(id) on delete restrict,
    case_id uuid not null references public."case"(id) on delete restrict,
    member_order int check (member_order is null or member_order >= 1),
    created_at timestamptz not null default now(),
    created_by uuid not null references public.user_profile(id),
    valid_to timestamptz,
    closed_by uuid references public.user_profile(id),
    change_reason text
);
create unique index if not exists uq_family_member_current on public.family_member (case_id) where valid_to is null;
create index if not exists idx_family_member_unit on public.family_member (family_unit_id);

alter table public.family_member enable row level security;
revoke all on public.family_member from anon;
revoke insert, update, delete on public.family_member from authenticated;
drop policy if exists tenant_operational_select on public.family_member;
create policy tenant_operational_select on public.family_member for select to authenticated
    using (organization_id = public.current_organization_id() and public.has_operational_role());
drop trigger if exists trg_audit_family_member on public.family_member;
create trigger trg_audit_family_member after insert or update on public.family_member
for each row execute function public.fn_audit_trigger_fields();

-- ---------------------------------------------------------------- 4. Funciones
-- Interna: valida y crea la familia. La usan fn_create_family_unit y fn_set_case_family.
create or replace function public.fn_family_unit_insert(p_org uuid, p_number text, p_type_id uuid)
returns uuid
security definer
set search_path = public
language plpgsql as $$
declare
    v_number text := btrim(coalesce(p_number, ''));
    v_id uuid;
begin
    if v_number = '' then
        raise exception 'El folio de la familia es obligatorio.' using errcode = 'BV320';
    end if;
    if char_length(v_number) > 60 then
        raise exception 'El folio de la familia excede los 60 caracteres.' using errcode = 'BV321';
    end if;
    if p_type_id is not null and not exists (
        select 1 from public.family_type t where t.id = p_type_id and t.organization_id = p_org and t.is_active
    ) then
        raise exception 'El tipo de familia no existe, es de otra organización o está retirado.' using errcode = 'BV218';
    end if;
    if exists (select 1 from public.family_unit f where f.organization_id = p_org and lower(btrim(f.family_number)) = lower(v_number)) then
        raise exception 'Ya existe una familia con ese folio.' using errcode = 'BV330';
    end if;
    insert into public.family_unit (organization_id, family_number, family_type_id, created_by)
    values (p_org, v_number, p_type_id, auth.uid())
    returning id into v_id;
    return v_id;
end;
$$;
revoke execute on function public.fn_family_unit_insert(uuid, text, uuid) from public, anon, authenticated;

create or replace function public.fn_create_family_unit(p_family_number text, p_family_type_id uuid default null)
returns uuid
security definer
set search_path = public
language plpgsql as $$
begin
    if auth.uid() is null or public.current_organization_id() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: crear familias exige un rol que opere expedientes (E14).' using errcode = 'BV120';
    end if;
    return public.fn_family_unit_insert(public.current_organization_id(), p_family_number, p_family_type_id);
end;
$$;
revoke execute on function public.fn_create_family_unit(text, uuid) from public, anon;
grant execute on function public.fn_create_family_unit(text, uuid) to authenticated;

-- Asigna, mueve o quita a una persona (por su expediente) de una familia; opcionalmente crea la familia en el mismo paso
create or replace function public.fn_set_case_family(
    p_case_id uuid,
    p_family_unit_id uuid,
    p_member_order int,
    p_reason text default null,
    p_new_family_number text default null,
    p_new_family_type_id uuid default null
)
returns uuid
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_org uuid;
    v_new_number text := nullif(btrim(coalesce(p_new_family_number, '')), '');
    v_unit uuid;
    v_cur record;
    v_id uuid;
begin
    if v_user is null or public.current_organization_id() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: asignar familias exige un rol que opere expedientes (E14).' using errcode = 'BV120';
    end if;
    perform public.fn_assert_same_org('case', p_case_id);
    select organization_id into v_org from public."case" where id = p_case_id;

    if p_family_unit_id is not null and v_new_number is not null then
        raise exception 'Indica una familia existente o el folio de una nueva, no ambas.' using errcode = 'BV332';
    end if;
    if p_member_order is not null and p_member_order < 1 then
        raise exception 'El consecutivo debe ser un número positivo.' using errcode = 'BV331';
    end if;

    select * into v_cur from public.family_member where case_id = p_case_id and valid_to is null;

    -- Quitar a la persona de su familia
    if p_family_unit_id is null and v_new_number is null then
        if not found then
            return null;
        end if;
        if p_reason is null or btrim(p_reason) = '' then
            raise exception 'El motivo es obligatorio al quitar a la persona de su familia (Ethos C8).' using errcode = 'BV304';
        end if;
        update public.family_member set valid_to = now(), closed_by = v_user, change_reason = btrim(p_reason) where id = v_cur.id;
        return null;
    end if;

    if p_family_unit_id is not null then
        if not exists (select 1 from public.family_unit f where f.id = p_family_unit_id and f.organization_id = v_org) then
            raise exception 'La familia no existe o es de otra organización.' using errcode = 'BV219';
        end if;
        v_unit := p_family_unit_id;
        if v_cur.id is not null and v_cur.family_unit_id = v_unit and v_cur.member_order is not distinct from p_member_order then
            return v_cur.id;
        end if;
    end if;

    if v_cur.id is not null and (p_reason is null or btrim(p_reason) = '') then
        raise exception 'El motivo es obligatorio al cambiar la familia o el consecutivo de una persona (Ethos C8).' using errcode = 'BV304';
    end if;

    if v_unit is null then
        v_unit := public.fn_family_unit_insert(v_org, v_new_number, p_new_family_type_id);
    end if;
    if v_cur.id is not null then
        update public.family_member set valid_to = now(), closed_by = v_user, change_reason = btrim(p_reason) where id = v_cur.id;
    end if;

    insert into public.family_member (organization_id, family_unit_id, case_id, member_order, created_by)
    values (v_org, v_unit, p_case_id, p_member_order, v_user)
    returning id into v_id;
    return v_id;
end;
$$;
revoke execute on function public.fn_set_case_family(uuid, uuid, int, text, text, uuid) from public, anon;
grant execute on function public.fn_set_case_family(uuid, uuid, int, text, text, uuid) to authenticated;

-- Cambia (o quita) el tipo de la familia: solo informa; no se compara con los marcadores
create or replace function public.fn_set_family_type(p_family_unit_id uuid, p_family_type_id uuid, p_reason text default null)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_unit record;
begin
    if v_user is null or public.current_organization_id() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: cambiar el tipo de familia exige un rol que opere expedientes (E14).' using errcode = 'BV120';
    end if;
    select * into v_unit from public.family_unit where id = p_family_unit_id and organization_id = public.current_organization_id();
    if not found then
        raise exception 'La familia no existe o es de otra organización.' using errcode = 'BV219';
    end if;
    if p_family_type_id is not null and not exists (
        select 1 from public.family_type t where t.id = p_family_type_id and t.organization_id = v_unit.organization_id and t.is_active
    ) then
        raise exception 'El tipo de familia no existe, es de otra organización o está retirado.' using errcode = 'BV218';
    end if;
    if p_family_type_id is not distinct from v_unit.family_type_id then
        return;
    end if;
    if v_unit.family_type_id is not null and (p_reason is null or btrim(p_reason) = '') then
        raise exception 'El motivo es obligatorio al cambiar o quitar un tipo ya registrado (Ethos C8).' using errcode = 'BV304';
    end if;

    update public.family_unit set family_type_id = p_family_type_id where id = p_family_unit_id;

    if v_unit.family_type_id is not null then
        insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
        values (v_unit.organization_id, v_user, 'RECTIFICATION', 'family_unit', p_family_unit_id,
                jsonb_build_object('changed_fields', jsonb_build_array('family_type_id'), 'reason', btrim(p_reason)));
    end if;
end;
$$;
revoke execute on function public.fn_set_family_type(uuid, uuid, text) from public, anon;
grant execute on function public.fn_set_family_type(uuid, uuid, text) to authenticated;

-- ---------------------------------------------------------------- 5. Anonimización y extracto de acceso ARCO
-- Se redefinen a partir de la definición vigente (20261015000001 y 20261016000001); solo se agregan los pasos marcados «E14 f3».

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
        religion = null,                                  -- E14
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
            'religion', v_person.religion,
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
