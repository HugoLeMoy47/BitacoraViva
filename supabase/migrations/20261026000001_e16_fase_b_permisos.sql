-- ==============================================================================
-- E16 fase B · Permisos como datos (por rol y por área)
--
-- Contexto: quién puede qué estaba escrito en las funciones de la base por nombre de rol o de área (más de cien
-- comprobaciones). Decisión del Product Owner (23 oct 2026): solo la dirección gestiona el equipo **con la capacidad
-- configurable para delegar**; **migrar solo cinco capacidades y dejar el resto como deuda D-24**; una pantalla «Equipo y
-- permisos» con dos pestañas.
--
-- Cómo
--  * `capability`: catálogo de capacidades (código estable). Cinco: `manage_catalogs`, `manage_team`, `view_audit`,
--    `manage_authority_requests` y `manage_org_settings`.
--  * `capability_grant`: concesiones por organización, a un **rol** o a un **área** (esta última vale para quien tiene un rol
--    operativo —dirección, ingreso o atención— en esa área). Revocar cierra la concesión con motivo; nada se borra.
--  * `has_capability(código)`: verdadero si la cuenta activa tiene un rol o un área con esa concesión. **Salvaguarda:** si la
--    organización no tiene ninguna concesión vigente de una capacidad, aplica la dirección (nunca se queda bloqueada).
--  * Por omisión (`fn_seed_default_capabilities`) todo queda **como estaba**: dirección tiene las cinco y el área de Trabajo
--    Social tiene `manage_catalogs`.
--  * Se migran las comprobaciones de las cinco capacidades: `can_manage_catalogs()`, `can_manage_team()`, la lectura de la
--    auditoría (política de `audit_event` y la verificación de la cadena), los requerimientos de autoridad (políticas) y la
--    configuración de la organización (identidad, aviso de privacidad, textos de consentimiento y ajustes de seguridad).
--  * **Cambiar permisos es siempre y solo de la dirección** (`fn_grant_capability`, `fn_revoke_capability`): delegar la
--    gestión del equipo no permite escalar privilegios.
--  * Lo no migrado sigue funcionando exactamente como hoy (D-24). La compartimentación de la bitácora no se vuelve
--    configurable: es una garantía del producto, no un permiso de administración.
--  * Errores con código estable: BV349 a BV353.
--
-- Idempotente: el reinicio de la demo reaplica todas las migraciones.
-- ==============================================================================

-- ---------------------------------------------------------------- 1. Catálogo y concesiones
create table if not exists public.capability (
    code text primary key,
    description_es text not null,
    sort_order integer not null default 0
);
insert into public.capability (code, description_es, sort_order) values
    ('manage_catalogs', 'Administrar los diccionarios editables (listas de opciones)', 1),
    ('manage_team', 'Gestionar el equipo: otorgar y revocar roles, desactivar y reactivar cuentas', 2),
    ('view_audit', 'Consultar el registro de auditoría', 3),
    ('manage_authority_requests', 'Administrar los requerimientos de autoridad', 4),
    ('manage_org_settings', 'Configurar la organización (identidad, aviso de privacidad, consentimientos y seguridad)', 5)
on conflict (code) do update set description_es = excluded.description_es, sort_order = excluded.sort_order;

alter table public.capability enable row level security;
revoke all on public.capability from anon;
revoke insert, update, delete on public.capability from authenticated;
drop policy if exists capability_select on public.capability;
create policy capability_select on public.capability for select to authenticated using (true);

create table if not exists public.capability_grant (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    capability_code text not null references public.capability(code),
    role_name text references public.role(name),
    area_id uuid references public.area(id),
    granted_by uuid references public.user_profile(id),
    granted_at timestamptz not null default now(),
    grant_reason text,
    revoked_by uuid references public.user_profile(id),
    revoked_at timestamptz,
    revoke_reason text,
    check ((role_name is null) <> (area_id is null))
);
create unique index if not exists uq_capability_grant_role on public.capability_grant (organization_id, capability_code, role_name) where role_name is not null and revoked_at is null;
create unique index if not exists uq_capability_grant_area on public.capability_grant (organization_id, capability_code, area_id) where area_id is not null and revoked_at is null;
create index if not exists idx_capability_grant_org on public.capability_grant (organization_id, capability_code) where revoked_at is null;

