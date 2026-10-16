-- ==============================================================================
-- E15 fase 4 · Papel en la familia (para el orden sugerido de la familia)
--
-- La matriz de Trabajo Social ordena a las personas de una familia así: 1.º madre, 2.º padre o pareja, 3.º hijas e hijos de
-- mayor a menor, 4.º otros. Esa regla necesita saber el **papel** de cada persona en la familia, dato que no existía (la unidad
-- familiar guardaba el consecutivo, no el papel). Decisión del Product Owner (22 oct 2026): hacerlo como se propuso.
--
-- Cómo
--  * Diccionario editable `family_role` (dirección y Trabajo Social), sembrado con madre, padre o pareja, hija o hijo y otro.
--  * `family_member.family_role_item_id`: el papel de la persona en SU familia; vacío = «No registrado» (no se supone).
--  * `fn_set_family_member_role`: se registra dentro de una familia; cambiarlo o quitarlo pide motivo y deja la auditoría.
--  * El orden sugerido se calcula en la interfaz y su aplicación es manual, un expediente a la vez.
--  * El extracto de acceso ARCO incluye el papel. Error con código estable: BV342 (la persona no tiene familia).
--
-- Idempotente: el reinicio de la demo reaplica todas las migraciones.
-- ==============================================================================

alter table public.catalog_item drop constraint if exists catalog_item_catalog_check;
alter table public.catalog_item add constraint catalog_item_catalog_check
    check (catalog in ('language', 'religion', 'specific_need', 'service_line', 'education_level', 'marital_status', 'occupation', 'department', 'family_role'));

insert into public.catalog_item (organization_id, catalog, key, label_es, is_system, sort_order)
select o.id, 'family_role', v.key, v.label_es, false, v.sort_order
from public.organization o
cross join (values
    ('mother', 'Madre', 1),
    ('father_partner', 'Padre o pareja', 2),
    ('child', 'Hija o hijo', 3),
    ('other', 'Otro', 4)
) as v(key, label_es, sort_order)
on conflict (organization_id, catalog, key) do nothing;

alter table public.family_member
    add column if not exists family_role_item_id uuid references public.catalog_item(id) on delete restrict;

create or replace function public.fn_set_family_member_role(p_case_id uuid, p_item_id uuid, p_reason text default null)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_case record;
    v_member record;
begin
    if v_user is null or public.current_organization_id() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: registrar el papel en la familia exige un rol que opere expedientes (E15).' using errcode = 'BV120';
    end if;
    perform public.fn_assert_same_org('case', p_case_id);
    select c.organization_id, p.is_anonymized into v_case
    from public."case" c join public.person p on p.id = c.titular_person_id
    where c.id = p_case_id;
    if v_case.is_anonymized then
        raise exception 'Operación no permitida: una persona anonimizada no admite este dato (ADR-0001).' using errcode = 'BV507';
    end if;

    select * into v_member from public.family_member where case_id = p_case_id and valid_to is null;
    if v_member.id is null then
        raise exception 'Primero asigna a la persona a una familia: el papel se registra dentro de una familia.' using errcode = 'BV342';
    end if;
    if p_item_id is not null then
        perform public.fn_assert_catalog_item(v_case.organization_id, 'family_role', p_item_id);
    end if;
    if p_item_id is not distinct from v_member.family_role_item_id then
        return;
    end if;
    if v_member.family_role_item_id is not null and (p_reason is null or btrim(p_reason) = '') then
        raise exception 'El motivo es obligatorio al cambiar o quitar un dato ya registrado (Ethos C8).' using errcode = 'BV304';
    end if;

    update public.family_member set family_role_item_id = p_item_id where id = v_member.id;

    if v_member.family_role_item_id is not null then
        insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
        values (v_case.organization_id, v_user, 'RECTIFICATION', 'family_member', v_member.id,
                jsonb_build_object('changed_fields', jsonb_build_array('family_role_item_id'), 'reason', btrim(p_reason)));
    end if;
end;
$$;
revoke execute on function public.fn_set_family_member_role(uuid, uuid, text) from public, anon;
grant execute on function public.fn_set_family_member_role(uuid, uuid, text) to authenticated;

-- Extracto de acceso ARCO: se redefine a partir de la definición vigente (20261023000001); solo se agrega el papel en la familia.

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
        'family_role', (select ci.label_es from public.catalog_item ci where ci.id = m.family_role_item_id),   -- E15 f4
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
        'specific_needs', v_needs,
        'social_answers', (
            select coalesce(jsonb_agg(jsonb_build_object(
                'case_number', c.case_number,
                'question', q.label_es,
                'choice', a.choice,
                'number', a.number_value,
                'text', a.text_value,
                'date', a.date_value,
                'date_precision', a.date_precision,
                'detail', a.detail,
                'registered_at', a.created_at,
                'closed_at', a.valid_to
            ) order by c.case_number, q.sort_order, a.created_at), '[]'::jsonb)
            from public.social_answer a
            join public.social_question q on q.id = a.question_id
            join public.case c on c.id = a.case_id
            where c.titular_person_id = p_person_id
        )
    );

    -- Auditoría obligatoria de emisión: la persona se identifica por record_id, no por su nombre
    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_person.organization_id, v_user_id, 'ARCO_ACCESS_EXTRACT_ISSUED', 'person', p_person_id,
            jsonb_build_object('emitted_at', now()));

    return v_result;
end;
$function$;
