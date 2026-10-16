-- ==============================================================================
-- D-24 tanda 1 · Limpieza de las políticas de escritura inertes
--
-- Contexto: varias tablas de negocio solo se escriben por funciones `security definer` (la API directa no tiene permiso de
-- INSERT ni de UPDATE). Sus políticas de escritura por nombre de rol nunca se evalúan: el permiso se niega antes. Dejarlas
-- engaña a quien lee el esquema (parece que dirección o ingreso escriben directo) y cuenta como deuda D-24 sin decidir nada.
--
-- Qué hace: quita, en esas tablas, todas las políticas que no son de lectura. No cambia ningún comportamiento: la escritura
-- directa sigue rechazada (por permiso y, ahora, también por ausencia de política: si algún día se concediera el permiso por
-- error, RLS la negaría igualmente). Las políticas de lectura no se tocan.
--
-- No se tocan las tablas de administración que sí se escriben directo (`area`, `status_axis`, `status_value`,
-- `case_task_kind`): son la tanda 2.
-- ==============================================================================

do $$
declare
    pol record;
begin
    for pol in
        select schemaname, tablename, policyname
        from pg_policies
        where schemaname = 'public'
          and tablename in ('user_role', 'user_profile', 'person', 'case', 'case_status', 'case_vulnerability_marker',
                            'consent', 'arco_request', 'journal_entry', 'privacy_notice', 'organization')
          and cmd <> 'SELECT'
    loop
        execute format('drop policy %I on %I.%I', pol.policyname, pol.schemaname, pol.tablename);
    end loop;
end $$;
