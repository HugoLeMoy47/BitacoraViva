-- ==============================================================================
-- Indicadores sin re-identificación por resta (Ethos C6 · E-05) · riesgo R-19
--
-- Hallazgo M-2 de la auditoría del 11 oct 2026. Con el rol `viewer` se comprobó que el
-- umbral n >= 5 se podía rodear de dos maneras:
--   * Por complemento: el total menos las celdas visibles de un grupo deja al descubierto
--     las celdas suprimidas (si es una sola, su valor exacto).
--   * Por diferencia de ventanas: dos consultas con fechas que difieren en unos días,
--     restadas, revelan cuántas personas entraron en ese lapso en una celda de 1 a 4 personas.
--
-- Decisión del Product Owner (11 oct 2026): opciones 1 y 3.
--   1. Redondeo: para quien no es de Dirección, toda cifra mostrada se redondea al múltiplo
--      de 5 más cercano. Dirección ve la cifra exacta (ya tiene acceso a los expedientes).
--      Una cifra visible nunca baja de 5.
--   3. Supresión complementaria: en un grupo que reparte los casos (cada caso en una sola
--      celda), si se oculta exactamente UNA celda por pequeña, se oculta también la celda
--      visible más pequeña: la resta ya no revela nada. Rige para todos los roles.
--
-- La supresión por tamaño (n < 5) no cambia. Cada periodo (el pedido y el anterior) se
-- protege por separado. El resultado informa `exact` (si las cifras son exactas) y, en cada
-- fila, `hidden_reason` ('small' | 'complement' | null).
-- ==============================================================================

-- Filas con su motivo de ocultamiento. Interna: no ejecutable por los roles de aplicación.
create or replace function public.fn_metric_rows_protected(p_org uuid, p_from date, p_to date)
returns table (metric text, bucket text, n int, val numeric, ord int, by_freq boolean, hidden text)
language sql
stable
security definer
set search_path = public
as $$
    with r as (
        select * from public.fn_metric_rows(p_org, p_from, p_to)
    ),
    w as (
        select r.*,
               -- Grupos que reparten los casos: cada caso cae en una sola celda
               r.metric in ('intake_window_type', 'intake_month', 'sex', 'age_band', 'nationality',
                            'case_stage', 'legal_status', 'engagement_status', 'shelter_status') as is_partition,
               count(*) filter (where r.n < 5) over (partition by r.metric) as n_small,
               row_number() over (partition by r.metric, (r.n >= 5) order by r.n, r.bucket) as rn_visible
        from r
    )
    select w.metric, w.bucket, w.n, w.val, w.ord, w.by_freq,
           case
               when w.n < 5 then 'small'
               when w.is_partition and w.n_small = 1 and w.rn_visible = 1 then 'complement'
           end
    from w
$$;

revoke execute on function public.fn_metric_rows_protected(uuid, date, date) from public, anon, authenticated;

create or replace function public.fn_aggregate_metrics(p_from date default null, p_to date default null)
returns jsonb
stable
security definer
set search_path = public
language plpgsql as $$
declare
    v_org uuid := public.current_organization_id();
    v_min constant int := 5;
    v_exact boolean;
    v_len int;
    v_pf date;
    v_pt date;
    v_result jsonb;
begin
    if v_org is null or not public.has_any_role() then
        raise exception 'Acceso denegado: se requiere una sesión con rol vigente.';
    end if;

    -- Dirección ve cifras exactas; el resto, redondeadas a múltiplos de 5 (R-19)
    v_exact := public.has_role('director');

    if p_from is not null and p_to is not null then
        if p_from > p_to then
            raise exception 'El periodo es inválido: la fecha inicial es posterior a la final.';
        end if;
        v_len := p_to - p_from + 1;
        v_pf := p_from - v_len;
        v_pt := p_from - 1;
    end if;

    with cur as (
        select * from public.fn_metric_rows_protected(v_org, p_from, p_to)
    ),
    prev as (
        select * from public.fn_metric_rows_protected(v_org, v_pf, v_pt) where v_pf is not null
    )
    select jsonb_build_object(
        'min_group_size', v_min,
        'exact', v_exact,
        'rounded_to', case when v_exact then null else 5 end,
        'generated_at', now(),
        'period', jsonb_build_object('from', p_from, 'to', p_to, 'prev_from', v_pf, 'prev_to', v_pt),
        'rows', coalesce(jsonb_agg(jsonb_build_object(
            'metric', c.metric,
            'bucket', c.bucket,
            'count', case when c.hidden is null
                          then (case when v_exact then c.n else ((c.n + 2) / 5) * 5 end) end,
            'value', case when c.hidden is null and c.metric = 'duration' then round(c.val, 1) end,
            'suppressed', c.hidden is not null,
            'hidden_reason', c.hidden,
            'prev_count', case when pr.n is not null and pr.hidden is null
                               then (case when v_exact then pr.n else ((pr.n + 2) / 5) * 5 end) end,
            'prev_value', case when pr.n is not null and pr.hidden is null and c.metric = 'duration'
                               then round(pr.val, 1) end
        ) order by c.metric,
                   (case when c.by_freq and c.hidden is null then -c.n else c.ord end),
                   c.bucket), '[]'::jsonb)
    ) into v_result
    from cur c
    left join prev pr on pr.metric = c.metric and pr.bucket = c.bucket;

    return v_result;
end;
$$;

revoke execute on function public.fn_aggregate_metrics(date, date) from public, anon;
grant execute on function public.fn_aggregate_metrics(date, date) to authenticated;
