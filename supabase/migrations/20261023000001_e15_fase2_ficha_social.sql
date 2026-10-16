-- ==============================================================================
-- E15 fase 2 · Ficha social con preguntas configurables
--
-- Contexto: la matriz de Trabajo Social trae preguntas de contexto migratorio y de situaciones sensibles que crecen y
-- cambian. Decisión del Product Owner (22 oct 2026): **probar el modelo de preguntas configurables**; las narrativas
-- sensibles van a la bitácora (ver `campos-narrativos-en-bitacora.md`); «¿cómo salió?» y «punto de ingreso» son texto corto;
-- embarazo, salud y detención son **informativos y el marcador manda**; **violencias queda pospuesto** (no se siembra).
--
-- Cómo
--  * `social_question`: la pregunta (clave estable, texto, sección, tipo de respuesta, si lleva detalle, si es sensible).
--    La administran dirección y Trabajo Social (`can_manage_catalogs()`) desde «Diccionarios», sin migración. Una pregunta
--    ya creada no cambia de tipo ni de clave ni deja de ser sensible (`BV341`); puede pasar a sensible y se puede retirar.
--  * `social_answer`: una respuesta vigente por pregunta y expediente; cambiarla o quitarla la CIERRA con motivo y abre
--    la nueva (nada se sobrescribe). Tipos: sí / no / no quiso responder (con detalle opcional), número, texto corto
--    (≤ 120) y fecha con precisión día/mes/año. Se escribe por `fn_set_social_answers` (varias respuestas por operación).
--  * Sensible = consentimiento sensible vigente (`BV408`); «no quiso responder» no es un dato y se registra sin él.
--  * Se siembran las preguntas del contexto migratorio y de situaciones sensibles de la matriz (sin violencias).
--  * Anonimización: las respuestas se cierran y su texto y detalle se suprimen; el extracto ARCO las incluye.
--  * Errores con código estable: BV340 (pregunta o respuesta no válida) y BV341 (cambio no permitido de una pregunta).
--
-- Idempotente: el reinicio de la demo reaplica todas las migraciones.
-- ==============================================================================

-- ---------------------------------------------------------------- 1. Preguntas
create table if not exists public.social_question (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    key text not null,
    label_es text not null,
    section text not null check (section in ('migration', 'sensitive')),
    answer_type text not null check (answer_type in ('yes_no', 'number', 'text', 'date')),
    has_detail boolean not null default false,
    is_sensitive boolean not null default false,
    is_active boolean not null default true,
    sort_order integer not null default 0,
    created_at timestamptz not null default now(),
    unique (organization_id, key),
    check (not has_detail or answer_type = 'yes_no')
);

alter table public.social_question enable row level security;
revoke all on public.social_question from anon;
revoke delete on public.social_question from authenticated;
drop policy if exists tenant_operational_select on public.social_question;
create policy tenant_operational_select on public.social_question for select to authenticated
    using (organization_id = public.current_organization_id() and public.has_operational_role());
drop policy if exists managers_insert on public.social_question;
create policy managers_insert on public.social_question for insert to authenticated
    with check (organization_id = public.current_organization_id() and public.can_manage_catalogs());
drop policy if exists managers_update on public.social_question;
create policy managers_update on public.social_question for update to authenticated
    using (organization_id = public.current_organization_id() and public.can_manage_catalogs())
    with check (organization_id = public.current_organization_id() and public.can_manage_catalogs());

create or replace function public.fn_social_question_guard()
returns trigger
language plpgsql as $$
begin
    if new.key is distinct from old.key or new.answer_type is distinct from old.answer_type
       or new.organization_id is distinct from old.organization_id or new.has_detail is distinct from old.has_detail
       or (old.is_sensitive and not new.is_sensitive) then
        raise exception 'Una pregunta ya creada no cambia de clave ni de tipo y no deja de ser sensible: crea otra.' using errcode = 'BV341';
    end if;
    return new;
end;
$$;
drop trigger if exists trg_social_question_guard on public.social_question;
create trigger trg_social_question_guard before update on public.social_question
for each row execute function public.fn_social_question_guard();
drop trigger if exists trg_audit_social_question on public.social_question;
create trigger trg_audit_social_question after insert or update on public.social_question
for each row execute function public.fn_audit_trigger_fields();

-- ---------------------------------------------------------------- 2. Respuestas (versionadas)
create table if not exists public.social_answer (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    case_id uuid not null references public."case"(id) on delete restrict,
    question_id uuid not null references public.social_question(id) on delete restrict,
    choice text check (choice in ('yes', 'no', 'no_response')),
    number_value integer,
    text_value text,
    date_value date,
    date_precision text check (date_precision in ('day', 'month', 'year')),
    detail text,
    created_at timestamptz not null default now(),
    created_by uuid not null references public.user_profile(id),
    valid_to timestamptz,
    closed_by uuid references public.user_profile(id),
    change_reason text
);
create unique index if not exists uq_social_answer_current on public.social_answer (case_id, question_id) where valid_to is null;
create index if not exists idx_social_answer_case on public.social_answer (case_id);

