-- ==============================================================================
-- E16 fase C · Invitar personas (ADR-0010)
--
-- Contexto: la dirección ya gestiona el equipo (fases A y B) pero no puede dar de alta a una persona nueva: crear una cuenta
-- de acceso exige la llave `service_role`, que no puede estar en el navegador. El ADR-0010 decide una función de borde de
-- Supabase, delgada; **la regla vive aquí, en la base**.
--
-- Cómo
--  * `user_invitation`: una fila por invitación (correo en minúsculas, nombre, organización, quien invita, cuándo). Solo se
--    escribe por las funciones de abajo; la leen quienes gestionan el equipo (`manage_team`).
--  * `fn_prepare_invitation(correo, nombre)`: se llama **con la sesión de quien invita**. Exige `manage_team` (BV346), valida
--    el correo (BV354) y el nombre (BV355), que el correo no tenga ya una cuenta (BV356; responde igual si es de otra
--    organización, para no revelar de quién es) y aplica el **tope de 20 invitaciones por hora por persona** (BV357). La
--    **organización sale de la sesión**, nunca de la petición. Devuelve `{invitation_id, resend, user_id}`. Si el correo es de
--    una cuenta de esta organización, nacida de una invitación, que **aún no la aceptó** (sin confirmar), es un **reenvío**.
--  * `fn_complete_invitation(invitación, cuenta)`: solo la ejecuta la **llave de servicio**. Crea el perfil de la cuenta recién
--    creada en la organización de la invitación y la marca completada (BV358 si no existe o ya se completó).
--  * **Invitar no concede ningún rol**: la persona entra sin rol y la dirección se lo otorga con `fn_grant_role`.
-- ==============================================================================

-- ---------------------------------------------------------------- 1. La tabla
create table if not exists public.user_invitation (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    email text not null check (email = lower(btrim(email)) and char_length(email) between 3 and 254),
    full_name text not null check (btrim(full_name) <> '' and char_length(full_name) <= 120),
    invited_by uuid not null references public.user_profile(id),
    invited_at timestamptz not null default now(),
    user_id uuid references auth.users(id) on delete set null,
    completed_at timestamptz,
    updated_at timestamptz not null default now()
);
create index if not exists idx_user_invitation_org on public.user_invitation (organization_id, invited_at desc);
create index if not exists idx_user_invitation_inviter on public.user_invitation (invited_by, invited_at desc);
create index if not exists idx_user_invitation_email on public.user_invitation (organization_id, email);

alter table public.user_invitation enable row level security;
revoke all on public.user_invitation from anon;
revoke insert, update, delete on public.user_invitation from authenticated;
grant select on public.user_invitation to authenticated;

drop policy if exists user_invitation_select on public.user_invitation;
create policy user_invitation_select on public.user_invitation for select to authenticated
    using (organization_id = public.current_organization_id() and (select public.has_capability('manage_team')));

drop trigger if exists trg_audit_user_invitation on public.user_invitation;
create trigger trg_audit_user_invitation after insert or update on public.user_invitation
for each row execute function public.fn_audit_trigger_fields();

-- ---------------------------------------------------------------- 2. Preparar (con la sesión de quien invita)
create or replace function public.fn_prepare_invitation(p_email text, p_full_name text)
returns jsonb
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_org uuid := public.current_organization_id();
    v_email text := lower(btrim(coalesce(p_email, '')));
    v_name text := btrim(coalesce(p_full_name, ''));
    v_existing_id uuid;
    v_existing_org uuid;
    v_confirmed timestamptz;
    v_id uuid;
begin
    if v_user is null or v_org is null or not public.can_manage_team() then
        raise exception 'Acceso denegado: la gestión del equipo es de la dirección (o de quien reciba ese permiso).' using errcode = 'BV346';
    end if;
    if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' or char_length(v_email) > 254 then
        raise exception 'El correo no tiene forma de correo electrónico.' using errcode = 'BV354';
    end if;
    if v_name = '' or char_length(v_name) > 120 then
        raise exception 'El nombre es obligatorio y no puede pasar de 120 caracteres.' using errcode = 'BV355';
    end if;

    -- ¿Ya existe una cuenta con ese correo? Se mira en todo el sistema, pero la respuesta no dice de quién es.
    select u.id, u.email_confirmed_at into v_existing_id, v_confirmed from auth.users u where lower(u.email) = v_email limit 1;
    if v_existing_id is not null then
        select up.organization_id into v_existing_org from public.user_profile up where up.id = v_existing_id;
        -- Reenvío: es una cuenta de esta organización, nacida de una invitación, que aún no la aceptó
        if v_existing_org is not distinct from v_org and v_confirmed is null
           and exists (select 1 from public.user_invitation i where i.user_id = v_existing_id and i.completed_at is not null) then
            null;
        else
            raise exception 'Ese correo ya tiene una cuenta o no se puede invitar.' using errcode = 'BV356';
        end if;
    elsif exists (select 1 from public.user_profile up where lower(up.email) = v_email) then
        raise exception 'Ese correo ya tiene una cuenta o no se puede invitar.' using errcode = 'BV356';
    end if;

    -- Tope por persona y por hora (cuentan también los reenvíos)
    if (select count(*) from public.user_invitation i where i.invited_by = v_user and i.invited_at > now() - interval '1 hour') >= 20 then
        raise exception 'Llegaste al tope de invitaciones por hora. Inténtalo más tarde.' using errcode = 'BV357';
    end if;

    insert into public.user_invitation (organization_id, email, full_name, invited_by, user_id)
    values (v_org, v_email, v_name, v_user, case when v_existing_id is not null then v_existing_id end)
    returning id into v_id;

    return jsonb_build_object('invitation_id', v_id, 'resend', v_existing_id is not null, 'user_id', v_existing_id);
end;
$$;
revoke execute on function public.fn_prepare_invitation(text, text) from public, anon;
grant execute on function public.fn_prepare_invitation(text, text) to authenticated;

-- ---------------------------------------------------------------- 3. Completar (solo la llave de servicio)
create or replace function public.fn_complete_invitation(p_invitation_id uuid, p_user_id uuid)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_inv public.user_invitation%rowtype;
begin
    if auth.role() is distinct from 'service_role' then
        raise exception 'Esa invitación no existe o ya se completó.' using errcode = 'BV358';
    end if;
    select * into v_inv from public.user_invitation where id = p_invitation_id for update;
    if v_inv.id is null or v_inv.completed_at is not null or p_user_id is null
       or not exists (select 1 from auth.users where id = p_user_id) then
        raise exception 'Esa invitación no existe o ya se completó.' using errcode = 'BV358';
    end if;

    -- En un reenvío la cuenta ya tiene su perfil; si no, se crea en la organización de la invitación
    insert into public.user_profile (id, organization_id, email, full_name, active)
    values (p_user_id, v_inv.organization_id, v_inv.email, v_inv.full_name, true)
    on conflict (id) do nothing;

    update public.user_invitation
       set user_id = p_user_id, completed_at = now(), updated_at = now()
     where id = v_inv.id;
end;
$$;
revoke execute on function public.fn_complete_invitation(uuid, uuid) from public, anon, authenticated;
grant execute on function public.fn_complete_invitation(uuid, uuid) to service_role;
