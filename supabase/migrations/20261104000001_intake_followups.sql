-- ==============================================================================
-- Ciclo «Ingreso y expediente», parte 2 (decisiones del Product Owner del 02 nov 2026)
--
--  1. Los indicadores de nacionalidad pasan a agrupar por país ISO 3166-1 (`person.nationality_iso`). Los registros anteriores se
--     completan SOLO donde el dato es inequívoco: el id del estándar de Honduras (93) y Guatemala (86), y los seis nombres de país
--     que el alta anterior ofrecía. «Otro» y cualquier texto distinto se dejan como estaban (no se adivina un país).
--  2. Corregir lo registrado de una persona ya creada: `fn_rectify_person_contact` (segundo teléfono y etiqueta, documentos con que
--     se identifica y país). Cambiar un valor ya registrado pide motivo (Ethos C8) y deja auditoría; agregar un teléfono o un país
--     exige consentimiento sensible vigente (D-14).
--  3. Escenario 3 del contrato (fotografía sin autorización): una función que aborta con error revierte todo lo que hizo, incluido
--     el registro del intento. `fn_request_dossier_photo_upload` ahora RESPONDE «denegado» con el código `BV402` (y deja la acción
--     `ACCESS_DENIED` en la auditoría) en lugar de abortar. La subida real sigue bloqueada por la política del almacenamiento, que
--     no depende de esta función. Errores de permiso (BV113) y de persona anonimizada (BV507) siguen abortando.
-- ==============================================================================

-- ---------------------------------------------------------------- 1. Indicadores por país ISO
-- Completar el ISO de los registros anteriores solo donde es inequívoco (columna nueva: no se pisa ningún valor)
update public.person set nationality_iso = 'HN' where nationality_iso is null and nationality_country_id = 93 and not is_anonymized;
update public.person set nationality_iso = 'GT' where nationality_iso is null and nationality_country_id = 86 and not is_anonymized;
update public.person p set nationality_iso = v.iso
from (values ('Honduras', 'HN'), ('Guatemala', 'GT'), ('El Salvador', 'SV'), ('Venezuela', 'VE'), ('Haití', 'HT'), ('Cuba', 'CU'),
             ('Colombia', 'CO'), ('México', 'MX')) as v(name, iso)
where p.nationality_iso is null and not p.is_anonymized and btrim(p.other_nationality) = v.name;

