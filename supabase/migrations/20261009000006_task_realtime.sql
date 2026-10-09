-- ==============================================================================
-- Seguidor de tareas (E7) · Fase 2: tiempo real en el tablero
--
-- Publica `task` en Supabase Realtime para que el tablero de quien coordina refleje al instante que
-- una persona marcó una tarea como en curso o hecha, sin recargar la página (BV-7.6).
--
-- No abre ningún dato nuevo: Realtime (postgres_changes) evalúa RLS con la identidad de cada
-- suscriptor, así que cada persona recibe únicamente los cambios de las tareas que ya puede leer
-- (la gestión, todas las de su organización; el resto, las suyas y el pool). Sin esta publicación la
-- pantalla sigue funcionando: se relee cada minuto y al volver a la pestaña.
--
-- Idempotente: no hace nada si la publicación no existe o ya incluye la tabla.
-- ==============================================================================

do $$
begin
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
       and not exists (
            select 1 from pg_publication_tables
            where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'task'
       ) then
        alter publication supabase_realtime add table public.task;
    end if;
end $$;
