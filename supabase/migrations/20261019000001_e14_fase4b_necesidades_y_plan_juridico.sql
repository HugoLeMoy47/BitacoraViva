-- ==============================================================================
-- E14 fase 4b · Necesidades específicas (casillas) y plan al ingreso
--
-- Decisiones del Product Owner (17 oct 2026), a partir de los desplegables de la hoja de casos de CAFEMIN:
--  * «Necesidades específicas» es una lista de **casillas** con lo que se marca, de un diccionario que editan dirección y
--    Trabajo Social; se busca una mejor integración con su uso más adelante (no se vincula automáticamente a los marcadores).
--    Son datos sensibles (D-14): solo con consentimiento sensible vigente (`BV408`), salvo «La persona no quiso responder»,
--    que no se combina con otras (`BV334`).
--  * PLAN es el **plan al ingreso** y JURÍDICO es la **situación actual**: comparten diccionario. El plan al ingreso usa los
--    valores del eje jurídico (`legal_status`); la situación actual sigue siendo ese eje con su historial.
--  * Se agregan al eje jurídico: Residente permanente, Tarjeta de visitante INM/PFNNA, Registro por vínculo familiar, Retorno
--    voluntario y Plan indefinido. «Solicitud de refugio» ya existe como «Solicitante de asilo»; «CURP actualizadas» y
--    «Población mexicana» se omiten.
--
-- Cómo
--  * `catalog_item` admite el diccionario `specific_need` (sembrado con los diez valores de la hoja + «no quiso responder»).
--  * `case_need`: una fila por necesidad marcada; quitarla la CIERRA con motivo, nada se borra. Se escribe por
--    `fn_set_case_needs` (roles que operan expedientes), que recibe el conjunto completo de casillas marcadas.
--  * `case.intake_plan_value_id` (valor del eje jurídico) por `fn_set_case_intake_plan`; cambiarlo o quitarlo exige motivo.
--  * Al anonimizar se cierran las necesidades; el extracto de acceso ARCO las incluye.
--  * Errores con código estable: BV334.
--
-- Idempotente: el reinicio de la demo reaplica todas las migraciones.
-- ==============================================================================

-- ---------------------------------------------------------------- 1. Diccionario de necesidades
alter table public.catalog_item drop constraint if exists catalog_item_catalog_check;
alter table public.catalog_item add constraint catalog_item_catalog_check
    check (catalog in ('language', 'religion', 'specific_need'));

insert into public.catalog_item (organization_id, catalog, key, label_es, legacy_code, is_system, sort_order)
select o.id, 'specific_need', v.key, v.label_es, v.legacy_code, v.is_system, v.sort_order
from public.organization o
cross join (values
    ('caregiver_alone', 'Cuidador sola(o)', 'CUIDADOR SOLA (O)', false, 1),
    ('disability', 'Discapacidad', 'DISCAPACIDAD', false, 2),
    ('pregnancy', 'Embarazo', 'EMBARAZO', false, 3),
    ('palliative_care', 'Cuidados paliativos', 'CUIDADOS PALIATIVOS', false, 4),
    ('unaccompanied_minor', 'NNA no acompañadxs', 'NNA NO ACOMPAÑADXS', false, 5),
    ('older_adult', 'Personas adultas mayores', 'PERSONAS ADULTAS MAYORES', false, 6),
    ('humanitarian_care', 'Atención humanitaria', 'ATENCIÓN HUMANITARIA', false, 7),
    ('integral_care_plan', 'Plan de atención integral', 'PLAN DE ATEN. INTEGRAL', false, 8),
    ('non_binary', 'No binario (LGBTQM+)', 'NO BINARIO (LGBTQM+)', false, 9),
    ('neurodivergence', 'Neurodivergencia', 'NEURODIVERGENCIA', false, 10),
    ('no_response', 'La persona no quiso responder', null, true, 99)
) as v(key, label_es, legacy_code, is_system, sort_order)
on conflict (organization_id, catalog, key) do nothing;

