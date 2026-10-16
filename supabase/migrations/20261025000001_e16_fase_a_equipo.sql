-- ==============================================================================
-- E16 fase A · Gestionar el equipo (roles y cuentas de quien ya existe)
--
-- Contexto: no había función ni pantalla para otorgar, cambiar ni revocar roles; la dirección escribía directo en `user_role`
-- y `user_profile` por la API (deuda D-20), sin motivo ni salvaguardas. Decisiones del Product Owner (23 oct 2026):
--  * Solo la **dirección** gestiona el equipo por ahora, con la capacidad **configurable** para delegarla (fase B).
--  * **Rol y área son independientes**: cualquier rol puede ir con cualquier área o sin ella, y una persona puede tener
--    varios roles y áreas («muchas gorras»). No hay restricciones de combinación.
--  * **Nunca sin dirección** (ya lo impone el disparador `fn_protect_last_director`, TK006) y **nadie se revoca ni se
--    desactiva a sí mismo**.
--
-- Cómo
--  * `can_manage_team()`: hoy, la dirección. La fase B la vuelve una capacidad configurable sin cambiar quién la llama.
--  * `fn_grant_role`, `fn_revoke_role` y `fn_set_user_active`: validan, exigen motivo al quitar, dejan auditoría.
--    `user_role` guarda por qué se otorgó y por qué se revocó (`grant_reason`, `revoke_reason`).
--  * Se REVOCA la escritura directa de la API a `user_role` y `user_profile`: solo por estas funciones (paga la parte de
--    roles de D-20). La lectura sigue igual (la pantalla «Equipo» la usa).
--  * Errores con código estable: BV343 a BV348.
--
-- Idempotente: el reinicio de la demo reaplica todas las migraciones.
-- ==============================================================================

alter table public.user_role
    add column if not exists grant_reason text,
    add column if not exists revoke_reason text;

-- ---------------------------------------------------------------- 1. Quién gestiona el equipo
create or replace function public.can_manage_team()
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select public.has_role('director');
$$;
revoke execute on function public.can_manage_team() from public, anon;
grant execute on function public.can_manage_team() to authenticated;

-- ---------------------------------------------------------------- 2. Otorgar un rol (con o sin área; varios por persona)
create or replace function public.fn_grant_role(p_user_id uuid, p_role_name text, p_area_id uuid default null, p_reason text default null)
returns uuid
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_org uuid := public.current_organization_id();
    v_id uuid;
begin
    if v_user is null or v_org is null or not public.can_manage_team() then
        raise exception 'Acceso denegado: la gestión del equipo es de la dirección (o de quien reciba ese permiso).' using errcode = 'BV346';
    end if;
    if not exists (select 1 from public.user_profile where id = p_user_id and organization_id = v_org) then
        raise exception 'Esa cuenta no existe en tu organización.' using errcode = 'BV347';
    end if;
    if p_role_name is null or not exists (select 1 from public.role where name = p_role_name) then
        raise exception 'Ese rol o esa área no son válidos para esta organización.' using errcode = 'BV344';
    end if;
    if p_area_id is not null and not exists (
        select 1 from public.area where id = p_area_id and organization_id = v_org and active
    ) then
        raise exception 'Ese rol o esa área no son válidos para esta organización.' using errcode = 'BV344';
    end if;
    if exists (
        select 1 from public.user_role
        where user_id = p_user_id and role_name = p_role_name and revoked_at is null
          and coalesce(area_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_area_id, '00000000-0000-0000-0000-000000000000'::uuid)
    ) then
        raise exception 'Esa persona ya tiene ese rol en esa área.' using errcode = 'BV345';
    end if;

    insert into public.user_role (user_id, role_name, area_id, granted_by, grant_reason)
    values (p_user_id, p_role_name, p_area_id, v_user, nullif(btrim(coalesce(p_reason, '')), ''))
    returning id into v_id;
    return v_id;
