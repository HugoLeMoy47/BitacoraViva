-- ==============================================================================
-- Indicadores agregados ampliados (Ethos E-05: umbral n >= 5)
--
-- Reemplaza fn_aggregate_metrics (20261007000001) con la misma firma y la misma
-- garantia: supresion de celdas con n < 5 y exclusion de expedientes con oposicion a
-- usos secundarios (BV-5.5). Agrega: situacion ante la organizacion, alojamiento,
-- nacionalidad, sexo, grupo de edad (a la fecha de ingreso) e ingreso por mes.
--
-- Orden de salida: ejes de estatus por su sort_order; nacionalidad y vulnerabilidad
-- por frecuencia (solo celdas visibles; las suprimidas al final y por nombre, para
-- no filtrar su orden relativo). Nota: la supresion es primaria; no hay supresion
-- complementaria, por lo que un total y sus categorias podrian permitir inferir una
-- celda oculta en poblaciones muy pequenas.
-- ==============================================================================

create or replace function public.fn_aggregate_metrics()
returns jsonb
stable
security definer
set search_path = public
language plpgsql as $$
declare
    v_org uuid := public.current_organization_id();
    v_min constant int := 5;
    v_result jsonb;
begin
    if v_org is null or not public.has_any_role() then
        raise exception 'Acceso denegado: se requiere una sesión con rol vigente.';
    end if;

    with base as (
        select
            c.id as case_id,
            c.intake_window_type,
            c.intake_date,
            p.sex_id,
            coalesce(nullif(trim(p.other_nationality), ''), 'Sin dato') as nationality,
            extract(year from age(c.intake_date, p.birth_date))::int as age_at_intake
        from public."case" c
        join public.person p on p.id = c.titular_person_id
        where c.organization_id = v_org
          and not exists (
              select 1 from public.consent k
              where k.person_id = p.id
                and k.consent_type = 'secondary_use_research'
                and k.status = 'opposed'
          )
    ),
    cur as (
        select cs.case_id, ax.code as axis, sv.label_es, sv.sort_order
        from public.case_status cs
        join public.status_axis ax on ax.id = cs.axis_id
        join public.status_value sv on sv.id = cs.value_id
        where cs.valid_to is null and cs.organization_id = v_org
    ),
    raw as (
        select 'total_cases'::text as metric, 'all'::text as bucket, count(*)::int as n, 0 as ord, true as by_freq from base
        union all
        select 'intake_window_type', b.intake_window_type, count(*)::int, 0, false from base b group by 2
        union all
        select 'intake_month', to_char(b.intake_date, 'YYYY-MM'), count(*)::int, 0, false from base b group by 2
        union all
        select 'sex', b.sex_id::text, count(*)::int, 0, false from base b group by 2
        union all
        select 'age_band',
               case when b.age_at_intake < 12 then '0-11'
                    when b.age_at_intake < 18 then '12-17'
                    when b.age_at_intake < 30 then '18-29'
                    when b.age_at_intake < 45 then '30-44'
                    else '45+' end,
               count(*)::int, 0, false
        from base b group by 2
        union all
        select 'nationality', b.nationality, count(*)::int, 0, true from base b group by 2
        union all
        select 'vulnerability', m.marker_code, count(distinct m.case_id)::int, 0, true
        from public.case_vulnerability_marker m
        join base b on b.case_id = m.case_id
        where m.removed_at is null group by 2
        union all
        select 'case_stage', cur.label_es, count(*)::int, min(cur.sort_order), false
        from base b join cur on cur.case_id = b.case_id and cur.axis = 'case_stage' group by cur.label_es
        union all
        select 'legal_status', cur.label_es, count(*)::int, min(cur.sort_order), false
        from base b join cur on cur.case_id = b.case_id and cur.axis = 'legal_status' group by cur.label_es
        union all
        select 'engagement_status', cur.label_es, count(*)::int, min(cur.sort_order), false
        from base b join cur on cur.case_id = b.case_id and cur.axis = 'engagement_status' group by cur.label_es
        union all
        select 'shelter_status', cur.label_es, count(*)::int, min(cur.sort_order), false
        from base b join cur on cur.case_id = b.case_id and cur.axis = 'shelter_status' group by cur.label_es
    ),
    metrics as (
        select metric, bucket, n,
               case when by_freq and n >= v_min then -n else ord end as ord
        from raw
    )
    select jsonb_build_object(
        'min_group_size', v_min,
        'generated_at', now(),
        'rows', coalesce(jsonb_agg(jsonb_build_object(
            'metric', metric,
            'bucket', bucket,
            'count', case when n >= v_min then n end,
            'suppressed', n < v_min
        ) order by metric, ord, bucket), '[]'::jsonb)
    ) into v_result
    from metrics;

    return v_result;
end;
$$;

revoke execute on function public.fn_aggregate_metrics() from public, anon;
grant execute on function public.fn_aggregate_metrics() to authenticated;