alter table public.capability_grant enable row level security;
revoke all on public.capability_grant from anon;
revoke insert, update, delete on public.capability_grant from authenticated;
drop policy if exists capability_grant_select on public.capability_grant;
drop trigger if exists trg_audit_capability_grant on public.capability_grant;
create trigger trg_audit_capability_grant after insert or update on public.capability_grant
for each row execute function public.fn_audit_trigger_fields();

-- ---------------------------------------------------------------- 2. ¿Tiene la cuenta esta capacidad?
create or replace function public.has_capability(p_code text)
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select exists (select 1 from public.user_profile up where up.id = auth.uid() and up.active)
       and exists (select 1 from public.capability c where c.code = p_code)
       and (
           exists (
               select 1 from public.capability_grant g
               where g.organization_id = public.current_organization_id() and g.capability_code = p_code and g.revoked_at is null
                 and (
                     (g.role_name is not null and exists (
                         select 1 from public.user_role ur
                         where ur.user_id = auth.uid() and ur.revoked_at is null and ur.role_name = g.role_name))
                     or
                     (g.area_id is not null and exists (
                         select 1 from public.user_role ur
                         where ur.user_id = auth.uid() and ur.revoked_at is null and ur.area_id = g.area_id
                           and ur.role_name in ('director', 'intake_officer', 'caseworker')))
                 )
           )
           -- Salvaguarda: sin ninguna concesión vigente de la capacidad en la organización, aplica la dirección
           or (
               not exists (
                   select 1 from public.capability_grant g
                   where g.organization_id = public.current_organization_id() and g.capability_code = p_code and g.revoked_at is null
               )
               and public.has_role('director')
           )
       );
$$;
revoke execute on function public.has_capability(text) from public, anon;
grant execute on function public.has_capability(text) to authenticated;

-- Valores por omisión: todo como estaba (dirección tiene las cinco; el área de Trabajo Social, la de diccionarios)
create or replace function public.fn_seed_default_capabilities(p_org uuid)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_code text;
    v_ts uuid;
begin
    foreach v_code in array array['manage_catalogs', 'manage_team', 'view_audit', 'manage_authority_requests', 'manage_org_settings'] loop
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

-- Quién ve las concesiones: la dirección (siempre) y quien gestiona el equipo
create policy capability_grant_select on public.capability_grant for select to authenticated
    using (organization_id = public.current_organization_id() and (public.has_role('director') or public.has_capability('manage_team')));

-- ---------------------------------------------------------------- 3. Las dos capacidades que ya tenían función
create or replace function public.can_manage_catalogs()
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select public.has_capability('manage_catalogs');
$$;

create or replace function public.can_manage_team()
returns boolean
stable
security definer
set search_path = public
language sql as $$
    select public.has_capability('manage_team');
$$;

-- Las capacidades de la cuenta que consulta (la interfaz decide con ellas qué pantallas ofrece; la base las vuelve a exigir)
create or replace function public.fn_my_capabilities()
returns text[]
stable
security definer
set search_path = public
language sql as $$
    select coalesce(array_agg(c.code order by c.sort_order), '{}'::text[]) from public.capability c where public.has_capability(c.code);
$$;
revoke execute on function public.fn_my_capabilities() from public, anon;
grant execute on function public.fn_my_capabilities() to authenticated;

-- ---------------------------------------------------------------- 4. Cambiar permisos: siempre y solo la dirección
create or replace function public.fn_grant_capability(p_capability_code text, p_role_name text, p_area_id uuid, p_reason text default null)
returns uuid
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_org uuid := public.current_organization_id();
    v_id uuid;