-- ---------------------------------------------------------------- 2. Las necesidades marcadas de cada persona (por su expediente)
create table if not exists public.case_need (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    case_id uuid not null references public."case"(id) on delete restrict,
    catalog_item_id uuid not null references public.catalog_item(id) on delete restrict,
    created_at timestamptz not null default now(),
    created_by uuid not null references public.user_profile(id),
    valid_to timestamptz,
    closed_by uuid references public.user_profile(id),
    change_reason text
);
create unique index if not exists uq_case_need_current on public.case_need (case_id, catalog_item_id) where valid_to is null;
create index if not exists idx_case_need_case on public.case_need (case_id);

alter table public.case_need enable row level security;
revoke all on public.case_need from anon;
revoke insert, update, delete on public.case_need from authenticated;
drop policy if exists tenant_operational_select on public.case_need;
create policy tenant_operational_select on public.case_need for select to authenticated
    using (organization_id = public.current_organization_id() and public.has_operational_role());
drop trigger if exists trg_audit_case_need on public.case_need;
create trigger trg_audit_case_need after insert or update on public.case_need
for each row execute function public.fn_audit_trigger_fields();

-- Recibe el conjunto COMPLETO de casillas marcadas; agrega las nuevas y cierra (con motivo) las desmarcadas
create or replace function public.fn_set_case_needs(p_case_id uuid, p_item_ids uuid[], p_reason text default null)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_case record;
    v_ids uuid[];
    v_id uuid;
    v_has_no_response boolean := false;
    v_current uuid[];
    v_added uuid[];
    v_removed uuid[];
begin
    if v_user is null or public.current_organization_id() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: marcar necesidades exige un rol que opere expedientes (E14).' using errcode = 'BV120';
    end if;
    perform public.fn_assert_same_org('case', p_case_id);

    select c.organization_id, c.titular_person_id, p.is_anonymized into v_case
    from public."case" c join public.person p on p.id = c.titular_person_id
    where c.id = p_case_id;
    if v_case.is_anonymized then
        raise exception 'Operación no permitida: una persona anonimizada no admite este dato (ADR-0001).' using errcode = 'BV507';
    end if;

    -- Conjunto sin repetidos; cada valor debe existir, ser de esta organización y de este diccionario, y estar activo
    select coalesce(array_agg(distinct x), '{}'::uuid[]) into v_ids from unnest(coalesce(p_item_ids, '{}'::uuid[])) as t(x);
    if exists (select 1 from unnest(coalesce(p_item_ids, '{}'::uuid[])) as t(x) where x is null) then
        raise exception 'Ese valor no está disponible en el diccionario.' using errcode = 'BV220';
    end if;
    foreach v_id in array v_ids loop
        perform public.fn_assert_catalog_item(v_case.organization_id, 'specific_need', v_id);
        if public.fn_catalog_item_is_no_response(v_id) then
            v_has_no_response := true;
        end if;
    end loop;
    if v_has_no_response and array_length(v_ids, 1) > 1 then
        raise exception '«La persona no quiso responder» no se combina con otras necesidades.' using errcode = 'BV334';
    end if;

    select coalesce(array_agg(catalog_item_id), '{}'::uuid[]) into v_current
    from public.case_need where case_id = p_case_id and valid_to is null;
    select coalesce(array_agg(x), '{}'::uuid[]) into v_added from unnest(v_ids) as t(x) where x <> all (v_current);
    select coalesce(array_agg(x), '{}'::uuid[]) into v_removed from unnest(v_current) as t(x) where x <> all (v_ids);

    -- Marcar una necesidad es un dato sensible (D-14); «no quiso responder» y quitar no lo son
    if exists (select 1 from unnest(v_added) as t(x) where not public.fn_catalog_item_is_no_response(x))
       and not public.fn_person_has_sensitive_consent(v_case.titular_person_id) then
        raise exception 'Control P-06: las necesidades específicas son datos sensibles y exigen consentimiento sensible vigente (D-14).' using errcode = 'BV408';
    end if;
    if coalesce(array_length(v_added, 1), 0) = 0 and coalesce(array_length(v_removed, 1), 0) = 0 then
        return;
    end if;
    if coalesce(array_length(v_removed, 1), 0) > 0 and (p_reason is null or btrim(p_reason) = '') then
        raise exception 'El motivo es obligatorio al quitar una necesidad ya marcada (Ethos C8).' using errcode = 'BV304';
    end if;

    if coalesce(array_length(v_removed, 1), 0) > 0 then
        update public.case_need set valid_to = now(), closed_by = v_user, change_reason = btrim(p_reason)
        where case_id = p_case_id and valid_to is null and catalog_item_id = any (v_removed);
    end if;
    foreach v_id in array v_added loop
        insert into public.case_need (organization_id, case_id, catalog_item_id, created_by)
        values (v_case.organization_id, p_case_id, v_id, v_user);
    end loop;
