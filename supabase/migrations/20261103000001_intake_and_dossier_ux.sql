-- ==============================================================================
-- Ciclo «Ingreso y expediente» (contrato de handoff del 01 nov 2026)
--
-- Origen: validación de campo con Trabajo Social y decisiones del Product Owner (diario, 01 nov 2026), Ethos v1.4 (E-01).
-- Esta migración cubre la parte de base de datos. Adaptaciones al contrato, por lo que el esquema real ya tenía:
--  * No existe `case_consent`: las tres autorizaciones físicas viven en `case` (`photo_consent`,
--    `coexistence_rules_accepted`, `nna_responsibility_accepted`) y cambian solo con `fn_set_case_authorizations` (motivo + auditoría).
--    Sin valor por omisión (la suite lo exige: «ningún valor supuesto»): vacío = «No registrado»; `false` es una respuesta explícita.
--    Lo mismo con `identity_documents_presented`: vacío = «No registrado»; `['none']` = «no cuenta con documentos».
--  * No existe `dictionary_identity_document`: el diccionario es `identity_document` de `catalog_item` (la infraestructura de
--    E14/E15, editable por dirección y Trabajo Social, con su pantalla «Diccionarios» y sus pruebas). Un `text[]` no admite
--    claves foráneas: un disparador valida cada clave contra ese diccionario.
--  * El contexto de ingreso usa los valores que ya existen (`fija`, `movil`, `transaccional`) y NO tiene valor por omisión:
--    «ningún valor supuesto». Vacío = la organización no lo ha configurado y quien captura lo elige.
--  * No existe `vulnerability_factor`: los marcadores son un catálogo cerrado en una restricción; se agregan `cuidador_monoparental`
--    y `cuidados_paliativos` (sensibles como todos los marcadores: exigen consentimiento sensible, BV402).
--  * El país se guarda también como ISO 3166-1 alfa-2 (`nationality_iso`, sensible). `nationality_country_id` se conserva
--    (Honduras 93, Guatemala 86, «otro» 1) para no tocar los diccionarios ni los indicadores que dependen de él.
--  * Fotografía (Ethos E-01 v1.4): solo la compuerta. Bucket privado `dossier-photos` (webp, 256 KB), política de subida que
--    exige `case.photo_consent`, y `fn_request_dossier_photo_upload` (BV402 sin consentimiento). La lectura con URL firmada
--    y auditoría y la captura en pantalla son de la fase posterior acordada: por ahora nadie puede leer lo subido.
--
-- Errores nuevos: BV367 (documentos de identificación), BV368 (segundo teléfono), BV369 (país), BV370 (contexto de ingreso),
-- BV371 (autorizaciones). Se reutilizan BV109, BV101, BV113, BV304, BV402 y BV507.
-- ==============================================================================

-- ---------------------------------------------------------------- 1. Contexto de ingreso por organización
alter table public.organization add column if not exists default_intake_context text;
alter table public.organization drop constraint if exists organization_default_intake_context_check;
alter table public.organization add constraint organization_default_intake_context_check
    check (default_intake_context is null or default_intake_context in ('fija', 'movil', 'transaccional'));

create or replace function public.fn_set_organization_default_intake_context(p_context text)
returns void
security definer
set search_path = public, auth
language plpgsql as $$
declare
    v_org uuid := public.current_organization_id();
begin
    if auth.uid() is null or v_org is null or not public.has_capability('manage_org_settings') then
        raise exception 'Acceso denegado: solo la dirección configura la organización.' using errcode = 'BV109';
    end if;
    if p_context is not null and p_context not in ('fija', 'movil', 'transaccional') then
        raise exception 'El contexto de ingreso no es válido: elige ventanilla fija, móvil o transaccional.' using errcode = 'BV370';
    end if;
    update public.organization set default_intake_context = p_context where id = v_org and default_intake_context is distinct from p_context;
end;
$$;
revoke execute on function public.fn_set_organization_default_intake_context(text) from public, anon;
grant execute on function public.fn_set_organization_default_intake_context(text) to authenticated;

-- ---------------------------------------------------------------- 2. Diccionario «documentos de identificación»
alter table public.catalog_item drop constraint if exists catalog_item_catalog_check;
alter table public.catalog_item add constraint catalog_item_catalog_check
    check (catalog in ('language', 'religion', 'specific_need', 'service_line', 'education_level', 'marital_status', 'occupation', 'department', 'family_role', 'identity_document'));

