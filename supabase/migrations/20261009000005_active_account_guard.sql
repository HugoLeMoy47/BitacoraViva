-- ==============================================================================
-- Cuenta desactivada = sin acceso al expediente (Regla Dura 1)
--
-- Hallazgo que corrige
--  `user_profile.active` no se revisaba en ninguna política ni función del núcleo de
--  casos. Los helpers de acceso sólo miraban `user_role.revoked_at is null`; una cuenta
--  desactivada (active = false) con roles sin revocar seguía leyendo y escribiendo
--  expedientes y podía ejecutar las funciones SECURITY DEFINER. El módulo de tareas ya
--  lo resolvía con `is_active_user()`; el núcleo de casos no. Hoy es latente (la
--  desactivación llega con la épica E11) y se cierra antes del primer dato real.
--
-- Estrategia
--  Se corrige en los helpers, no en cada política: todas las políticas y funciones
--  existentes los llaman, así que una sola redefinición cubre el núcleo completo sin
--  reescribir ninguna. Mismas firmas (CREATE OR REPLACE), mismos permisos (se conservan).
--  La comprobación va en línea (JOIN con user_profile) y no anidando is_active_user(),
--  para no pagar una llamada SECURITY DEFINER extra por fila evaluada.
--
--  * current_organization_id()  -> NULL para una cuenta desactivada. Es lo que cierra
--    toda política «organization_id = current_organization_id()» (incluidas lectura de
--    organización, perfiles, roles, áreas y auditoría) y toda función que toma la
--    organización de la sesión.
--  * has_role(), has_role_in_area(), has_case_role(), has_operational_role(),
--    has_active_role() -> falso para una cuenta desactivada. has_any_role() ya delega
--    en has_case_role() (20261009000001) y queda cubierta.
--  * has_task_role(), has_task_management() y user_has_task_role() ya exigían cuenta
--    activa: no se tocan.
--
-- Efecto colateral buscado
--  Una cuenta desactivada ya no lee ni su propio perfil. El cliente (src/lib/session.tsx)
--  trata «sin perfil» igual que «perfil inactivo» y la devuelve a la pantalla de acceso.
--
-- TK006 no cambia: fn_protect_last_director sigue impidiendo desactivar al último
-- director vigente de la organización, así que esta migración no puede dejarla sin
-- dirección. Para revertir: volver a aplicar las definiciones de 20260914000001,
-- 20261007000001 y 20261009000001.
-- ==============================================================================

create or replace function public.current_organization_id()
returns uuid
stable
security definer
set search_path = public
language sql as $$
    select up.organization_id
    from public.user_profile up
    where up.id = auth.uid() and up.active
    limit 1;
$$;

create or replace function public.has_role(p_role text)
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select exists (
        select 1
        from public.user_role ur
        join public.user_profile up on up.id = ur.user_id
        where ur.user_id = auth.uid()
          and up.active
          and ur.role_name = p_role
          and ur.revoked_at is null
    );
$$;

create or replace function public.has_role_in_area(p_role text, p_area_code text)
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select exists (
        select 1
        from public.user_role ur
        join public.user_profile up on up.id = ur.user_id
        join public.area a on a.id = ur.area_id
        where ur.user_id = auth.uid()
          and up.active
          and ur.role_name = p_role
          and a.code = p_area_code
          and ur.revoked_at is null
    );
$$;

-- viewer, caseworker, intake_officer o director vigentes. has_any_role() delega aquí.
create or replace function public.has_case_role()
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select exists (
        select 1
        from public.user_role ur
        join public.user_profile up on up.id = ur.user_id
        where ur.user_id = auth.uid()
          and up.active
          and ur.revoked_at is null
          and ur.role_name in ('viewer', 'caseworker', 'intake_officer', 'director')
    );
$$;

-- Roles que operan expedientes. viewer queda fuera a propósito.
create or replace function public.has_operational_role()
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select exists (
        select 1
        from public.user_role ur
        join public.user_profile up on up.id = ur.user_id
        where ur.user_id = auth.uid()
          and up.active
          and ur.revoked_at is null
          and ur.role_name in ('director', 'intake_officer', 'caseworker')
    );
$$;

-- Cualquier rol vigente, de casos o de tareas.
create or replace function public.has_active_role()
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select exists (
        select 1
        from public.user_role ur
        join public.user_profile up on up.id = ur.user_id
        where ur.user_id = auth.uid()
          and up.active
          and ur.revoked_at is null
    );
$$;