end;
$$;
revoke execute on function public.fn_set_case_needs(uuid, uuid[], text) from public, anon;
grant execute on function public.fn_set_case_needs(uuid, uuid[], text) to authenticated;

-- ---------------------------------------------------------------- 3. Plan al ingreso (valor del eje jurídico)
alter table public."case"
    add column if not exists intake_plan_value_id uuid references public.status_value(id) on delete restrict;

create or replace function public.fn_set_case_intake_plan(p_case_id uuid, p_value_id uuid, p_reason text default null)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_case record;
begin
    if v_user is null or public.current_organization_id() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: registrar el plan al ingreso exige un rol que opere expedientes (E14).' using errcode = 'BV120';
    end if;
    perform public.fn_assert_same_org('case', p_case_id);
    select * into v_case from public."case" where id = p_case_id;

    if p_value_id is not null and not exists (
        select 1 from public.status_value sv join public.status_axis ax on ax.id = sv.axis_id
        where sv.id = p_value_id and sv.organization_id = v_case.organization_id and ax.code = 'legal_status'
    ) then
        raise exception 'Ese valor no está disponible en el diccionario.' using errcode = 'BV220';
    end if;
    if p_value_id is not distinct from v_case.intake_plan_value_id then
        return;
    end if;
    if v_case.intake_plan_value_id is not null and (p_reason is null or btrim(p_reason) = '') then
        raise exception 'El motivo es obligatorio al cambiar o quitar un dato ya registrado (Ethos C8).' using errcode = 'BV304';
    end if;

    update public."case" set intake_plan_value_id = p_value_id where id = p_case_id;

    if v_case.intake_plan_value_id is not null then
        insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
        values (v_case.organization_id, v_user, 'RECTIFICATION', 'case', p_case_id,
                jsonb_build_object('changed_fields', jsonb_build_array('intake_plan_value_id'), 'reason', btrim(p_reason)));
    end if;
end;
$$;
revoke execute on function public.fn_set_case_intake_plan(uuid, uuid, text) from public, anon;
grant execute on function public.fn_set_case_intake_plan(uuid, uuid, text) to authenticated;

-- ---------------------------------------------------------------- 4. Valores nuevos del eje jurídico
-- Plan al ingreso y situación actual comparten diccionario. «Solicitud de refugio» ya existe (solicitante de asilo).
insert into public.status_value (axis_id, organization_id, code, label_es, sort_order, is_system)
select ax.id, ax.organization_id, v.code, v.label_es, v.sort_order, false
from public.status_axis ax
cross join (values
    ('permanent_resident', 'Residente permanente', 10),
    ('visitor_card', 'Tarjeta de visitante INM/PFNNA', 11),
    ('family_link_registration', 'Registro por vínculo familiar', 12),
    ('voluntary_return', 'Retorno voluntario', 13),
    ('indefinite_plan', 'Plan indefinido', 14)
) as v(code, label_es, sort_order)
where ax.code = 'legal_status'
on conflict (axis_id, code) do nothing;

-- ---------------------------------------------------------------- 5. Anonimización y extracto de acceso ARCO
-- Se redefinen a partir de la definición vigente (20261018000001); solo se agregan los pasos marcados «E14 f4b».

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
