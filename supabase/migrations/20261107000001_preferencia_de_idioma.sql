-- Idioma de la interfaz: preferencia por persona (español por defecto; inglés como primer idioma adicional).
-- La preferencia vive en el perfil y viaja con la cuenta. Como `user_profile` ya no admite escritura directa
-- (D-20), cada persona la cambia por esta función, que solo toca su propia fila. La auditoría la genera el
-- disparador de `user_profile` (Regla Dura 5).

alter table public.user_profile
    add column if not exists ui_locale text not null default 'es';

alter table public.user_profile drop constraint if exists user_profile_ui_locale_check;
alter table public.user_profile
    add constraint user_profile_ui_locale_check check (ui_locale in ('es', 'en'));

create or replace function public.fn_set_my_locale(p_locale text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user uuid := auth.uid();
begin
    if v_user is null or public.current_organization_id() is null then
        raise exception 'Tu sesión no tiene un rol vigente.' using errcode = 'BV101';
    end if;
    if p_locale is null or p_locale not in ('es', 'en') then
        raise exception 'Ese idioma no está disponible.' using errcode = 'BV372';
    end if;
    update public.user_profile set ui_locale = p_locale, updated_at = now() where id = v_user;
end;
$$;
revoke execute on function public.fn_set_my_locale(text) from public, anon;
grant execute on function public.fn_set_my_locale(text) to authenticated;
