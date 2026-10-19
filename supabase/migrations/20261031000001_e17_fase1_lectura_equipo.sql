-- ==============================================================================
-- E17 fase 1 · Lectura para la tabla de «Equipo»
--
-- Contexto: «Equipo» pasa de tarjetas a una tabla con panel lateral (propuesta E17). Dos datos que la interfaz no puede leer
-- por sí sola:
--  * si cada persona ya aceptó su invitación (vive en Supabase Auth, no en nuestras tablas);
--  * qué puede hacer cada persona y por qué (hoy cada cuenta solo conoce sus propios permisos).
--
-- Cómo
--  * `fn_team_access()`: una fila por persona de la organización de quien consulta, con `accepted` (confirmó su correo o ya
--    tiene contraseña) y la fecha de su último acceso. Solo con la capacidad de gestionar el equipo (BV346).
--  * `fn_user_capabilities(persona)`: las capacidades vigentes de esa persona y **de dónde le llegan**: por un rol, por un área
--    o por la salvaguarda (sin ninguna concesión en la organización aplica la dirección). Calcula lo mismo que `has_capability`
--    pero para otra cuenta. Una cuenta desactivada no tiene ninguna. Solo con la capacidad de gestionar el equipo (BV346) y
--    solo para personas de la misma organización (BV347).
--  * Ninguna escribe nada ni devuelve correos ni nombres de otras organizaciones.
-- ==============================================================================

create or replace function public.fn_team_access()
returns table (user_id uuid, accepted boolean, last_sign_in_at timestamptz)
stable
security definer
set search_path = public
language plpgsql as $$
begin
    if auth.uid() is null or public.current_organization_id() is null or not public.can_manage_team() then
        raise exception 'Acceso denegado: la gestión del equipo es de la dirección (o de quien reciba ese permiso).' using errcode = 'BV346';
    end if;
    return query
        select up.id,
               (u.email_confirmed_at is not null or coalesce(u.encrypted_password, '') <> ''),
               u.last_sign_in_at
        from public.user_profile up
        join auth.users u on u.id = up.id
        where up.organization_id = public.current_organization_id();
end;
$$;
revoke execute on function public.fn_team_access() from public, anon;
grant execute on function public.fn_team_access() to authenticated;

create or replace function public.fn_user_capabilities(p_user_id uuid)
returns table (capability_code text, source_kind text, role_name text, area_id uuid)
stable
security definer
set search_path = public
language plpgsql as $$
declare
    v_org uuid := public.current_organization_id();
begin
    if auth.uid() is null or v_org is null or not public.can_manage_team() then
        raise exception 'Acceso denegado: la gestión del equipo es de la dirección (o de quien reciba ese permiso).' using errcode = 'BV346';
    end if;
    if not exists (select 1 from public.user_profile up where up.id = p_user_id and up.organization_id = v_org) then
        raise exception 'Esa cuenta no existe en tu organización.' using errcode = 'BV347';
    end if;
    -- Una cuenta desactivada no puede nada, aunque conserve sus roles
    if not exists (select 1 from public.user_profile up where up.id = p_user_id and up.active) then
        return;
    end if;

    return query
        -- Por un rol vigente con una concesión a ese rol
        select g.capability_code, 'role'::text, g.role_name, null::uuid
        from public.capability_grant g
        join public.capability c on c.code = g.capability_code
        where g.organization_id = v_org and g.revoked_at is null and g.role_name is not null
          and exists (select 1 from public.user_role ur where ur.user_id = p_user_id and ur.revoked_at is null and ur.role_name = g.role_name)
        union
        -- Por pertenecer a un área con una concesión a esa área (rol operativo en ella)
        select g.capability_code, 'area'::text, null::text, g.area_id
        from public.capability_grant g
        join public.capability c on c.code = g.capability_code
        where g.organization_id = v_org and g.revoked_at is null and g.area_id is not null
          and exists (select 1 from public.user_role ur where ur.user_id = p_user_id and ur.revoked_at is null and ur.area_id = g.area_id
                      and ur.role_name in ('director', 'intake_officer', 'caseworker'))
        union
        -- Salvaguarda: sin ninguna concesión vigente de la capacidad en la organización, aplica la dirección
        select c.code, 'safeguard'::text, 'director'::text, null::uuid
        from public.capability c
        where not exists (select 1 from public.capability_grant g where g.organization_id = v_org and g.capability_code = c.code and g.revoked_at is null)
          and exists (select 1 from public.user_role ur where ur.user_id = p_user_id and ur.revoked_at is null and ur.role_name = 'director');
end;
$$;
revoke execute on function public.fn_user_capabilities(uuid) from public, anon;
grant execute on function public.fn_user_capabilities(uuid) to authenticated;