insert into public.catalog_item (organization_id, catalog, key, label_es, is_system, sort_order)
select o.id, 'identity_document', v.key, v.label_es, v.is_system, v.sort_order
from public.organization o
cross join (values
    ('origin_id', 'Cédula o documento de identidad del país de origen', false, 1),
    ('passport', 'Pasaporte', false, 2),
    ('birth_cert', 'Acta de nacimiento', false, 3),
    ('ine', 'INE (credencial para votar, México)', false, 4),
    ('curp', 'CURP', false, 5),
    ('comar_doc', 'Constancia de solicitud de refugio (COMAR)', false, 6),
    ('inm_doc', 'Forma migratoria o tarjeta de visitante (INM)', false, 7),
    ('other_doc', 'Otro documento de identidad', false, 8),
    ('none', 'No cuenta con documentos de identificación', true, 9)
) as v(key, label_es, is_system, sort_order)
on conflict (organization_id, catalog, key) do nothing;

-- ---------------------------------------------------------------- 3. Persona: segundo teléfono, documentos y país (ISO)
alter table public.person add column if not exists secondary_phone text;
alter table public.person add column if not exists secondary_phone_label text;
alter table public.person add column if not exists identity_documents_presented text[];
alter table public.person add column if not exists nationality_iso text;

alter table public.person drop constraint if exists person_secondary_phone_check;
alter table public.person add constraint person_secondary_phone_check
    check (secondary_phone is null or (btrim(secondary_phone) <> '' and char_length(secondary_phone) <= 30));
alter table public.person drop constraint if exists person_secondary_phone_label_check;
alter table public.person add constraint person_secondary_phone_label_check
    check (secondary_phone_label is null or (secondary_phone is not null and secondary_phone_label in ('familiar', 'whatsapp', 'propio', 'acompanante', 'otro')));
alter table public.person drop constraint if exists person_nationality_iso_check;
alter table public.person add constraint person_nationality_iso_check check (nationality_iso is null or nationality_iso ~ '^[A-Z]{2}$');
-- «Ninguno» no puede ir junto con ningún otro documento
alter table public.person drop constraint if exists person_identity_documents_none_check;
alter table public.person add constraint person_identity_documents_none_check
    check (not ('none' = any (identity_documents_presented)) or cardinality(identity_documents_presented) = 1);

-- Cada clave debe existir en el diccionario de la organización de la persona (un arreglo no admite clave foránea)
create or replace function public.fn_assert_identity_documents(p_org uuid, p_docs text[])
returns text[]
language plpgsql
stable
set search_path = public
as $$
declare
    v_docs text[];
begin
    if p_docs is null or cardinality(p_docs) = 0 then
        return null;
    end if;
    select array_agg(distinct btrim(d) order by btrim(d)) into v_docs from unnest(p_docs) d;
    if exists (select 1 from unnest(v_docs) d where d is null or d = '') then
        raise exception 'Los documentos de identificación no son válidos.' using errcode = 'BV367';
    end if;
    if 'none' = any (v_docs) and cardinality(v_docs) > 1 then
        raise exception 'Los documentos de identificación no son válidos: «No cuenta con documentos» no puede ir junto con otros.' using errcode = 'BV367';
    end if;
    if exists (
        select 1 from unnest(v_docs) d
        where not exists (select 1 from public.catalog_item i where i.organization_id = p_org and i.catalog = 'identity_document' and i.key = d and i.is_active)
    ) then
        raise exception 'Los documentos de identificación no son válidos: alguno no está en el diccionario.' using errcode = 'BV367';
    end if;
    return v_docs;
end;
$$;
revoke execute on function public.fn_assert_identity_documents(uuid, text[]) from public, anon, authenticated;

create or replace function public.fn_person_identity_documents_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
    if tg_op = 'INSERT' or new.identity_documents_presented is distinct from old.identity_documents_presented then
        new.identity_documents_presented := public.fn_assert_identity_documents(new.organization_id, new.identity_documents_presented);
    end if;
    return new;
end;
$$;
drop trigger if exists trg_person_identity_documents_guard on public.person;
create trigger trg_person_identity_documents_guard before insert or update of identity_documents_presented on public.person
for each row execute function public.fn_person_identity_documents_guard();

-- ---------------------------------------------------------------- 4. Caso: autorizaciones firmadas en físico
alter table public."case" add column if not exists photo_consent boolean;
alter table public."case" add column if not exists coexistence_rules_accepted boolean;
alter table public."case" add column if not exists nna_responsibility_accepted boolean;

create or replace function public.fn_set_case_authorizations(
    p_case_id uuid, p_photo_consent boolean, p_coexistence_rules boolean, p_nna_responsibility boolean, p_reason text default null
)
returns void
security definer
set search_path = public, auth
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_case record;
    v_changed jsonb;
