-- ==============================================================================
-- D-24 tanda 2 · Administración como capacidades
--
-- Contexto: cuatro funciones de administración seguían escritas por nombre de rol (`has_role('director')`). Decisión del
-- Product Owner (23 oct 2026, «de acuerdo con tus recomendaciones»): migrarlas a capacidades configurables **sin cambiar el
-- comportamiento por omisión**: sigue siendo solo de la dirección hasta que ella delegue.
--
-- Capacidades nuevas (el catálogo pasa de cinco a nueve):
--  * `manage_areas`           áreas funcionales de la organización (`area`)
--  * `manage_status_catalog`  ejes y valores de estatus (`status_axis`, `status_value`)
--  * `manage_task_catalogs`   categorías, áreas de trabajo y tipos de tarea de expediente (`task_category`, `work_area`,
--                             `case_task_kind`)
--  * `manage_task_settings`   ajustes de operación de tareas (`fn_update_task_setting`)
--
-- Notas
--  * El inventario previo de D-24 no vio las políticas de `task_category` y `work_area`, escritas con comillas dobles dentro de
--    una cadena de `format()`; se migran aquí con `case_task_kind`.
--  * Quien administra los catálogos de tareas debe poder ver también lo archivado (si no, no podría desarchivar).
--  * Cambiar permisos sigue siendo solo de la dirección (BV353): delegar una capacidad no permite delegar más.
-- ==============================================================================

-- ---------------------------------------------------------------- 1. Catálogo y valores por omisión
insert into public.capability (code, description_es, sort_order) values
    ('manage_areas', 'Administrar las áreas de la organización', 6),
    ('manage_status_catalog', 'Administrar el catálogo de estatus (ejes y valores)', 7),
    ('manage_task_catalogs', 'Administrar los catálogos de tareas (categorías, áreas de trabajo y tipos de tarea de expediente)', 8),
    ('manage_task_settings', 'Cambiar los ajustes de operación de las tareas (notas de turno y bolsa de tareas)', 9)
on conflict (code) do update set description_es = excluded.description_es, sort_order = excluded.sort_order;

create or replace function public.fn_seed_default_capabilities(p_org uuid)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_code text;
    v_ts uuid;
begin
    foreach v_code in array array['manage_catalogs', 'manage_team', 'view_audit', 'manage_authority_requests', 'manage_org_settings',
                                  'manage_areas', 'manage_status_catalog', 'manage_task_catalogs', 'manage_task_settings'] loop
        insert into public.capability_grant (organization_id, capability_code, role_name, grant_reason)
        select p_org, v_code, 'director', 'Valor por omisión'
        where not exists (
            select 1 from public.capability_grant g
            where g.organization_id = p_org and g.capability_code = v_code and g.role_name = 'director' and g.revoked_at is null
        );
    end loop;
    select id into v_ts from public.area where organization_id = p_org and code = 'trabajo_social' limit 1;
    if v_ts is not null then
        insert into public.capability_grant (organization_id, capability_code, area_id, grant_reason)
        select p_org, 'manage_catalogs', v_ts, 'Valor por omisión'
        where not exists (
            select 1 from public.capability_grant g
            where g.organization_id = p_org and g.capability_code = 'manage_catalogs' and g.area_id = v_ts and g.revoked_at is null
        );
    end if;
end;
$$;
revoke execute on function public.fn_seed_default_capabilities(uuid) from public, anon, authenticated;

select public.fn_seed_default_capabilities(o.id) from public.organization o;

-- ---------------------------------------------------------------- 2. Políticas de administración
drop policy if exists "Directores gestionan áreas de su organización" on public.area;
drop policy if exists area_manage_insert on public.area;
create policy area_manage_insert on public.area for insert to authenticated
    with check (organization_id = public.current_organization_id() and (select public.has_capability('manage_areas')));
drop policy if exists area_manage_update on public.area;
create policy area_manage_update on public.area for update to authenticated
    using (organization_id = public.current_organization_id() and (select public.has_capability('manage_areas')))
    with check (organization_id = public.current_organization_id() and (select public.has_capability('manage_areas')));