-- fn_metric_rows (agrupa por ISO)
create or replace function public.fn_metric_rows(p_org uuid, p_from date, p_to date)
returns table (metric text, bucket text, n int, val numeric, ord int, by_freq boolean)
language sql
stable
security definer
set search_path = public
as $$
    with elig as (
        select c.id as case_id, c.opened_at, c.intake_window_type, c.intake_date, p.sex_id,
               coalesce(p.nationality_iso, nullif(trim(p.other_nationality), ''), 'Sin dato') as nationality,
               extract(year from age(c.intake_date, p.birth_date))::int as age_at_intake
        from public."case" c
        join public.person p on p.id = c.titular_person_id
        where c.organization_id = p_org
          and not exists (
              select 1 from public.consent k
              where k.person_id = p.id
                and k.consent_type = 'secondary_use_research'
                and k.status = 'opposed'
          )
    ),
    base as (
        select * from elig
        where (p_from is null or intake_date >= p_from)
          and (p_to is null or intake_date <= p_to)
    ),
    cur as (
        select cs.case_id, ax.code as axis, sv.label_es, sv.sort_order
        from public.case_status cs
        join public.status_axis ax on ax.id = cs.axis_id
        join public.status_value sv on sv.id = cs.value_id
        where cs.valid_to is null and cs.organization_id = p_org
    ),
    milestone as (
        select cs.case_id, sv.code as stage_code, min(cs.valid_from) as t
        from public.case_status cs
        join public.status_axis ax on ax.id = cs.axis_id and ax.code = 'case_stage'
        join public.status_value sv on sv.id = cs.value_id and sv.code in ('case_plan', 'closure')
        where cs.organization_id = p_org
        group by cs.case_id, sv.code
    )
    select 'total_cases'::text, 'all'::text, count(*)::int, count(*)::numeric, 0, true from base
    union all
    select 'intake_window_type', b.intake_window_type, count(*)::int, count(*)::numeric, 0, false from base b group by 2
    union all
    select 'intake_month', to_char(b.intake_date, 'YYYY-MM'), count(*)::int, count(*)::numeric, 0, false from base b group by 2
    union all
    select 'egress_month', to_char(m.t, 'YYYY-MM'), count(*)::int, count(*)::numeric, 0, false
    from milestone m
    join elig e on e.case_id = m.case_id
    where m.stage_code = 'closure'
      and (p_from is null or m.t::date >= p_from)
      and (p_to is null or m.t::date <= p_to)
    group by 2
    union all
    select 'sex', coalesce(b.sex_id::text, 'sin_dato'), count(*)::int, count(*)::numeric, 0, false from base b group by 2
    union all
    -- E14 f5: sin grupos configurados el indicador dice «sin dato»; no se suponen rangos
    select 'age_band', coalesce(ab.label_es, 'sin_dato'), count(*)::int, count(*)::numeric, coalesce(min(ab.sort_order), 99), false
    from base b
    left join lateral (
        select a.label_es, a.sort_order from public.age_band a
        where a.organization_id = p_org and a.valid_to is null and a.min_age <= b.age_at_intake
        order by a.min_age desc limit 1
    ) ab on true
    group by 2
    union all
    select 'nationality', b.nationality, count(*)::int, count(*)::numeric, 0, true from base b group by 2
    union all
    select 'vulnerability', mk.marker_code, count(distinct mk.case_id)::int, count(distinct mk.case_id)::numeric, 0, true
    from public.case_vulnerability_marker mk
    join base b on b.case_id = mk.case_id
    where mk.removed_at is null group by 2
    union all
    select 'case_stage', cur.label_es, count(*)::int, count(*)::numeric, min(cur.sort_order), false
    from base b join cur on cur.case_id = b.case_id and cur.axis = 'case_stage' group by cur.label_es
    union all
    select 'legal_status', cur.label_es, count(*)::int, count(*)::numeric, min(cur.sort_order), false
    from base b join cur on cur.case_id = b.case_id and cur.axis = 'legal_status' group by cur.label_es
    union all
    select 'engagement_status', cur.label_es, count(*)::int, count(*)::numeric, min(cur.sort_order), false
    from base b join cur on cur.case_id = b.case_id and cur.axis = 'engagement_status' group by cur.label_es
    union all
    select 'shelter_status', cur.label_es, count(*)::int, count(*)::numeric, min(cur.sort_order), false
    from base b join cur on cur.case_id = b.case_id and cur.axis = 'shelter_status' group by cur.label_es
    union all
    -- Duraciones: promedio en días sobre los casos de la cohorte que ya alcanzaron el hito
    select 'duration', 'to_case_plan', count(*)::int,
           avg(extract(epoch from (m.t - b.opened_at)) / 86400.0), 0, false
    from base b join milestone m on m.case_id = b.case_id and m.stage_code = 'case_plan'
    union all
    select 'duration', 'to_closure', count(*)::int,
           avg(extract(epoch from (m.t - b.opened_at)) / 86400.0), 1, false
    from base b join milestone m on m.case_id = b.case_id and m.stage_code = 'closure'
$$;


-- ---------------------------------------------------------------- 2. Corregir contacto, documentos y país
create or replace function public.fn_rectify_person_contact(
    p_person_id uuid,
    p_secondary_phone text,
    p_secondary_phone_label text,
    p_identity_documents text[],
    p_nationality_iso text,
    p_nationality_country_id integer,
    p_other_nationality text,
    p_reason text default null
)
returns void
security definer
set search_path = public, auth
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_person public.person%rowtype;
    v_phone2 text := nullif(btrim(coalesce(p_secondary_phone, '')), '');
    v_label text := nullif(btrim(coalesce(p_secondary_phone_label, '')), '');
    v_iso text := nullif(btrim(coalesce(p_nationality_iso, '')), '');
    v_name text := nullif(btrim(coalesce(p_other_nationality, '')), '');
    v_docs text[];
    v_changed text[] := '{}';
    v_had_value boolean := false;