begin
    if v_user is null or v_org is null or not public.has_role('director') then
        raise exception 'Acceso denegado: cambiar los permisos es solo de la dirección.' using errcode = 'BV353';
    end if;
    if p_capability_code is null or not exists (select 1 from public.capability where code = p_capability_code) then
        raise exception 'Esa capacidad no existe.' using errcode = 'BV349';
    end if;
    if (p_role_name is null) = (p_area_id is null)
       or (p_role_name is not null and not exists (select 1 from public.role where name = p_role_name))
       or (p_area_id is not null and not exists (select 1 from public.area where id = p_area_id and organization_id = v_org and active)) then
        raise exception 'Indica un rol o un área válidos (uno solo) de esta organización.' using errcode = 'BV350';
    end if;
    if exists (
        select 1 from public.capability_grant g
        where g.organization_id = v_org and g.capability_code = p_capability_code and g.revoked_at is null
          and ((p_role_name is not null and g.role_name = p_role_name) or (p_area_id is not null and g.area_id = p_area_id))
    ) then
        raise exception 'Esa capacidad ya está concedida a ese rol o área.' using errcode = 'BV351';
    end if;
    insert into public.capability_grant (organization_id, capability_code, role_name, area_id, granted_by, grant_reason)
    values (v_org, p_capability_code, p_role_name, p_area_id, v_user, nullif(btrim(coalesce(p_reason, '')), ''))
    returning id into v_id;
    return v_id;
end;
$$;
revoke execute on function public.fn_grant_capability(text, text, uuid, text) from public, anon;
grant execute on function public.fn_grant_capability(text, text, uuid, text) to authenticated;

create or replace function public.fn_revoke_capability(p_grant_id uuid, p_reason text)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_user uuid := auth.uid();
    v_org uuid := public.current_organization_id();
    v_row record;
begin
    if v_user is null or v_org is null or not public.has_role('director') then
        raise exception 'Acceso denegado: cambiar los permisos es solo de la dirección.' using errcode = 'BV353';
    end if;
    select * into v_row from public.capability_grant where id = p_grant_id and organization_id = v_org and revoked_at is null;
    if v_row.id is null then
        raise exception 'Esa concesión no existe o ya no está vigente.' using errcode = 'BV352';
    end if;
    if p_reason is null or btrim(p_reason) = '' then
        raise exception 'El motivo es obligatorio al cambiar o quitar un dato ya registrado (Ethos C8).' using errcode = 'BV304';
    end if;
    update public.capability_grant set revoked_at = now(), revoked_by = v_user, revoke_reason = btrim(p_reason) where id = v_row.id;
end;
$$;
revoke execute on function public.fn_revoke_capability(uuid, text) from public, anon;
grant execute on function public.fn_revoke_capability(uuid, text) to authenticated;

-- ---------------------------------------------------------------- 5. Auditoría, requerimientos de autoridad y configuración
-- Políticas (antes `has_role('director')`)
drop policy if exists "Solo directores leen auditoría de su organización" on public.audit_event;
create policy "Solo directores leen auditoría de su organización" on public.audit_event for select to authenticated
    using (organization_id = public.current_organization_id() and (select public.has_capability('view_audit')));

drop policy if exists "Solo directores leen requerimientos de autoridad" on public.authority_request;
create policy "Solo directores leen requerimientos de autoridad" on public.authority_request for select to authenticated
    using (organization_id = public.current_organization_id() and (select public.has_capability('manage_authority_requests')));

drop policy if exists "Solo directores gestionan requerimientos de autoridad" on public.authority_request;
create policy "Solo directores gestionan requerimientos de autoridad" on public.authority_request for all to authenticated
    using (organization_id = public.current_organization_id() and (select public.has_capability('manage_authority_requests')))
    with check (organization_id = public.current_organization_id() and (select public.has_capability('manage_authority_requests')));

-- Funciones: se redefinen a partir de las definiciones vigentes; solo cambia la comprobación de permiso