begin
    if v_user is null or public.current_organization_id() is null or not public.has_operational_role() then
        raise exception 'Tu sesión no tiene un rol vigente.' using errcode = 'BV101';
    end if;
    perform public.fn_assert_same_org('case', p_case_id);
    if p_photo_consent is null or p_coexistence_rules is null then
        raise exception 'Indica si cuenta con cada autorización (sí o no).' using errcode = 'BV371';
    end if;
    select c.id, c.organization_id, c.photo_consent, c.coexistence_rules_accepted, c.nna_responsibility_accepted, p.is_anonymized
    into v_case
    from public."case" c join public.person p on p.id = c.titular_person_id
    where c.id = p_case_id;
    if v_case.is_anonymized then
        raise exception 'Operación no permitida: una persona anonimizada no admite este dato (ADR-0001).' using errcode = 'BV507';
    end if;

    select coalesce(jsonb_agg(f order by f), '[]'::jsonb) into v_changed from (
        select 'photo_consent' as f where p_photo_consent is distinct from v_case.photo_consent
        union all select 'coexistence_rules_accepted' where p_coexistence_rules is distinct from v_case.coexistence_rules_accepted
        union all select 'nna_responsibility_accepted' where p_nna_responsibility is distinct from v_case.nna_responsibility_accepted
    ) x;
    if jsonb_array_length(v_changed) = 0 then
        return;
    end if;
    -- Registrar por primera vez (vacío → valor) no pide motivo; cambiar o quitar un valor ya registrado, sí (Ethos C8)
    if ((p_photo_consent is distinct from v_case.photo_consent and v_case.photo_consent is not null)
        or (p_coexistence_rules is distinct from v_case.coexistence_rules_accepted and v_case.coexistence_rules_accepted is not null)
        or (p_nna_responsibility is distinct from v_case.nna_responsibility_accepted and v_case.nna_responsibility_accepted is not null))
       and (p_reason is null or btrim(p_reason) = '') then
        raise exception 'El motivo es obligatorio al cambiar o quitar un dato ya registrado (Ethos C8).' using errcode = 'BV304';
    end if;

    update public."case"
       set photo_consent = p_photo_consent, coexistence_rules_accepted = p_coexistence_rules, nna_responsibility_accepted = p_nna_responsibility
     where id = p_case_id;
    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_case.organization_id, v_user, 'RECTIFICATION', 'case', p_case_id,
            jsonb_build_object('changed_fields', v_changed, 'reason', btrim(p_reason)));
end;
$$;
revoke execute on function public.fn_set_case_authorizations(uuid, boolean, boolean, boolean, text) from public, anon;
grant execute on function public.fn_set_case_authorizations(uuid, boolean, boolean, boolean, text) to authenticated;

-- ---------------------------------------------------------------- 5. Marcadores de vulnerabilidad (sensibles)
do $$
declare
    c text;
begin
    for c in
        select conname from pg_constraint
        where conrelid = 'public.case_vulnerability_marker'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%marker_code%'
    loop
        execute format('alter table public.case_vulnerability_marker drop constraint %I', c);
    end loop;
end $$;
alter table public.case_vulnerability_marker add constraint case_vulnerability_marker_marker_code_check check (marker_code in (
    'pregnant_or_lactating', 'unaccompanied_child', 'separated_child', 'victim_of_violence', 'medical_condition', 'disability',
    'lgbtiq', 'indigenous_language_speaker', 'stateless_or_at_risk', 'survivor_torture_trauma', 'international_protection_need',
    'older_person_at_risk', 'other_vulnerability', 'cuidador_monoparental', 'cuidados_paliativos'
));

-- ---------------------------------------------------------------- 6. Fotografía de identificación visual: compuerta (Ethos E-01, v1.4)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('dossier-photos', 'dossier-photos', false, 262144, array['image/webp'])
on conflict (id) do update
    set public = false, file_size_limit = 262144, allowed_mime_types = array['image/webp'];

-- Subir solo a `<organización>/<caso>/photo-<id>.webp`, con la autorización de fotografía registrada y el permiso de abrir
-- expedientes. No hay política de lectura, de cambio ni de borrado: lo subido no se lee ni se cambia desde la API (la lectura con
-- URL firmada de 60 s y registro en la auditoría es la fase posterior).
drop policy if exists dossier_photos_insert on storage.objects;
create policy dossier_photos_insert on storage.objects
    for insert to authenticated
    with check (
        bucket_id = 'dossier-photos'
        and storage.objects.name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/photo-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.webp$'
        and (storage.foldername(storage.objects.name))[1] = public.current_organization_id()::text
        and public.has_capability('open_cases')
        and exists (
            select 1 from public."case" c
            where c.id::text = (storage.foldername(storage.objects.name))[2]
              and c.organization_id = public.current_organization_id()
              and c.photo_consent is true
        )
    );

