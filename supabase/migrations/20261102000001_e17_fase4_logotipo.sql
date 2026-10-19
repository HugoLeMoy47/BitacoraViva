-- ==============================================================================
-- E17 fase 4 · Logotipo de la organización (paga la parte del logotipo de D-16)
--
-- Contexto: la organización no podía personalizar la aplicación con su logotipo. Decisión del Product Owner (24 oct 2026, «de
-- acuerdo con tus recomendaciones»): PNG, JPG o WebP de hasta 1 MB, **sin SVG** (un SVG puede llevar código), visible en el
-- encabezado de la aplicación (el inicio de sesión sigue con la marca de Bitácora Viva: antes de entrar no se sabe a qué
-- organización pertenece quien llega).
--
-- Cómo
--  * Bucket `org-assets`: **público** (el logotipo no es un dato sensible), 1 MB y solo `image/png`, `image/jpeg` e
--    `image/webp`. La ruta lleva la organización y un identificador al azar (`<organización>/logo-<id>.<png|jpg|webp>`).
--  * Política de subida: solo a la carpeta de la propia organización, con ese nombre exacto y con el permiso de configurar la
--    organización (`manage_org_settings`). **No hay política de cambio ni de borrado:** cada logotipo es un archivo nuevo y el
--    anterior se conserva («nada se borra»).
--  * `organization.logo_path`: cuál es el logotipo vigente. Solo se fija con `fn_set_organization_logo` (BV109 sin permiso;
--    BV366 si la ruta no es de la organización, está mal formada o el archivo no existe) y se quita con
--    `fn_clear_organization_logo`. El cambio queda en la auditoría por el disparador de la organización.
--  * Lo que **no** cubre: subir el PDF del aviso de privacidad (la otra mitad de D-16).
-- ==============================================================================

-- ---------------------------------------------------------------- 1. Bucket y política de subida
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('org-assets', 'org-assets', true, 1048576, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update
    set public = true,
        file_size_limit = 1048576,
        allowed_mime_types = array['image/png', 'image/jpeg', 'image/webp'];

drop policy if exists org_assets_logo_insert on storage.objects;
create policy org_assets_logo_insert on storage.objects
    for insert to authenticated
    with check (
        bucket_id = 'org-assets'
        and (storage.foldername(storage.objects.name))[1] = public.current_organization_id()::text
        and storage.objects.name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/logo-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|jpg|webp)$'
        and public.has_capability('manage_org_settings')
    );

-- ---------------------------------------------------------------- 2. El logotipo vigente
alter table public.organization add column if not exists logo_path text;

create or replace function public.fn_set_organization_logo(p_path text)
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_org uuid := public.current_organization_id();
begin
    if auth.uid() is null or v_org is null or not public.has_capability('manage_org_settings') then
        raise exception 'Acceso denegado: solo la dirección configura la organización.' using errcode = 'BV109';
    end if;
    if p_path is null
       or p_path !~ ('^' || v_org::text || '/logo-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|jpg|webp)$')
       or not exists (select 1 from storage.objects o where o.bucket_id = 'org-assets' and o.name = p_path) then
        raise exception 'El logotipo no es válido: usa una imagen PNG, JPG o WebP de hasta 1 MB.' using errcode = 'BV366';
    end if;
    update public.organization set logo_path = p_path where id = v_org and logo_path is distinct from p_path;
end;
$$;
revoke execute on function public.fn_set_organization_logo(text) from public, anon;
grant execute on function public.fn_set_organization_logo(text) to authenticated;

create or replace function public.fn_clear_organization_logo()
returns void
security definer
set search_path = public
language plpgsql as $$
declare
    v_org uuid := public.current_organization_id();
begin
    if auth.uid() is null or v_org is null or not public.has_capability('manage_org_settings') then
        raise exception 'Acceso denegado: solo la dirección configura la organización.' using errcode = 'BV109';
    end if;
    update public.organization set logo_path = null where id = v_org and logo_path is not null;
end;
$$;
revoke execute on function public.fn_clear_organization_logo() from public, anon;
grant execute on function public.fn_clear_organization_logo() to authenticated;