end;
$$;
revoke execute on function public.fn_grant_role(uuid, text, uuid, text) from public, anon;
grant execute on function public.fn_grant_role(uuid, text, uuid, text) to authenticated;

-- ---------------------------------------------------------------- 3. Revocar (no se borra: fecha, quién y motivo)
create or replace function public.fn_revoke_role(p_user_role_id uuid, p_reason text)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_org uuid := public.current_organization_id();
    v_row record;
begin
    if v_user is null or v_org is null or not public.can_manage_team() then
        raise exception 'Acceso denegado: la gestión del equipo es de la dirección (o de quien reciba ese permiso).' using errcode = 'BV346';
    end if;
    -- Una asignación que no existe, ya no está vigente o es de otra organización se ve igual (no se revela su existencia)
    select ur.* into v_row
    from public.user_role ur join public.user_profile up on up.id = ur.user_id
    where ur.id = p_user_role_id and ur.revoked_at is null and up.organization_id = v_org;
    if v_row.id is null then
        raise exception 'Esa asignación no existe o ya no está vigente.' using errcode = 'BV348';
    end if;
    if v_row.user_id = v_user then
        raise exception 'No puedes quitarte a ti mismo el acceso: pídelo a otra persona con ese permiso.' using errcode = 'BV343';
    end if;
    if p_reason is null or btrim(p_reason) = '' then
        raise exception 'El motivo es obligatorio al cambiar o quitar un dato ya registrado (Ethos C8).' using errcode = 'BV304';
    end if;
    -- El disparador fn_protect_last_director impide dejar a la organización sin dirección (TK006)
    update public.user_role set revoked_at = now(), revoked_by = v_user, revoke_reason = btrim(p_reason) where id = v_row.id;
end;
$$;
revoke execute on function public.fn_revoke_role(uuid, text) from public, anon;
grant execute on function public.fn_revoke_role(uuid, text) to authenticated;

-- ---------------------------------------------------------------- 4. Desactivar o reactivar una cuenta
create or replace function public.fn_set_user_active(p_user_id uuid, p_active boolean, p_reason text default null)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_org uuid := public.current_organization_id();
    v_profile record;
begin
    if v_user is null or v_org is null or not public.can_manage_team() then
        raise exception 'Acceso denegado: la gestión del equipo es de la dirección (o de quien reciba ese permiso).' using errcode = 'BV346';
    end if;
    select * into v_profile from public.user_profile where id = p_user_id and organization_id = v_org;
    if v_profile.id is null then
        raise exception 'Esa cuenta no existe en tu organización.' using errcode = 'BV347';
    end if;
    if p_active is null then
        raise exception 'Ese rol o esa área no son válidos para esta organización.' using errcode = 'BV344';
    end if;
    if p_user_id = v_user and not p_active then
        raise exception 'No puedes quitarte a ti mismo el acceso: pídelo a otra persona con ese permiso.' using errcode = 'BV343';
    end if;
    if p_active = v_profile.active then
        return;
    end if;
    if p_reason is null or btrim(p_reason) = '' then
        raise exception 'El motivo es obligatorio al cambiar o quitar un dato ya registrado (Ethos C8).' using errcode = 'BV304';
    end if;

    -- El disparador fn_protect_last_director impide desactivar al último director (TK006)
    update public.user_profile set active = p_active, updated_at = now() where id = p_user_id;

    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_org, v_user, 'RECTIFICATION', 'user_profile', p_user_id,
            jsonb_build_object('changed_fields', jsonb_build_array('active'), 'reason', btrim(p_reason)));
end;
$$;
revoke execute on function public.fn_set_user_active(uuid, boolean, text) from public, anon;
grant execute on function public.fn_set_user_active(uuid, boolean, text) to authenticated;

-- ---------------------------------------------------------------- 5. Ya no se escribe directo (D-20, parte de roles)
revoke insert, update, delete on public.user_role from authenticated;
revoke insert, update, delete on public.user_profile from authenticated;
