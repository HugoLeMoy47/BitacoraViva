-- ==============================================================================
-- Configuración de la organización (épica E9: BV-9.1, BV-9.2, BV-9.3)
--
-- Principio: la plataforma ofrece el MECANISMO (versionado, evidencia, bloqueo en la
-- base, auditoría); la asociación declara el CONTENIDO y responde por su cumplimiento.
--
--  1. Identidad: la organización declara nombre, responsable, domicilio, contacto ARCO,
--     «acerca de» y el prefijo de sus folios. Solo la dirección la modifica, por función.
--  2. Aviso de privacidad: versionado y de solo agregar. Publicar una versión nueva
--     desactiva la anterior; nada se edita ni se borra. Solo la dirección publica.
--  3. Textos de consentimiento: por tipo, versionados, con obligatoriedad. El consentimiento
--     general sigue siendo obligatorio (BV-5.1): la asociación define el texto, no puede
--     suprimirlo. Cada consentimiento registra el texto con el que se otorgó.
--
-- Reglas Duras: toda función security definer repite la regla de acceso (sesión, rol de
-- dirección, organización); ejecutable solo por authenticated; sin UPDATE/DELETE directos.
-- ==============================================================================

-- ---------------------------------------------------------------- 1. Identidad
alter table public.organization
    add column if not exists folio_prefix text,
    add column if not exists about_text text,
    add column if not exists responsible_name text,
    add column if not exists responsible_address text,
    add column if not exists responsible_contact text,
    add column if not exists arco_contact text;

alter table public.organization drop constraint if exists organization_folio_prefix_check;
alter table public.organization add constraint organization_folio_prefix_check
    check (folio_prefix is null or folio_prefix ~ '^[A-Z]{2,5}$');

-- El demo declara el prefijo que ya usa su semilla
update public.organization set folio_prefix = 'ASF' where slug = 'albergue-santa-fe' and folio_prefix is null;

-- El prefijo declarado manda; si no hay, se deriva del slug como hasta ahora
create or replace function public.fn_generate_case_number(p_org_id uuid)
returns text
language plpgsql as $$
declare
    v_slug text;
    v_declared text;
    v_prefix text;
    v_year text;
    v_seq int;
begin
    select slug, folio_prefix into v_slug, v_declared from public.organization where id = p_org_id;
    v_prefix := coalesce(v_declared, case when v_slug is null then 'BV' else upper(substring(v_slug from 1 for 3)) end);
    v_year := to_char(now(), 'YYYY');
    select count(*) + 1 into v_seq from public.case where organization_id = p_org_id;
    return v_prefix || '-' || v_year || '-' || lpad(v_seq::text, 4, '0');
end;
$$;

revoke update on public.organization from authenticated;

create or replace function public.fn_update_organization_identity(
    p_display_name text,
    p_legal_name text,
    p_folio_prefix text,
    p_about_text text,
    p_responsible_name text,
    p_responsible_address text,
    p_responsible_contact text,
    p_arco_contact text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_org uuid;
    v_old jsonb;
    v_prefix text;
begin
    if auth.uid() is null or not public.has_role('director') then
        raise exception 'Acceso denegado: solo la dirección configura la organización.';
    end if;
    v_org := public.current_organization_id();
    if v_org is null then
        raise exception 'Acceso denegado: sin organización.';
    end if;
    if coalesce(btrim(p_display_name), '') = '' or coalesce(btrim(p_legal_name), '') = '' then
        raise exception 'El nombre y la razón social son obligatorios.';
    end if;
    v_prefix := nullif(upper(btrim(coalesce(p_folio_prefix, ''))), '');
    if v_prefix is not null and v_prefix !~ '^[A-Z]{2,5}$' then
        raise exception 'El prefijo del folio debe tener de 2 a 5 letras (A–Z).';
    end if;

    select to_jsonb(o) - 'created_at' - 'updated_at' into v_old from public.organization o where id = v_org;

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

    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, old_values, new_values)
    select v_org, auth.uid(), 'UPDATE', 'organization', v_org, v_old, to_jsonb(o) - 'created_at' - 'updated_at'
    from public.organization o where id = v_org;

    return v_org;
end;
$$;

-- ------------------------------------------------- Versionado de solo agregar (común)
-- Una versión publicada no se edita: lo único que cambia es `active` (true → false) al publicar la siguiente.
create or replace function public.fn_versioned_row_guard()
returns trigger
language plpgsql as $$
begin
    if tg_op = 'DELETE' then
        raise exception 'Violación de integridad: las versiones publicadas son inmutables y no se eliminan (Reglas Duras 2 y 3).';
    end if;
    if (to_jsonb(new) - 'active') is distinct from (to_jsonb(old) - 'active') or not (old.active and not new.active) then
        raise exception 'Violación de integridad: una versión publicada no se edita; se publica una nueva (Ethos C7).';
    end if;
    return new;
end;
$$;

-- ---------------------------------------------------------------- 2. Aviso de privacidad
drop policy if exists "privacy_notice_insert_policy" on public.privacy_notice;
drop policy if exists "privacy_notice_update_policy" on public.privacy_notice;
revoke insert, update on public.privacy_notice from authenticated;