alter table public.social_answer enable row level security;
revoke all on public.social_answer from anon;
revoke insert, update, delete on public.social_answer from authenticated;
drop policy if exists tenant_operational_select on public.social_answer;
create policy tenant_operational_select on public.social_answer for select to authenticated
    using (organization_id = public.current_organization_id() and public.has_operational_role());
drop trigger if exists trg_audit_social_answer on public.social_answer;
create trigger trg_audit_social_answer after insert or update on public.social_answer
for each row execute function public.fn_audit_trigger_fields();

-- Recibe una lista de respuestas ({question_key, choice | number | text | date + precision, detail, clear});
-- agrega las nuevas y cierra (con motivo) las que cambian o se quitan.
create or replace function public.fn_set_social_answers(p_case_id uuid, p_answers jsonb, p_reason text default null)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_case record;
    v_item jsonb;
    v_q record;
    v_cur record;
    v_has_sensitive boolean;
    v_clear boolean;
    v_choice text;
    v_num integer;
    v_txt text;
    v_date date;
    v_prec text;
    v_detail text;
    v_same boolean;
    v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
    if v_user is null or public.current_organization_id() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: la ficha social exige un rol que opere expedientes (E15).' using errcode = 'BV120';
    end if;
    perform public.fn_assert_same_org('case', p_case_id);

    select c.organization_id, c.titular_person_id, p.is_anonymized, p.birth_date into v_case
    from public."case" c join public.person p on p.id = c.titular_person_id
    where c.id = p_case_id;
    if v_case.is_anonymized then
        raise exception 'Operación no permitida: una persona anonimizada no admite este dato (ADR-0001).' using errcode = 'BV507';
    end if;

    if jsonb_typeof(coalesce(p_answers, 'null'::jsonb)) is distinct from 'array'
       or jsonb_array_length(p_answers) > 40
       or (select count(distinct x->>'question_key') from jsonb_array_elements(p_answers) x) <> jsonb_array_length(p_answers) then
        raise exception 'Esa pregunta o su respuesta no son válidas.' using errcode = 'BV340';
    end if;

    v_has_sensitive := public.fn_person_has_sensitive_consent(v_case.titular_person_id);

    for v_item in select value from jsonb_array_elements(p_answers) loop
        select * into v_q from public.social_question
        where organization_id = v_case.organization_id and key = (v_item->>'question_key') and is_active;
        if v_q.id is null then
            raise exception 'Esa pregunta no existe o ya no está disponible.' using errcode = 'BV340';
        end if;
        v_clear := coalesce(v_item->>'clear', 'false') = 'true';
        v_choice := null; v_num := null; v_txt := null; v_date := null; v_prec := null; v_detail := null;

        if not v_clear then
            if v_q.answer_type = 'yes_no' then
                v_choice := v_item->>'choice';
                if v_choice is null or v_choice not in ('yes', 'no', 'no_response') then
                    raise exception 'Esa respuesta no corresponde a la pregunta.' using errcode = 'BV340';
                end if;
                v_detail := nullif(btrim(coalesce(v_item->>'detail', '')), '');
                if v_detail is not null then
                    if not v_q.has_detail or v_choice = 'no_response' then
                        raise exception 'Esa pregunta no admite detalle en esa respuesta.' using errcode = 'BV340';
                    end if;
                    if char_length(v_detail) > 120 then
                        raise exception 'El texto es demasiado largo.' using errcode = 'BV321';
                    end if;
                end if;
            elsif v_q.answer_type = 'number' then
                if jsonb_typeof(v_item->'number') is distinct from 'number'
                   or (v_item->>'number')::numeric <> trunc((v_item->>'number')::numeric)
                   or (v_item->>'number')::numeric not between 0 and 999 then
                    raise exception 'Esa respuesta no corresponde a la pregunta.' using errcode = 'BV340';
                end if;
                v_num := (v_item->>'number')::integer;
            elsif v_q.answer_type = 'text' then
                v_txt := nullif(btrim(coalesce(v_item->>'text', '')), '');
                if v_txt is null then
                    raise exception 'Esa respuesta no corresponde a la pregunta.' using errcode = 'BV340';
                end if;
                if char_length(v_txt) > 120 then
                    raise exception 'El texto es demasiado largo.' using errcode = 'BV321';
                end if;
            else
                begin
                    v_date := (v_item->>'date')::date;
                exception when others then
                    raise exception 'Esa fecha no es válida.' using errcode = 'BV325';
                end;
                v_prec := v_item->>'precision';
                -- Misma validación que las fechas del caso: precisión, no futura, no anterior al nacimiento
                v_date := public.fn_assert_case_date_value('nation_entry', v_date, v_prec, v_case.birth_date);
            end if;

            -- Sensible = consentimiento sensible vigente; «no quiso responder» no es un dato
            if v_q.is_sensitive and not v_has_sensitive and not (v_q.answer_type = 'yes_no' and v_choice = 'no_response') then
                raise exception 'Control P-06: esta pregunta es de datos sensibles y exige consentimiento sensible vigente (D-14).' using errcode = 'BV408';
            end if;
        end if;

        select * into v_cur from public.social_answer where case_id = p_case_id and question_id = v_q.id and valid_to is null;

        if v_clear then
            if v_cur.id is null then
                continue;
            end if;
        else
            v_same := v_cur.id is not null and (
                case v_q.answer_type
                    when 'yes_no' then v_cur.choice = v_choice and v_cur.detail is not distinct from v_detail
                    when 'number' then v_cur.number_value = v_num
                    when 'text' then v_cur.text_value = v_txt
                    else v_cur.date_value = v_date and v_cur.date_precision = v_prec end);
            if v_same then
                continue;
            end if;
        end if;

        if v_cur.id is not null then
            if v_reason is null then
                raise exception 'El motivo es obligatorio al cambiar o quitar una respuesta ya registrada (Ethos C8).' using errcode = 'BV304';
            end if;
            update public.social_answer set valid_to = now(), closed_by = v_user, change_reason = v_reason where id = v_cur.id;
        end if;

        if not v_clear then
            insert into public.social_answer (organization_id, case_id, question_id, choice, number_value, text_value, date_value, date_precision, detail, created_by)
            values (v_case.organization_id, p_case_id, v_q.id, v_choice, v_num, v_txt, v_date, v_prec, v_detail, v_user);
        end if;
    end loop;