-- Pide la ruta donde subir la fotografía de un caso. Sin la autorización firmada en físico: BV402.
create or replace function public.fn_request_dossier_photo_upload(p_case_id uuid)
returns text
security definer
set search_path = public, auth
language plpgsql as $$
declare
    v_org uuid := public.current_organization_id();
    v_case record;
begin
    if auth.uid() is null or v_org is null or not public.has_capability('open_cases') then
        raise exception 'Acceso denegado: se requiere el permiso de abrir expedientes (por omisión, ingreso y dirección).' using errcode = 'BV113';
    end if;
    perform public.fn_assert_same_org('case', p_case_id);
    select c.photo_consent, p.is_anonymized into v_case
    from public."case" c join public.person p on p.id = c.titular_person_id
    where c.id = p_case_id;
    if v_case.is_anonymized then
        raise exception 'Operación no permitida: una persona anonimizada no admite este dato (ADR-0001).' using errcode = 'BV507';
    end if;
    if v_case.photo_consent is not true then
        raise exception 'Falta el consentimiento firmado en físico para la fotografía de identificación visual (Ethos E-01).' using errcode = 'BV402';
    end if;
    return v_org::text || '/' || p_case_id::text || '/photo-' || gen_random_uuid()::text || '.webp';
end;
$$;
revoke execute on function public.fn_request_dossier_photo_upload(uuid) from public, anon;
grant execute on function public.fn_request_dossier_photo_upload(uuid) to authenticated;

-- ---------------------------------------------------------------- 7. El alta recibe lo nuevo (una sola transacción)
do $$
declare
    f record;
begin
    for f in
        select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname in ('fn_create_case_with_person', 'fn_create_case_with_person_impl')
    loop
        execute format('drop function %s', f.sig);
    end loop;
end $$;