drop policy if exists "Directores gestionan ejes de estatus de su organización" on public.status_axis;
drop policy if exists status_axis_manage_insert on public.status_axis;
create policy status_axis_manage_insert on public.status_axis for insert to authenticated
    with check (organization_id = public.current_organization_id() and (select public.has_capability('manage_status_catalog')));
drop policy if exists status_axis_manage_update on public.status_axis;
create policy status_axis_manage_update on public.status_axis for update to authenticated
    using (organization_id = public.current_organization_id() and (select public.has_capability('manage_status_catalog')))
    with check (organization_id = public.current_organization_id() and (select public.has_capability('manage_status_catalog')));

drop policy if exists "Directores gestionan valores de estatus de su organización" on public.status_value;
drop policy if exists status_value_manage_insert on public.status_value;
create policy status_value_manage_insert on public.status_value for insert to authenticated
    with check (organization_id = public.current_organization_id() and (select public.has_capability('manage_status_catalog')));
drop policy if exists status_value_manage_update on public.status_value;
create policy status_value_manage_update on public.status_value for update to authenticated
    using (organization_id = public.current_organization_id() and (select public.has_capability('manage_status_catalog')))
    with check (organization_id = public.current_organization_id() and (select public.has_capability('manage_status_catalog')));

do $$
declare
    t text;
begin
    foreach t in array array['task_category', 'work_area', 'case_task_kind'] loop
        execute format('drop policy if exists %1$s_select on public.%1$I', t);
        execute format('create policy %1$s_select on public.%1$I for select to authenticated
                        using (archived_at is null or public.has_task_management() or (select public.has_capability(''manage_task_catalogs'')))', t);
        execute format('drop policy if exists %1$s_insert on public.%1$I', t);
        execute format('create policy %1$s_insert on public.%1$I for insert to authenticated
                        with check ((select public.has_capability(''manage_task_catalogs'')))', t);
        execute format('drop policy if exists %1$s_update on public.%1$I', t);
        execute format('create policy %1$s_update on public.%1$I for update to authenticated
                        using ((select public.has_capability(''manage_task_catalogs'')))
                        with check ((select public.has_capability(''manage_task_catalogs'')))', t);
    end loop;
end $$;

-- ---------------------------------------------------------------- 3. Ajustes de operación
create or replace function public.fn_update_task_setting(
    p_shift_note_scope text,
    p_shift_note_days int,
    p_pool_max_unstarted int,
    p_pool_release_days int
)
returns uuid
security definer
set search_path = public
language plpgsql as $$
declare
    v_org uuid := public.current_organization_id();
    v_id uuid;
begin
    if auth.uid() is null or not public.is_active_user() or not public.has_capability('manage_task_settings') then
        raise exception 'Acceso denegado: se requiere el permiso de cambiar los ajustes de operación (por omisión, la dirección).' using errcode = 'TK010';
    end if;
    if p_shift_note_scope not in ('all', 'area', 'own') then
        raise exception 'El alcance de las notas de turno debe ser all, area u own.' using errcode = 'TK024';
    end if;
    if p_shift_note_days is null or p_shift_note_days < 0 or p_shift_note_days > 3650 then
        raise exception 'Los días visibles de las notas deben estar entre 0 y 3650.' using errcode = 'TK024';
    end if;
    if p_pool_max_unstarted is null or p_pool_max_unstarted < 0 or p_pool_max_unstarted > 100 then
        raise exception 'El tope del pool debe estar entre 0 y 100.' using errcode = 'TK024';
    end if;
    if p_pool_release_days is null or p_pool_release_days < 0 or p_pool_release_days > 365 then
        raise exception 'Los días para devolver al pool deben estar entre 0 y 365.' using errcode = 'TK024';
    end if;

    update public.task_setting
       set shift_note_scope = p_shift_note_scope,
           shift_note_days = p_shift_note_days,
           pool_max_unstarted = p_pool_max_unstarted,
           pool_release_days = p_pool_release_days
     where organization_id = v_org
    returning id into v_id;

    if v_id is null then
        raise exception 'La organización no tiene ajustes de operación.' using errcode = 'TK024';
    end if;
    return v_id;
end;
$$;

revoke execute on function public.fn_update_task_setting(text, int, int, int) from public, anon;
grant execute on function public.fn_update_task_setting(text, int, int, int) to authenticated;
