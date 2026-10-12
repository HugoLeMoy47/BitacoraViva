-- ==============================================================================
-- Indicadores: cifras exactas para quien trabaja en la organización; redondeadas solo para el
-- observador externo (Ethos C6 · riesgo R-19) · decisión del Product Owner, opción B
--
-- La migración 20261011000004 redondeaba a múltiplos de 5 para todo rol que no fuera Dirección.
-- Eso daba una contradicción dentro de la organización (Dirección veía 59; ingreso o una persona
-- de operación de caso veía 60) y la herramienta debe ser confiable en sus números.
--
-- Criterio de la opción B:
--   * Dirección, ingreso y operación de caso (los roles operativos) ya acceden a cada expediente:
--     esconderles la cifra exacta no protege a nadie y solo les cuesta confiabilidad.
--   * El observador (`viewer`) es el único rol de «afuera»: sus cifras siguen redondeadas a
--     múltiplos de 5 y la interfaz lo rotula con «≈».
--   * Quien acumula un rol operativo y el de observador ve lo exacto (el rol operativo manda).
-- La supresión por tamaño (n < 5) y la supresión complementaria no cambian: rigen para todos.
--
-- Solo cambia v_exact; el resto de la función es idéntico a 20261011000004.
-- ==============================================================================

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

    -- Cifras exactas para los roles operativos; redondeadas solo para el observador externo (R-19)
    v_exact := public.has_operational_role();

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