CREATE OR REPLACE FUNCTION public.fn_create_case_with_person_impl(p_given_name text, p_paternal_family_name text, p_maternal_family_name text, p_preferred_name text, p_birth_date date, p_birth_date_is_estimated boolean, p_sex_id integer, p_nationality_country_id integer, p_other_nationality text, p_primary_language_item_id uuid, p_other_language text, p_phone_number text, p_intake_window_type text, p_travels_with_family boolean, p_intake_state_id integer, p_intake_municipality_key text, p_intake_channel_id integer, p_entry_route_id integer, p_entry_date_str text, p_assigned_area_id uuid, p_vulnerability_codes text[], p_consents jsonb DEFAULT '[]'::jsonb, p_dates jsonb DEFAULT '[]'::jsonb, p_education_level_item_id uuid DEFAULT NULL::uuid, p_marital_status_item_id uuid DEFAULT NULL::uuid, p_origin_department_item_id uuid DEFAULT NULL::uuid, p_occupation_item_ids uuid[] DEFAULT NULL::uuid[], p_secondary_phone text DEFAULT NULL::text, p_secondary_phone_label text DEFAULT NULL::text, p_identity_documents text[] DEFAULT NULL::text[], p_nationality_iso text DEFAULT NULL::text, p_photo_consent boolean DEFAULT NULL::boolean, p_coexistence_rules boolean DEFAULT NULL::boolean, p_nna_responsibility boolean DEFAULT NULL::boolean)
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
    v_docs text[];
    v_phone2 text := nullif(btrim(coalesce(p_secondary_phone, '')), '');
    v_iso text := nullif(btrim(coalesce(p_nationality_iso, '')), '');
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
        or v_phone2 is not null or v_iso is not null
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
    -- E17 ingreso y expediente: documentos con que se identifica, segundo teléfono y país (ISO). Se validan antes que lo demás.
    if v_iso is not null and v_iso !~ '^[A-Z]{2}$' then
        raise exception 'El país no es válido.' using errcode = 'BV369';
    end if;
    if p_secondary_phone_label is not null and v_phone2 is null then
        raise exception 'La etiqueta del segundo teléfono necesita un número.' using errcode = 'BV368';
    end if;
    if v_phone2 is not null and char_length(v_phone2) > 30 then
        raise exception 'El segundo teléfono no puede pasar de 30 caracteres.' using errcode = 'BV368';
    end if;
    if p_secondary_phone_label is not null and p_secondary_phone_label not in ('familiar', 'whatsapp', 'propio', 'acompanante', 'otro') then
        raise exception 'La etiqueta del segundo teléfono no es válida.' using errcode = 'BV368';
    end if;
    v_docs := public.fn_assert_identity_documents(v_org_id, p_identity_documents);

    v_occ := public.fn_assert_occupation_set(v_org_id, p_occupation_item_ids);

    insert into public.person (
        organization_id, given_name, paternal_family_name, maternal_family_name,
        preferred_name, birth_date, birth_date_is_estimated, sex_id,
        nationality_country_id, other_nationality, primary_language_item_id,
        other_language, phone_number,
        education_level_item_id, marital_status_item_id, origin_department_item_id,
        secondary_phone, secondary_phone_label, identity_documents_presented, nationality_iso
    ) values (
        v_org_id, trim(p_given_name), trim(p_paternal_family_name), nullif(trim(p_maternal_family_name), ''),
        nullif(trim(p_preferred_name), ''), p_birth_date, coalesce(p_birth_date_is_estimated, false), p_sex_id,
        p_nationality_country_id, p_other_nationality, p_primary_language_item_id,
        p_other_language, nullif(trim(p_phone_number), ''),
        p_education_level_item_id, p_marital_status_item_id, p_origin_department_item_id,
        v_phone2, case when v_phone2 is null then null else p_secondary_phone_label end, v_docs, v_iso
    ) returning id into v_person_id;

    perform public.fn_apply_person_occupations(v_person_id, v_org_id, v_occ, null);

    insert into public."case" (
        organization_id, case_number, titular_person_id, intake_state_id,
        intake_municipality_key, intake_channel_id, intake_window_type,
        entry_route_id, entry_date_str, travels_with_family, opened_by,
        assigned_area_id, assigned_user_id,
        photo_consent, coexistence_rules_accepted, nna_responsibility_accepted
    ) values (
        v_org_id, public.fn_generate_case_number(v_org_id), v_person_id, p_intake_state_id,
        p_intake_municipality_key, p_intake_channel_id, p_intake_window_type,
        p_entry_route_id, p_entry_date_str, p_travels_with_family, v_user_id,
        p_assigned_area_id, v_user_id,
        p_photo_consent, p_coexistence_rules, p_nna_responsibility
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

CREATE OR REPLACE FUNCTION public.fn_create_case_with_person(p_given_name text, p_paternal_family_name text, p_maternal_family_name text, p_preferred_name text, p_birth_date date, p_birth_date_is_estimated boolean, p_sex_id integer, p_nationality_country_id integer, p_other_nationality text, p_primary_language_item_id uuid, p_other_language text, p_phone_number text, p_intake_window_type text, p_travels_with_family boolean, p_intake_state_id integer, p_intake_municipality_key text, p_intake_channel_id integer, p_entry_route_id integer, p_entry_date_str text, p_assigned_area_id uuid, p_vulnerability_codes text[], p_consents jsonb DEFAULT '[]'::jsonb, p_dates jsonb DEFAULT '[]'::jsonb, p_education_level_item_id uuid DEFAULT NULL::uuid, p_marital_status_item_id uuid DEFAULT NULL::uuid, p_origin_department_item_id uuid DEFAULT NULL::uuid, p_occupation_item_ids uuid[] DEFAULT NULL::uuid[], p_secondary_phone text DEFAULT NULL::text, p_secondary_phone_label text DEFAULT NULL::text, p_identity_documents text[] DEFAULT NULL::text[], p_nationality_iso text DEFAULT NULL::text, p_photo_consent boolean DEFAULT NULL::boolean, p_coexistence_rules boolean DEFAULT NULL::boolean, p_nna_responsibility boolean DEFAULT NULL::boolean)
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
        p_education_level_item_id, p_marital_status_item_id, p_origin_department_item_id, p_occupation_item_ids,
        p_secondary_phone, p_secondary_phone_label, p_identity_documents, p_nationality_iso,
        p_photo_consent, p_coexistence_rules, p_nna_responsibility
    );
end;
$function$;

do $$
declare
    f record;
begin
    for f in
        select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname in ('fn_create_case_with_person', 'fn_create_case_with_person_impl')
    loop
        execute format('revoke execute on function %s from public, anon', f.sig);
        if f.proname = 'fn_create_case_with_person' then
            execute format('grant execute on function %s to authenticated', f.sig);
        else
            execute format('revoke execute on function %s from authenticated', f.sig);
        end if;
    end loop;
end $$;
