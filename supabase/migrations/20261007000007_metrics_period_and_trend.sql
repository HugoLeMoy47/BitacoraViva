-- ==============================================================================
-- Indicadores agregados con periodo, comparación y tendencia (E-05: n >= 5)
--
-- fn_aggregate_metrics(p_from, p_to):
--   * filtra la cohorte por fecha de ingreso en [p_from, p_to] (sin fechas = todo);
--   * si se dan ambas fechas, calcula también el periodo inmediato anterior de igual
--     duración y devuelve prev_count/prev_value para comparar. La supresión n < 5 se
--     aplica por separado a cada periodo: una cifra oculta nunca se deduce de la otra;
--   * agrega egresos por mes (casos que llegan a «Cierre y Egreso» en el periodo) y
--     tiempos promedio de proceso (ingreso → plan de acompañamiento; ingreso → cierre).
-- La lógica de conteo vive en fn_metric_rows (interna, no ejecutable por roles de
-- aplicación) para calcular el mismo cuerpo sobre dos periodos sin duplicarlo.
-- Se mantiene la exclusión de expedientes con oposición a usos secundarios (BV-5.5).
-- ==============================================================================

drop function if exists public.fn_aggregate_metrics();

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
    select 'sex', b.sex_id::text, count(*)::int, count(*)::numeric, 0, false from base b group by 2
    union all
    select 'age_band',
           case when b.age_at_intake < 12 then '0-11'
                when b.age_at_intake < 18 then '12-17'
                when b.age_at_intake < 30 then '18-29'
                when b.age_at_intake < 45 then '30-44'
                else '45+' end,
           count(*)::int, count(*)::numeric, 0, false
    from base b group by 2
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

revoke execute on function public.fn_metric_rows(uuid, date, date) from public, anon, authenticated;

create or replace function public.fn_aggregate_metrics(p_from date default null, p_to date default null)
returns jsonb
stable
security definer
set search_path = public
language plpgsql as $$
declare
    v_org uuid := public.current_organization_id();
    v_min constant int := 5;
    v_len int;
    v_pf date;
    v_pt date;
    v_result jsonb;
begin
    if v_org is null or not public.has_any_role() then
        raise exception 'Acceso denegado: se requiere una sesión con rol vigente.';
    end if;

    if p_from is not null and p_to is not null then
        if p_from > p_to then
            raise exception 'El periodo es inválido: la fecha inicial es posterior a la final.';
        end if;
        v_len := p_to - p_from + 1;
        v_pf := p_from - v_len;
        v_pt := p_from - 1;
    end if;

    with cur as (
        select * from public.fn_metric_rows(v_org, p_from, p_to)
    ),
    prev as (
        select * from public.fn_metric_rows(v_org, v_pf, v_pt) where v_pf is not null
    )
    select jsonb_build_object(
        'min_group_size', v_min,
        'generated_at', now(),
        'period', jsonb_build_object('from', p_from, 'to', p_to, 'prev_from', v_pf, 'prev_to', v_pt),
        'rows', coalesce(jsonb_agg(jsonb_build_object(
            'metric', c.metric,
            'bucket', c.bucket,
            'count', case when c.n >= v_min then c.n end,
            'value', case when c.n >= v_min and c.metric = 'duration' then round(c.val, 1) end,
            'suppressed', c.n < v_min,
            'prev_count', case when pr.n >= v_min then pr.n end,
            'prev_value', case when pr.n >= v_min and c.metric = 'duration' then round(pr.val, 1) end
        ) order by c.metric,
                   (case when c.by_freq and c.n >= v_min then -c.n else c.ord end),
                   c.bucket), '[]'::jsonb)
    ) into v_result
    from cur c
    left join prev pr on pr.metric = c.metric and pr.bucket = c.bucket;

    return v_result;
end;
$$;

revoke execute on function public.fn_aggregate_metrics(date, date) from public, anon;
grant execute on function public.fn_aggregate_metrics(date, date) to authenticated;
