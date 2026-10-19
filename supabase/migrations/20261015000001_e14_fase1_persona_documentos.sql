-- ==============================================================================
-- E14 fase 1 · Persona y documentos (empalme con la hoja de casos de la organización piloto)
--
-- Qué agrega (decisiones del Product Owner del 14 oct 2026, 30_entrega/la guía de equivalencias de la hoja de casos):
--  * Documentos de la persona: catálogo de tipos por organización (`document_type`, lo administran
--    dirección y el área de Trabajo Social, decisión del PO del 15 oct 2026 para todo catálogo) y los documentos mismos (`person_document`: tipo + número abierto). Incluye CURP y NUE.
--    Lo corregido o quitado se CIERRA con motivo (`valid_to`); nada se borra ni se sobrescribe.
--  * Religión de la persona (`person.religion`): dato sensible, solo con consentimiento sensible vigente (D-14).
--  * Detalle de los marcadores de vulnerabilidad: usa la columna `notes` que el marcador ya tenía y que ninguna
--    función escribía; aclara el marcador (p. ej. qué violencia o qué necesidad específica) y el marcador sigue mandando.
--  * Referencia heredada del expediente (`case.legacy_reference`): el EXPEDIENTE de la hoja anterior. El folio
--    de caso del sistema no cambia.
--
-- Cómo se protege
--  * Toda escritura es por función (Regla Dura 1); `person_document` no admite INSERT/UPDATE/DELETE directos.
--  * El log de auditoría guarda nombres de campos, nunca valores (decisión del PO, 11 oct 2026): las tablas y
--    la columna de detalle nuevas usan `fn_audit_trigger_fields`.
--  * Al anonimizar a la persona, el número de documento, la religión y el detalle de los marcadores se suprimen
--    (ADR-0001). El extracto de acceso ARCO incluye todo lo nuevo (derecho de acceso).
--  * Errores con código estable (E13): BV120, BV121, BV211, BV212, BV213, BV320, BV321, BV408, BV509.
--
-- Esta migración es idempotente: el reinicio de la demo reaplica todas las migraciones.
-- ==============================================================================

-- ---------------------------------------------------------------- 1. Columnas nuevas
alter table public.person
    add column if not exists religion text;
alter table public.person drop constraint if exists person_religion_length;
alter table public.person add constraint person_religion_length
    check (religion is null or char_length(religion) <= 120);

alter table public."case"
    add column if not exists legacy_reference text;
alter table public."case" drop constraint if exists case_legacy_reference_length;
alter table public."case" add constraint case_legacy_reference_length
    check (legacy_reference is null or char_length(legacy_reference) <= 120);
create index if not exists idx_case_legacy_reference
    on public."case" (organization_id, legacy_reference) where legacy_reference is not null;

alter table public.case_vulnerability_marker drop constraint if exists case_vulnerability_marker_notes_length;
alter table public.case_vulnerability_marker add constraint case_vulnerability_marker_notes_length
    check (notes is null or char_length(notes) <= 500) not valid;

-- El detalle del marcador (`notes`) es sensible: el log de este marcador guarda solo nombres de campos
drop trigger if exists trg_audit_case_vulnerability_marker on public.case_vulnerability_marker;
create trigger trg_audit_case_vulnerability_marker
after insert or update on public.case_vulnerability_marker
for each row execute function public.fn_audit_trigger_fields();

-- ---------------------------------------------------------------- 2. Quién administra los catálogos
-- Decisión del Product Owner (15 oct 2026): los catálogos los editan dirección y el área de Trabajo Social.
-- Trabajo Social es un ÁREA, no un rol: edita quien es director, o quien opera expedientes y tiene un rol
-- vigente en el área de código `trabajo_social`. Este es el ÚNICO lugar donde se define; todo catálogo nuevo
-- usa esta función en su política.
create or replace function public.can_manage_catalogs()
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select public.has_role('director')
        or (public.has_operational_role() and public.has_role_in_area('caseworker', 'trabajo_social'))
        or (public.has_operational_role() and public.has_role_in_area('intake_officer', 'trabajo_social'));
$$;
revoke execute on function public.can_manage_catalogs() from public, anon;
grant execute on function public.can_manage_catalogs() to authenticated;

