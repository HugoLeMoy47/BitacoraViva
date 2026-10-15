-- ==============================================================================
-- E14 fase 5 · Derivados: grupos por edad configurables
--
-- La hoja de casos de CAFEMIN trae «grupo por edad» (obligatorio) calculado por edad y sexo. Aquí se calcula SOLO por edad:
-- el sexo es un dato sensible (D-14) y no debe condicionar un cálculo obligatorio. Edad, mes de cumpleaños y días de
-- estancia son cálculos sobre datos que ya existen y se muestran en la pantalla del caso sin guardarse.
--
-- Cómo
--  * `age_band`: los grupos de la organización (nombre + edad desde la que empieza). Cada grupo termina donde empieza el
--    siguiente y el último queda abierto, así que no puede haber huecos ni traslapes. Se escriben por `fn_set_age_bands`,
--    que reemplaza el conjunto completo: lo anterior se CIERRA con motivo, nada se borra. Lo editan dirección y
--    Trabajo Social (`can_manage_catalogs()`).
--  * Los indicadores (`fn_metric_rows`) agrupan por estos grupos; sin grupos configurados dicen «sin dato».
--  * Se siembran los de la hoja: NNA 0-3, NNA 4-6, NNA 7-11, NNA 12-17, Personas adultas 18-59, Personas adultas mayores 60+
--    (nombres por confirmar con el Product Owner).
--  * Errores con código estable: BV335 (permiso) y BV336 (estructura de los grupos).
--
-- Idempotente: el reinicio de la demo reaplica todas las migraciones.
-- ==============================================================================

create table if not exists public.age_band (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    label_es text not null,
    min_age integer not null check (min_age between 0 and 120),
    sort_order integer not null,
    created_at timestamptz not null default now(),
    created_by uuid references public.user_profile(id),
    valid_to timestamptz,
    closed_by uuid references public.user_profile(id),
    change_reason text
);
create unique index if not exists uq_age_band_current on public.age_band (organization_id, min_age) where valid_to is null;

alter table public.age_band enable row level security;
revoke all on public.age_band from anon;
revoke insert, update, delete on public.age_band from authenticated;
drop policy if exists tenant_select on public.age_band;
create policy tenant_select on public.age_band for select to authenticated
    using (organization_id = public.current_organization_id());
drop trigger if exists trg_audit_age_band on public.age_band;
create trigger trg_audit_age_band after insert or update on public.age_band
for each row execute function public.fn_audit_trigger_fields();

create or replace function public.fn_set_age_bands(p_bands jsonb, p_reason text default null)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_org uuid := public.current_organization_id();
    v_prev int := -1;
    v_labels text[] := '{}';
    v_item jsonb;
    v_label text;
    v_min int;
    v_i int := 0;
begin
    if v_user is null or v_org is null or not public.can_manage_catalogs() then
        raise exception 'Acceso denegado: los grupos por edad los administran dirección y Trabajo Social.' using errcode = 'BV335';
    end if;
    if p_bands is null or jsonb_typeof(p_bands) <> 'array' or jsonb_array_length(p_bands) = 0 or jsonb_array_length(p_bands) > 12 then
        raise exception 'Los grupos por edad deben ser una lista de 1 a 12 grupos.' using errcode = 'BV336';
    end if;

    for v_item in select value from jsonb_array_elements(p_bands) loop
        v_i := v_i + 1;
        v_label := nullif(btrim(coalesce(v_item->>'label', '')), '');
        if v_label is null or coalesce(v_item->>'min_age', '') !~ '^[0-9]{1,3}$' then
            raise exception 'Cada grupo necesita un nombre y la edad desde la que empieza.' using errcode = 'BV336';
        end if;
        v_min := (v_item->>'min_age')::int;
        if v_min > 120 or (v_i = 1 and v_min <> 0) or v_min <= v_prev then
            raise exception 'El primer grupo empieza en 0 años y cada grupo siguiente en una edad mayor que el anterior.' using errcode = 'BV336';
        end if;
        if lower(v_label) = any (v_labels) then
            raise exception 'Dos grupos no pueden llamarse igual.' using errcode = 'BV336';
        end if;
        v_labels := v_labels || lower(v_label);
        v_prev := v_min;
    end loop;

    if exists (select 1 from public.age_band where organization_id = v_org and valid_to is null) then
        if p_reason is null or btrim(p_reason) = '' then
            raise exception 'El motivo es obligatorio al cambiar un dato ya registrado (Ethos C8).' using errcode = 'BV304';
        end if;
        update public.age_band set valid_to = now(), closed_by = v_user, change_reason = btrim(p_reason)
        where organization_id = v_org and valid_to is null;
    end if;

    v_i := 0;
    for v_item in select value from jsonb_array_elements(p_bands) loop
        v_i := v_i + 1;
        insert into public.age_band (organization_id, label_es, min_age, sort_order, created_by)
        values (v_org, btrim(v_item->>'label'), (v_item->>'min_age')::int, v_i, v_user);
    end loop;
end;
$$;
revoke execute on function public.fn_set_age_bands(jsonb, text) from public, anon;
grant execute on function public.fn_set_age_bands(jsonb, text) to authenticated;

-- Grupos de la hoja de casos para las organizaciones que ya existen (si no tienen ninguno)
insert into public.age_band (organization_id, label_es, min_age, sort_order)
select o.id, v.label_es, v.min_age, v.sort_order
from public.organization o
cross join (values
    ('NNA 0-3', 0, 1), ('NNA 4-6', 4, 2), ('NNA 7-11', 7, 3), ('NNA 12-17', 12, 4),
    ('Personas adultas 18-59', 18, 5), ('Personas adultas mayores 60+', 60, 6)
) as v(label_es, min_age, sort_order)
where not exists (select 1 from public.age_band a where a.organization_id = o.id);

-- Indicadores: el grupo por edad sale de los grupos configurados.
-- Se redefine a partir de la definición vigente (20261015000003); solo cambia el bloque 'age_band'.
create or replace function public.fn_metric_rows(p_org uuid, p_from date, p_to date)
returns table (metric text, bucket text, n int, val numeric, ord int, by_freq boolean)
language sql
stable
security definer
set search_path = public
as $$
    with elig as (
        select c.id as case_id, c.opened_at, c.intake_window_type, c.intake_date, p.sex_id,
               coalesce(nullif(trim(p.other_nationality), ''), 'Sin dato') as nationality,
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