drop trigger if exists trg_privacy_notice_guard on public.privacy_notice;
create trigger trg_privacy_notice_guard
before update on public.privacy_notice
for each row execute function public.fn_versioned_row_guard();

create or replace function public.fn_publish_privacy_notice(
    p_title text,
    p_summary text,
    p_full_text text,
    p_effective_date date default current_date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_org uuid;
    v_n int;
    v_version text;
    v_prev uuid;
    v_id uuid;
begin
    if auth.uid() is null or not public.has_role('director') then
        raise exception 'Acceso denegado: solo la dirección publica el aviso de privacidad.';
    end if;
    v_org := public.current_organization_id();
    if v_org is null then
        raise exception 'Acceso denegado: sin organización.';
    end if;
    if coalesce(btrim(p_title), '') = '' or coalesce(btrim(p_summary), '') = '' or coalesce(btrim(p_full_text), '') = '' then
        raise exception 'El título, el resumen y el texto completo del aviso son obligatorios.';
    end if;
    if p_effective_date is null or p_effective_date > current_date then
        raise exception 'La vigencia no puede ser una fecha futura: el aviso entra en vigor al publicarse.';
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
$$;

-- ---------------------------------------------------------------- 3. Textos de consentimiento
create table if not exists public.consent_text (
    id uuid primary key default gen_random_uuid(),
    organization_id uuid not null references public.organization(id),
    consent_type text not null check (consent_type in (
        'general_care', 'sensitive_data', 'internal_sharing', 'secondary_use_research'
    )),
    version int not null,
    title text not null,
    description text not null,
    required boolean not null default false,
    active boolean not null default true,
    created_by uuid references auth.users(id),
    created_at timestamptz not null default now(),
    unique (organization_id, consent_type, version),
    -- El consentimiento general es siempre obligatorio (BV-5.1): no se puede configurar hacia abajo
    check (consent_type <> 'general_care' or required)
);
create index if not exists idx_consent_text_org on public.consent_text (organization_id, consent_type, active);

alter table public.consent_text enable row level security;
revoke all on public.consent_text from anon;
revoke insert, update, delete on public.consent_text from authenticated;
grant select on public.consent_text to authenticated;

drop policy if exists consent_text_select_policy on public.consent_text;
create policy consent_text_select_policy on public.consent_text for select to authenticated
    using (organization_id = public.current_organization_id() and public.has_operational_role());

drop trigger if exists trg_consent_text_guard on public.consent_text;
create trigger trg_consent_text_guard
before update or delete on public.consent_text
for each row execute function public.fn_versioned_row_guard();

alter table public.consent add column if not exists consent_text_id uuid references public.consent_text(id);

-- Cada consentimiento nuevo registra el texto vigente con el que se otorgó
create or replace function public.fn_consent_stamp_text()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.consent_text_id is null then
        select id into new.consent_text_id
        from public.consent_text
        where organization_id = new.organization_id and consent_type = new.consent_type and active
        order by version desc limit 1;
    end if;
    return new;
end;
$$;

drop trigger if exists trg_consent_stamp_text on public.consent;
create trigger trg_consent_stamp_text
before insert on public.consent
for each row execute function public.fn_consent_stamp_text();

create or replace function public.fn_publish_consent_text(
    p_consent_type text,
    p_title text,
    p_description text,
    p_required boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_org uuid;
    v_version int;
    v_prev uuid;
    v_id uuid;
begin
    if auth.uid() is null or not public.has_role('director') then
        raise exception 'Acceso denegado: solo la dirección define los textos de consentimiento.';
    end if;
    v_org := public.current_organization_id();
    if v_org is null then
        raise exception 'Acceso denegado: sin organización.';
    end if;
    if p_consent_type is null or p_consent_type not in ('general_care', 'sensitive_data', 'internal_sharing', 'secondary_use_research') then
        raise exception 'Tipo de consentimiento no válido.';
    end if;
    if coalesce(btrim(p_title), '') = '' or coalesce(btrim(p_description), '') = '' then
        raise exception 'El título y la descripción del consentimiento son obligatorios.';
    end if;
    if p_consent_type = 'general_care' and coalesce(p_required, false) is not true then
        raise exception 'El consentimiento general es obligatorio y no puede configurarse como opcional.';
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
$$;

-- ---------------------------------------------------------------- Permisos de ejecución
revoke execute on function public.fn_update_organization_identity(text, text, text, text, text, text, text, text) from public, anon;
revoke execute on function public.fn_publish_privacy_notice(text, text, text, date) from public, anon;
revoke execute on function public.fn_publish_consent_text(text, text, text, boolean) from public, anon;
revoke execute on function public.fn_consent_stamp_text() from public, anon, authenticated;
revoke execute on function public.fn_versioned_row_guard() from public, anon;
grant execute on function public.fn_update_organization_identity(text, text, text, text, text, text, text, text) to authenticated;
grant execute on function public.fn_publish_privacy_notice(text, text, text, date) to authenticated;
grant execute on function public.fn_publish_consent_text(text, text, text, boolean) to authenticated;