-- ---------------------------------------------------------------- 2b. Catálogo de tipos de documento
create table if not exists public.document_type (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    key text not null check (key ~ '^[a-z][a-z0-9_]{1,39}$'),
    label_es text not null check (char_length(btrim(label_es)) between 1 and 80),
    is_active boolean not null default true,
    sort_order int not null default 0,
    created_at timestamptz not null default now(),
    unique (organization_id, key)
);

alter table public.document_type enable row level security;
revoke all on public.document_type from anon;
revoke delete on public.document_type from authenticated;

drop policy if exists "Roles vigentes ven los tipos de documento de su organización" on public.document_type;
create policy "Roles vigentes ven los tipos de documento de su organización"
    on public.document_type for select to authenticated
    using (organization_id = public.current_organization_id() and public.has_any_role());

drop policy if exists "Dirección administra los tipos de documento de su organización" on public.document_type;
drop policy if exists "Dirección y Trabajo Social administran los tipos de documento" on public.document_type;
create policy "Dirección y Trabajo Social administran los tipos de documento"
    on public.document_type for all to authenticated
    using (organization_id = public.current_organization_id() and public.can_manage_catalogs())
    with check (organization_id = public.current_organization_id() and public.can_manage_catalogs());

drop trigger if exists trg_audit_document_type on public.document_type;
create trigger trg_audit_document_type
after insert or update on public.document_type
for each row execute function public.fn_audit_trigger_fields();

-- Tipos iniciales PROVISIONALES para las organizaciones que ya existen (dirección los edita; la lista real
-- de la hoja de casos se homologa después). Las organizaciones nuevas los reciben de su alta.
insert into public.document_type (organization_id, key, label_es, sort_order)
select o.id, v.key, v.label_es, v.sort_order
from public.organization o
cross join (values
    ('curp', 'CURP', 1),
    ('nue', 'NUE', 2),
    ('passport', 'Pasaporte', 3),
    ('birth_certificate', 'Acta de nacimiento', 4),
    ('national_id', 'Identificación oficial de su país', 5),
    ('refugee_claim', 'Constancia de solicitud de refugio', 6),
    ('other', 'Otro documento', 99)
) as v(key, label_es, sort_order)
on conflict (organization_id, key) do nothing;

-- ---------------------------------------------------------------- 3. Documentos de la persona
create table if not exists public.person_document (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    person_id uuid not null references public.person(id) on delete restrict,
    document_type_id uuid not null references public.document_type(id) on delete restrict,
    document_number text not null check (char_length(document_number) between 1 and 60),
    created_at timestamptz not null default now(),
    created_by uuid not null references public.user_profile(id),
    valid_to timestamptz,
    closed_by uuid references public.user_profile(id),
    change_reason text
);
-- Un solo documento vigente por tipo y persona; el historial queda cerrado
create unique index if not exists uq_person_document_current
    on public.person_document (person_id, document_type_id) where valid_to is null;
create index if not exists idx_person_document_person on public.person_document (person_id);

alter table public.person_document enable row level security;
revoke all on public.person_document from anon;
revoke insert, update, delete on public.person_document from authenticated;

drop policy if exists tenant_operational_select on public.person_document;
create policy tenant_operational_select on public.person_document for select to authenticated
    using (organization_id = public.current_organization_id() and public.has_operational_role());

drop trigger if exists trg_audit_person_document on public.person_document;
create trigger trg_audit_person_document
after insert or update on public.person_document
for each row execute function public.fn_audit_trigger_fields();

-- ---------------------------------------------------------------- 4. Consentimiento sensible vigente
-- El consentimiento es un registro por evento: el vigente es el último de cada tipo (D-14, P-06).
create or replace function public.fn_person_has_sensitive_consent(p_person_id uuid)
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select coalesce((
        select c.status = 'granted'
        from public.consent c
        where c.person_id = p_person_id and c.consent_type = 'sensitive_data'
        order by c.granted_at desc, c.id desc
        limit 1
    ), false);