CREATE OR REPLACE FUNCTION public.fn_update_organization_identity(p_display_name text, p_legal_name text, p_folio_prefix text, p_about_text text, p_responsible_name text, p_responsible_address text, p_responsible_contact text, p_arco_contact text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_org uuid;
    v_prefix text;
begin
    if auth.uid() is null or not public.has_capability('manage_org_settings') then
        raise exception 'Acceso denegado: solo la dirección configura la organización.' using errcode = 'BV109';
    end if;
    v_org := public.current_organization_id();
    if v_org is null then
        raise exception 'Acceso denegado: sin organización.' using errcode = 'BV102';
    end if;
    if coalesce(btrim(p_display_name), '') = '' or coalesce(btrim(p_legal_name), '') = '' then
        raise exception 'El nombre y la razón social son obligatorios.' using errcode = 'BV317';
    end if;
    v_prefix := nullif(upper(btrim(coalesce(p_folio_prefix, ''))), '');
    if v_prefix is not null and v_prefix !~ '^[A-Z]{2,5}$' then
        raise exception 'El prefijo del folio debe tener de 2 a 5 letras (A–Z).' using errcode = 'BV318';
    end if;

    update public.organization set
        display_name = btrim(p_display_name),
        legal_name = btrim(p_legal_name),
        folio_prefix = v_prefix,
        about_text = nullif(btrim(coalesce(p_about_text, '')), ''),
        responsible_name = nullif(btrim(coalesce(p_responsible_name, '')), ''),
        responsible_address = nullif(btrim(coalesce(p_responsible_address, '')), ''),
        responsible_contact = nullif(btrim(coalesce(p_responsible_contact, '')), ''),
        arco_contact = nullif(btrim(coalesce(p_arco_contact, '')), ''),
        updated_at = now()
    where id = v_org;

    -- La auditoría la escribe el disparador trg_audit_organization (un evento por cambio, con antes y después).

    return v_org;
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_publish_privacy_notice(p_title text, p_summary text, p_full_text text, p_effective_date date DEFAULT CURRENT_DATE)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_org uuid;
    v_n int;
    v_version text;
    v_prev uuid;
    v_id uuid;
begin
    if auth.uid() is null or not public.has_capability('manage_org_settings') then
        raise exception 'Acceso denegado: solo la dirección publica el aviso de privacidad.' using errcode = 'BV108';
    end if;
    v_org := public.current_organization_id();
    if v_org is null then
        raise exception 'Acceso denegado: sin organización.' using errcode = 'BV102';
    end if;
    if coalesce(btrim(p_title), '') = '' or coalesce(btrim(p_summary), '') = '' or coalesce(btrim(p_full_text), '') = '' then
        raise exception 'El título, el resumen y el texto completo del aviso son obligatorios.' using errcode = 'BV315';
    end if;
    if p_effective_date is null or p_effective_date > current_date then
        raise exception 'La vigencia no puede ser una fecha futura: el aviso entra en vigor al publicarse.' using errcode = 'BV316';
    end if;

    select count(*) + 1 into v_n from public.privacy_notice where organization_id = v_org;
    v_version := v_n::text || '.0';
    select id into v_prev from public.privacy_notice where organization_id = v_org and active order by created_at desc limit 1;

    update public.privacy_notice set active = false where organization_id = v_org and active;

    insert into public.privacy_notice (organization_id, version, title, summary, full_text, effective_date, active)
    values (v_org, v_version, btrim(p_title), btrim(p_summary), btrim(p_full_text), p_effective_date, true)
    returning id into v_id;

    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_org, auth.uid(), 'INSERT', 'privacy_notice', v_id,
            jsonb_build_object('version', v_version, 'replaces', v_prev, 'effective_date', p_effective_date));

    return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_publish_consent_text(p_consent_type text, p_title text, p_description text, p_required boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_org uuid;
    v_version int;
    v_prev uuid;
    v_id uuid;
begin
    if auth.uid() is null or not public.has_capability('manage_org_settings') then
        raise exception 'Acceso denegado: solo la dirección define los textos de consentimiento.' using errcode = 'BV107';
    end if;
    v_org := public.current_organization_id();
    if v_org is null then
        raise exception 'Acceso denegado: sin organización.' using errcode = 'BV102';
    end if;
    if p_consent_type is null or p_consent_type not in ('general_care', 'sensitive_data', 'internal_sharing', 'secondary_use_research') then
        raise exception 'Tipo de consentimiento no válido.' using errcode = 'BV210';
    end if;
    if coalesce(btrim(p_title), '') = '' or coalesce(btrim(p_description), '') = '' then
        raise exception 'El título y la descripción del consentimiento son obligatorios.' using errcode = 'BV313';
    end if;
    if p_consent_type = 'general_care' and coalesce(p_required, false) is not true then
        raise exception 'El consentimiento general es obligatorio y no puede configurarse como opcional.' using errcode = 'BV314';
    end if;

    select coalesce(max(version), 0) + 1 into v_version from public.consent_text
    where organization_id = v_org and consent_type = p_consent_type;
    select id into v_prev from public.consent_text
    where organization_id = v_org and consent_type = p_consent_type and active order by version desc limit 1;

    update public.consent_text set active = false
    where organization_id = v_org and consent_type = p_consent_type and active;

    insert into public.consent_text (organization_id, consent_type, version, title, description, required, active, created_by)
    values (v_org, p_consent_type, v_version, btrim(p_title), btrim(p_description), coalesce(p_required, false), true, auth.uid())
    returning id into v_id;

    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_org, auth.uid(), 'INSERT', 'consent_text', v_id,
            jsonb_build_object('consent_type', p_consent_type, 'version', v_version, 'required', coalesce(p_required, false), 'replaces', v_prev));

    return v_id;