begin
    if v_user is null or public.current_organization_id() is null or not public.has_capability('rectify_person_data') then
        raise exception 'Acceso denegado: la rectificación de datos de una persona requiere ese permiso (por omisión, dirección e ingreso).' using errcode = 'BV119';
    end if;
    perform public.fn_assert_same_org('person', p_person_id);
    select * into v_person from public.person where id = p_person_id;
    if v_person.is_anonymized then
        raise exception 'Operación no permitida: una persona anonimizada no admite este dato (ADR-0001).' using errcode = 'BV507';
    end if;

    -- Validaciones de forma (las mismas del alta)
    if v_iso is not null and v_iso !~ '^[A-Z]{2}$' then
        raise exception 'El país no es válido.' using errcode = 'BV369';
    end if;
    if v_iso is not null and (p_nationality_country_id is distinct from (case v_iso when 'HN' then 93 when 'GT' then 86 else 1 end)
                              or v_name is null or char_length(v_name) > 80) then
        raise exception 'El país no es válido.' using errcode = 'BV369';
    end if;
    if v_iso is null and (p_nationality_country_id is not null or v_name is not null) then
        raise exception 'El país no es válido.' using errcode = 'BV369';
    end if;
    if v_label is not null and v_phone2 is null then
        raise exception 'La etiqueta del segundo teléfono necesita un número.' using errcode = 'BV368';
    end if;
    if v_phone2 is not null and char_length(v_phone2) > 30 then
        raise exception 'El segundo teléfono no puede pasar de 30 caracteres.' using errcode = 'BV368';
    end if;
    if v_label is not null and v_label not in ('familiar', 'whatsapp', 'propio', 'acompanante', 'otro') then
        raise exception 'La etiqueta del segundo teléfono no es válida.' using errcode = 'BV368';
    end if;
    v_docs := public.fn_assert_identity_documents(v_person.organization_id, p_identity_documents);

    -- Qué cambia
    if v_phone2 is distinct from v_person.secondary_phone then v_changed := array_append(v_changed, 'secondary_phone'); end if;
    if v_label is distinct from v_person.secondary_phone_label then v_changed := array_append(v_changed, 'secondary_phone_label'); end if;
    if v_docs is distinct from v_person.identity_documents_presented then v_changed := array_append(v_changed, 'identity_documents_presented'); end if;
    if v_iso is distinct from v_person.nationality_iso then v_changed := array_append(v_changed, 'nationality_iso'); end if;
    if cardinality(v_changed) = 0 then
        return;
    end if;

    -- D-14: agregar o cambiar un teléfono o un país exige consentimiento sensible vigente (quitarlos no)
    if ((v_phone2 is not null and v_phone2 is distinct from v_person.secondary_phone) or (v_iso is not null and v_iso is distinct from v_person.nationality_iso))
       and not public.fn_person_has_sensitive_consent(p_person_id) then
        raise exception 'Control P-06: el teléfono y el país son datos sensibles y exigen consentimiento sensible.' using errcode = 'BV402';
    end if;

    -- Ethos C8: cambiar o quitar algo ya registrado pide motivo; registrarlo por primera vez, no
    v_had_value := ('secondary_phone' = any (v_changed) and v_person.secondary_phone is not null)
                or ('secondary_phone_label' = any (v_changed) and v_person.secondary_phone_label is not null)
                or ('identity_documents_presented' = any (v_changed) and v_person.identity_documents_presented is not null)
                or ('nationality_iso' = any (v_changed) and v_person.nationality_iso is not null);
    if v_had_value and (p_reason is null or btrim(p_reason) = '') then
        raise exception 'El motivo es obligatorio al cambiar o quitar un dato ya registrado (Ethos C8).' using errcode = 'BV304';
    end if;

    update public.person
       set secondary_phone = v_phone2, secondary_phone_label = v_label, identity_documents_presented = v_docs,
           nationality_iso = v_iso, nationality_country_id = p_nationality_country_id, other_nationality = v_name, updated_at = now()
     where id = p_person_id;

    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_person.organization_id, v_user, 'RECTIFICATION', 'person', p_person_id,
            jsonb_build_object('changed_fields', to_jsonb(v_changed), 'reason', nullif(btrim(coalesce(p_reason, '')), '')));
end;
$$;
revoke execute on function public.fn_rectify_person_contact(uuid, text, text, text[], text, integer, text, text) from public, anon;
grant execute on function public.fn_rectify_person_contact(uuid, text, text, text[], text, integer, text, text) to authenticated;

-- ---------------------------------------------------------------- 3. Fotografía sin autorización: denegar y dejar constancia
alter table public.audit_event drop constraint if exists audit_event_action_check;
alter table public.audit_event add constraint audit_event_action_check check (action in (
    'INSERT', 'UPDATE', 'DELETE', 'LOGIN', 'EXPORT', 'STATUS_CHANGE',
    'CLARIFICATION', 'SHARE', 'ACKNOWLEDGE',
    'RECTIFICATION', 'ANONYMIZATION', 'OPPOSITION',
    'CONSENT_GRANTED', 'CONSENT_REVOKED', 'ARCO_ACCESS_EXTRACT_ISSUED',
    'EVIDENCE_ACCESS', 'READ_CASE', 'ACCESS_DENIED'
));

drop function if exists public.fn_request_dossier_photo_upload(uuid);
create or replace function public.fn_request_dossier_photo_upload(p_case_id uuid)
returns jsonb
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
        -- No se aborta: abortar revertiría este registro. La subida real la bloquea además la política del almacenamiento.
        insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
        values (v_org, auth.uid(), 'ACCESS_DENIED', 'case', p_case_id, jsonb_build_object('code', 'BV402', 'attempt', 'photo_upload'));
        return jsonb_build_object('ok', false, 'code', 'BV402');
    end if;
    return jsonb_build_object('ok', true, 'path', v_org::text || '/' || p_case_id::text || '/photo-' || gen_random_uuid()::text || '.webp');
end;
$$;
revoke execute on function public.fn_request_dossier_photo_upload(uuid) from public, anon;
grant execute on function public.fn_request_dossier_photo_upload(uuid) to authenticated;