$$;
revoke execute on function public.fn_person_has_sensitive_consent(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- 5. Funciones de escritura
create or replace function public.fn_set_person_document(
    p_person_id uuid,
    p_document_type_id uuid,
    p_document_number text,
    p_reason text default null
)
returns uuid
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_person record;
    v_number text := btrim(coalesce(p_document_number, ''));
    v_current record;
    v_id uuid;
begin
    if v_user is null or public.current_organization_id() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: registrar documentos exige un rol que opere expedientes (E14).' using errcode = 'BV120';
    end if;
    perform public.fn_assert_same_org('person', p_person_id);

    select * into v_person from public.person where id = p_person_id;
    if v_person.is_anonymized then
        raise exception 'Operación no permitida: una persona anonimizada no admite documentos (ADR-0001).' using errcode = 'BV507';
    end if;

    if not exists (
        select 1 from public.document_type t
        where t.id = p_document_type_id and t.organization_id = v_person.organization_id and t.is_active
    ) then
        raise exception 'El tipo de documento no existe, es de otra organización o está retirado.' using errcode = 'BV211';
    end if;

    if v_number = '' then
        raise exception 'El número del documento es obligatorio.' using errcode = 'BV320';
    end if;
    if char_length(v_number) > 60 then
        raise exception 'El número del documento excede los 60 caracteres.' using errcode = 'BV321';
    end if;

    select * into v_current from public.person_document
    where person_id = p_person_id and document_type_id = p_document_type_id and valid_to is null;
    if found then
        if v_current.document_number = v_number then
            return v_current.id;
        end if;
        if p_reason is null or btrim(p_reason) = '' then
            raise exception 'El motivo es obligatorio al cambiar un documento ya registrado (Ethos C8).' using errcode = 'BV304';
        end if;
        update public.person_document
        set valid_to = now(), closed_by = v_user, change_reason = btrim(p_reason)
        where id = v_current.id;
    end if;

    insert into public.person_document (organization_id, person_id, document_type_id, document_number, created_by)
    values (v_person.organization_id, p_person_id, p_document_type_id, v_number, v_user)
    returning id into v_id;
    return v_id;
end;
$$;

create or replace function public.fn_remove_person_document(p_document_id uuid, p_reason text)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_doc record;
begin
    if v_user is null or public.current_organization_id() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: quitar documentos exige un rol que opere expedientes (E14).' using errcode = 'BV120';
    end if;

    select * into v_doc from public.person_document
    where id = p_document_id and organization_id = public.current_organization_id();
    if not found then
        raise exception 'Documento no encontrado.' using errcode = 'BV212';
    end if;
    if v_doc.valid_to is not null then
        raise exception 'El documento ya estaba cerrado.' using errcode = 'BV509';
    end if;
    if p_reason is null or btrim(p_reason) = '' then
        raise exception 'El motivo es obligatorio al quitar un documento (Ethos C8).' using errcode = 'BV304';
    end if;

    update public.person_document
    set valid_to = now(), closed_by = v_user, change_reason = btrim(p_reason)
    where id = p_document_id;
end;
$$;

create or replace function public.fn_set_person_religion(
    p_person_id uuid,
    p_religion text,
    p_reason text default null
)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_person record;
    v_text text := nullif(btrim(coalesce(p_religion, '')), '');
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
    if v_text is not null and char_length(v_text) > 120 then
        raise exception 'La religión excede los 120 caracteres.' using errcode = 'BV321';
    end if;
    if v_text is not null and not public.fn_person_has_sensitive_consent(p_person_id) then
        raise exception 'Control P-06: la religión es un dato sensible y exige consentimiento sensible vigente (D-14).' using errcode = 'BV408';
    end if;
    if v_text is not distinct from v_person.religion then
        return;
    end if;
    if v_person.religion is not null and (p_reason is null or btrim(p_reason) = '') then
        raise exception 'El motivo es obligatorio al cambiar o quitar un dato ya registrado (Ethos C8).' using errcode = 'BV304';
    end if;

    update public.person set religion = v_text, updated_at = now() where id = p_person_id;

    if v_person.religion is not null then
        insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
        values (v_person.organization_id, v_user, 'RECTIFICATION', 'person', p_person_id,
                jsonb_build_object('changed_fields', jsonb_build_array('religion'), 'reason', btrim(p_reason)));
    end if;
end;
$$;

create or replace function public.fn_set_marker_detail(
    p_case_id uuid,
    p_marker_code text,
    p_detail text
)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_case record;
    v_detail text := nullif(btrim(coalesce(p_detail, '')), '');
begin
    if v_user is null or public.current_organization_id() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: detallar marcadores exige un rol que opere expedientes (E14).' using errcode = 'BV120';
    end if;
    perform public.fn_assert_same_org('case', p_case_id);

    select c.titular_person_id, p.is_anonymized into v_case
    from public."case" c join public.person p on p.id = c.titular_person_id
    where c.id = p_case_id;
    if v_case.is_anonymized then
        raise exception 'Operación no permitida: una persona anonimizada no admite este dato (ADR-0001).' using errcode = 'BV507';
    end if;

    if not exists (
        select 1 from public.case_vulnerability_marker m
        where m.case_id = p_case_id and m.marker_code = p_marker_code and m.removed_at is null
    ) then
        raise exception 'El expediente no tiene ese marcador de vulnerabilidad.' using errcode = 'BV213';
    end if;
    if v_detail is not null and char_length(v_detail) > 500 then
        raise exception 'El detalle excede los 500 caracteres.' using errcode = 'BV321';
    end if;
    if v_detail is not null and not public.fn_person_has_sensitive_consent(v_case.titular_person_id) then
        raise exception 'Control P-06: el detalle de un marcador es sensible y exige consentimiento sensible vigente (D-14).' using errcode = 'BV408';
    end if;

    update public.case_vulnerability_marker set notes = v_detail
    where case_id = p_case_id and marker_code = p_marker_code and removed_at is null;
end;
$$;

create or replace function public.fn_set_case_legacy_reference(
    p_case_id uuid,
    p_reference text,
    p_reason text default null
)
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
        raise exception 'Acceso denegado: la referencia heredada exige un rol que opere expedientes (E14).' using errcode = 'BV120';
    end if;
    perform public.fn_assert_same_org('case', p_case_id);

    select * into v_case from public."case" where id = p_case_id;
    if v_ref is not null and char_length(v_ref) > 120 then
        raise exception 'La referencia excede los 120 caracteres.' using errcode = 'BV321';
    end if;
    if v_ref is not distinct from v_case.legacy_reference then
        return;
    end if;
    if v_case.legacy_reference is not null and (p_reason is null or btrim(p_reason) = '') then
        raise exception 'El motivo es obligatorio al cambiar o quitar una referencia ya registrada (Ethos C8).' using errcode = 'BV304';
    end if;

    update public."case" set legacy_reference = v_ref where id = p_case_id;

    if v_case.legacy_reference is not null then
        insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
        values (v_case.organization_id, v_user, 'RECTIFICATION', 'case', p_case_id,
                jsonb_build_object('changed_fields', jsonb_build_array('legacy_reference'), 'reason', btrim(p_reason)));
    end if;
end;
$$;

revoke execute on function public.fn_set_person_document(uuid, uuid, text, text) from public, anon;
revoke execute on function public.fn_remove_person_document(uuid, text) from public, anon;
revoke execute on function public.fn_set_person_religion(uuid, text, text) from public, anon;
revoke execute on function public.fn_set_marker_detail(uuid, text, text) from public, anon;
revoke execute on function public.fn_set_case_legacy_reference(uuid, text, text) from public, anon;
grant execute on function public.fn_set_person_document(uuid, uuid, text, text) to authenticated;
grant execute on function public.fn_remove_person_document(uuid, text) to authenticated;
grant execute on function public.fn_set_person_religion(uuid, text, text) to authenticated;
grant execute on function public.fn_set_marker_detail(uuid, text, text) to authenticated;
grant execute on function public.fn_set_case_legacy_reference(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------- 6. Anonimización y extracto de acceso ARCO
-- Se redefinen a partir de la definición vigente (20261014000001); solo se agregan los pasos marcados «E14».

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
        'vulnerability_markers', v_markers
    );

    -- Auditoría obligatoria de emisión: la persona se identifica por record_id, no por su nombre
    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_person.organization_id, v_user_id, 'ARCO_ACCESS_EXTRACT_ISSUED', 'person', p_person_id,
            jsonb_build_object('emitted_at', now()));

    return v_result;
end;
$function$;
