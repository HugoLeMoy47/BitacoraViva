-- ==============================================================================
-- Reinicio de DEMO — Bitácora Viva
--
-- NO es una migracion ni se ejecuta desde la aplicacion. Lo corre una persona
-- operadora con acceso administrativo al proyecto (npm run demo:reset), seguido de
-- supabase/seed.sql, para dejar la demo en su estado inicial antes de una
-- presentacion.
--
-- Por que fuera de la aplicacion: borra tablas que las Reglas Duras 3 y 4 protegen
-- (sin DELETE para roles de aplicacion; audit_event append-only). Ninguna funcion
-- que alcance un rol de aplicacion puede hacer esto, y asi se mantiene.
--
-- Salvaguarda: se aborta si el entorno no es 'demo' (public.app_config). En un
-- proyecto sin esa fila el entorno es 'production' y este script no hace nada.
-- Efecto colateral aceptado: se pierde el historial de auditoria de la demo.
-- ==============================================================================

do $$
begin
    if public.fn_app_environment() <> 'demo' then
        raise exception 'Reinicio abortado: el entorno es "%" y solo se reinicia un entorno "demo".', public.fn_app_environment();
    end if;
end $$;

-- Datos de negocio. Se conservan: role (catalogo fijo de la migracion) y app_config.
truncate table
    public.arco_request,
    public.attachment,
    public.sharing_event,
    public.journal_entry,
    public.consent,
    public.consent_text,
    public.privacy_notice,
    public.case_vulnerability_marker,
    public.case_status,
    public."case",
    public.person,
    public.authority_request,
    public.audit_event,
    public.user_role,
    public.user_profile,
    public.status_value,
    public.status_axis,
    public.area,
    public.organization
restart identity cascade;

-- Cuentas de demostracion (las vuelve a crear seed.sql)
delete from auth.users where email like '%@alberguesantafe.org';
