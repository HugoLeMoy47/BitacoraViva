-- ==============================================================================
-- Endurecimiento de privilegios (Reglas Duras 3 y 4)
-- Supabase otorga por defecto todos los privilegios sobre public a anon y
-- authenticated. RLS y disparadores ya bloqueaban DELETE/UPDATE, pero la regla
-- exige que el privilegio no exista. TRUNCATE ademas omite RLS y los
-- disparadores por fila, por lo que tambien se revoca.
-- ==============================================================================

-- Regla 3: ningun rol de aplicacion tiene DELETE ni TRUNCATE sobre tablas de negocio
revoke delete, truncate on all tables in schema public from anon, authenticated;

-- Regla 4: audit_event es append-only para todos
revoke update, delete, truncate on public.audit_event from anon, authenticated;

-- Tablas futuras no heredan estos privilegios
alter default privileges in schema public revoke delete, truncate on tables from anon, authenticated;