end;
$function$;

create or replace function public.fn_update_organization_security_settings(
    p_enforce_absolute_session_timeout boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_org uuid;
    v_old boolean;
begin
    if auth.uid() is null or not public.has_capability('manage_org_settings') then
        raise exception 'Acceso denegado: solo la dirección configura la organización.' using errcode = 'BV109';
    end if;

    v_org := public.current_organization_id();
    if v_org is null then
        raise exception 'Acceso denegado: sin organización.' using errcode = 'BV102';
    end if;

    select enforce_absolute_session_timeout into v_old
    from public.organization
    where id = v_org;

    update public.organization
    set enforce_absolute_session_timeout = p_enforce_absolute_session_timeout,
        updated_at = now()
    where id = v_org;

    insert into public.audit_event (
        organization_id, user_id, action, table_name, record_id, old_values, new_values
    ) values (
        v_org,
        auth.uid(),
        'UPDATE',
        'organization',
        v_org,
        jsonb_build_object('enforce_absolute_session_timeout', v_old),
        jsonb_build_object('enforce_absolute_session_timeout', p_enforce_absolute_session_timeout)
    );

    return v_org;
end;
$$;

create or replace function public.fn_verify_audit_chain(p_org_id uuid default null)
returns table (
    organization_id uuid,
    total_events bigint,
    is_valid boolean,
    broken_at_seq bigint,
    reason text
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_target_org uuid;
    v_prev text := 'GENESIS_0000000000000000000000000000000000000000000000000000000000000000';
    v_expected text;
    r record;
    v_count bigint := 0;
begin
    if auth.uid() is null or not public.has_capability('view_audit') then
        raise exception 'Acceso denegado: solo la dirección configura la organización.' using errcode = 'BV109';
    end if;

    v_target_org := coalesce(p_org_id, public.current_organization_id());
    if v_target_org is null then
        raise exception 'Acceso denegado: sin organización.' using errcode = 'BV102';
    end if;

    for r in select ae.id, ae.seq, ae.organization_id, ae.user_id, ae.action, ae.table_name, ae.record_id, ae.new_values, ae.created_at, ae.prev_hash, ae.event_hash
             from public.audit_event ae
             where ae.organization_id = v_target_org
             order by ae.seq asc loop
        v_count := v_count + 1;

        if r.prev_hash is distinct from v_prev then
            return query select v_target_org, v_count, false, r.seq, 'Ruptura de enlace: prev_hash no coincide con el hash anterior'::text;
            return;
        end if;

        v_expected := encode(
            extensions.digest(
                concat_ws('|',
                    r.prev_hash,
                    r.organization_id::text,
                    coalesce(r.user_id::text, 'system'),
                    r.action,
                    r.table_name,
                    coalesce(r.record_id::text, ''),
                    coalesce(r.new_values::text, ''),
                    to_char(r.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
                )::bytea,
                'sha256'
            ),
            'hex'
        );

        if r.event_hash is distinct from v_expected then
            return query select v_target_org, v_count, false, r.seq, 'Ruptura de integridad: contenido alterado'::text;
            return;
        end if;

        v_prev := r.event_hash;
    end loop;

    return query select v_target_org, v_count, true, null::bigint, 'Cadena íntegra'::text;
end;
$$;