end;
$$;
revoke execute on function public.fn_set_social_answers(uuid, jsonb, text) from public, anon;
grant execute on function public.fn_set_social_answers(uuid, jsonb, text) to authenticated;

-- ---------------------------------------------------------------- 3. Preguntas de la matriz de Trabajo Social
-- Sin violencias (pospuestas por el Product Owner). Las narrativas van a la bitácora (campos-narrativos-en-bitacora.md).
insert into public.social_question (organization_id, key, label_es, section, answer_type, has_detail, is_sensitive, sort_order)
select o.id, v.key, v.label_es, v.section, v.answer_type, v.has_detail, v.is_sensitive, v.sort_order
from public.organization o
cross join (values
    ('wants_return', '¿Quiere regresar a su país?', 'migration', 'yes_no', false, false, 1),
    ('how_left_country', '¿Cómo salió de su país de origen?', 'migration', 'text', false, false, 2),
    ('transit_countries', 'Países por los que ha transitado desde su salida', 'migration', 'text', false, false, 3),
    ('prior_residence_country', 'Antes de llegar a México, ¿en qué país vivió más de seis meses?', 'migration', 'text', false, false, 4),
    ('first_time_mexico', '¿Es su primera vez en México?', 'migration', 'yes_no', false, false, 5),
    ('times_in_mexico', 'Si no es su primera vez: ¿cuántas veces ha estado en México?', 'migration', 'number', false, false, 6),
    ('deported', 'En alguno de esos ingresos, ¿fue deportado(a)?', 'migration', 'yes_no', false, true, 7),
    ('entry_point', '¿Por qué entidad o punto ingresó a México en esta ocasión?', 'migration', 'text', false, false, 8),
    ('destination_country', '¿A qué país piensa llegar?', 'migration', 'text', false, false, 9),
    ('life_in_danger', '¿Siente que en este momento su vida corre peligro?', 'sensitive', 'yes_no', false, true, 1),
    ('migration_detention', '¿Estuvo en detención migratoria?', 'sensitive', 'yes_no', true, true, 2),
    ('detention_release', 'Fecha de salida de la detención migratoria', 'sensitive', 'date', false, true, 3),
    ('health_condition', '¿Tiene alguna situación de salud?', 'sensitive', 'yes_no', true, true, 4),
    ('pregnancy_suspected', '¿Sospecha de embarazo?', 'sensitive', 'yes_no', false, true, 5),
    ('gestation_weeks', 'Estimación del período de gestación (semanas)', 'sensitive', 'number', false, true, 6),
    ('lactating', '¿Está en período de lactancia al momento del registro?', 'sensitive', 'yes_no', false, true, 7)
) as v(key, label_es, section, answer_type, has_detail, is_sensitive, sort_order)
on conflict (organization_id, key) do nothing;

-- ---------------------------------------------------------------- 4. Anonimización y extracto ARCO
-- Se redefinen a partir de la definición vigente (20261022000001); solo se agregan los pasos marcados «E15 f2».

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

    -- E15 f2: las respuestas de la ficha social se cierran y su texto y detalle se suprimen (pueden identificar)
    update public.social_answer
    set valid_to = coalesce(valid_to, now()),
        closed_by = coalesce(closed_by, v_user_id),
        change_reason = '[SUPRIMIDO - ADR-0001]',
        text_value = null,
        detail = null
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
