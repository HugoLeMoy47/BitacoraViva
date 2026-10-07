-- ==============================================================================
-- Etiqueta de entorno (demo / production)
--
-- Una sola fuente de verdad en la base para tres usos:
--  1. La interfaz muestra que es una DEMO (y oculta el acceso rapido con cuentas
--     de demostracion fuera de ella).
--  2. El script de reinicio de demo se niega a correr si el entorno no es 'demo'.
--  3. Sin fila = 'production': el valor seguro por omision. 'demo' solo lo
--     escribe supabase/seed.sql, que nunca se ejecuta en produccion.
--
-- Ningun rol de aplicacion puede leer ni escribir la tabla; la lectura es por
-- funcion, que expone unicamente el texto del entorno.
-- ==============================================================================

create table if not exists public.app_config (
    key text primary key,
    value text not null,
    updated_at timestamptz not null default now()
);

alter table public.app_config enable row level security;
revoke all on public.app_config from anon, authenticated;

create or replace function public.fn_app_environment()
returns text
stable
security definer
set search_path = public
language sql as $$
    select coalesce((select value from public.app_config where key = 'environment'), 'production');
$$;

revoke execute on function public.fn_app_environment() from public;
grant execute on function public.fn_app_environment() to anon, authenticated;
