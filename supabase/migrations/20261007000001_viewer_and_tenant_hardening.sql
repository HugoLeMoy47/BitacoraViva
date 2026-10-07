-- ==============================================================================
-- Viewer sin datos identificables + aislamiento por organizacion y rol
-- (Regla Dura 1, BV-1.1, BV-1.2, Ethos E-05)
--
-- Hallazgos que corrige:
--  * El rol viewer leia personas, casos y consentimientos completos, pese a que su
--    definicion es "metricas agregadas y anonimizadas, sin datos identificables".
--  * Un usuario con perfil pero sin rol vigente veia datos (BV-1.2: "no ve nada").
--  * consent y privacy_notice tenian SELECT using (true): lectura entre
--    organizaciones.
--  * journal_entry, sharing_event, arco_request y attachment dejaban pasar a
--    cualquier director/intake sin comprobar la organizacion.
--
-- Estrategia: politicas RESTRICTIVAS. Se combinan con AND sobre las politicas
-- permisivas existentes, que no se tocan. Revertir = drop policy.
-- ==============================================================================

-- Helpers (security definer, como has_role)
create or replace function public.has_any_role()
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select exists (
        select 1 from public.user_role
        where user_id = auth.uid() and revoked_at is null
    );
$$;

-- Roles que operan expedientes. viewer queda fuera a proposito.
create or replace function public.has_operational_role()
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select exists (
        select 1 from public.user_role
        where user_id = auth.uid()
          and revoked_at is null
          and role_name in ('director', 'intake_officer', 'caseworker')
    );
$$;

revoke execute on function public.has_any_role() from public, anon;
revoke execute on function public.has_operational_role() from public, anon;
grant execute on function public.has_any_role() to authenticated;
grant execute on function public.has_operational_role() to authenticated;

-- Tablas con datos de personas atendidas: solo roles operativos y misma organizacion
do $$
declare
    t text;
begin
    foreach t in array array[
        'person', 'case', 'case_status', 'case_vulnerability_marker',
        'journal_entry', 'sharing_event', 'consent', 'arco_request',
        'attachment', 'privacy_notice'
    ] loop
        execute format('drop policy if exists tenant_operational_select on public.%I', t);
        execute format(
            'create policy tenant_operational_select on public.%I as restrictive for select to authenticated '
            'using (organization_id = public.current_organization_id() and public.has_operational_role())',
            t
        );
    end loop;
end $$;

-- Catalogos y estructura: cualquier rol vigente, ninguno sin rol (BV-1.2)
do $$
declare
    t text;
begin
    foreach t in array array['organization', 'area', 'status_axis', 'status_value'] loop
        execute format('drop policy if exists require_active_role_select on public.%I', t);
        execute format(
            'create policy require_active_role_select on public.%I as restrictive for select to authenticated '
            'using (public.has_any_role())',
            t
        );
    end loop;
end $$;

-- Perfiles y roles: cada quien ve el propio (para informar "sin rol"); el resto exige rol vigente
drop policy if exists require_active_role_select on public.user_profile;
create policy require_active_role_select on public.user_profile
    as restrictive for select to authenticated
    using (id = auth.uid() or public.has_any_role());

drop policy if exists require_active_role_select on public.user_role;
create policy require_active_role_select on public.user_role
    as restrictive for select to authenticated
    using (user_id = auth.uid() or public.has_any_role());

-- ------------------------------------------------------------------------------
-- Indicadores agregados (Ethos E-05: umbral n >= 5)
-- Unica via de lectura de estadistica para viewer. Suprime celdas con n < 5 y excluye
-- expedientes con oposicion a usos secundarios (BV-5.5).
-- ------------------------------------------------------------------------------
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
        select c.id as case_id, c.intake_window_type
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
        select cs.case_id, ax.code as axis, sv.label_es
        from public.case_status cs
        join public.status_axis ax on ax.id = cs.axis_id
        join public.status_value sv on sv.id = cs.value_id
        where cs.valid_to is null and cs.organization_id = v_org
    ),
    metrics as (
        select 'total_cases'::text as metric, 'all'::text as bucket, count(*)::int as n from base
        union all
        select 'intake_window_type', b.intake_window_type, count(*)::int from base b group by 2
        union all
        select 'case_stage', cur.label_es, count(*)::int
        from base b join cur on cur.case_id = b.case_id and cur.axis = 'case_stage' group by 2
        union all
        select 'legal_status', cur.label_es, count(*)::int
        from base b join cur on cur.case_id = b.case_id and cur.axis = 'legal_status' group by 2
        union all
        select 'vulnerability', m.marker_code, count(distinct m.case_id)::int
        from public.case_vulnerability_marker m
        join base b on b.case_id = m.case_id
        where m.removed_at is null group by 2
    )
    select jsonb_build_object(
        'min_group_size', v_min,
        'generated_at', now(),
        'rows', coalesce(jsonb_agg(jsonb_build_object(
            'metric', metric,
            'bucket', bucket,
            'count', case when n >= v_min then n end,
            'suppressed', n < v_min
        ) order by metric, bucket), '[]'::jsonb)
    ) into v_result
    from metrics;

    return v_result;
end;
$$;

revoke execute on function public.fn_aggregate_metrics() from public, anon;
grant execute on function public.fn_aggregate_metrics() to authenticated;
