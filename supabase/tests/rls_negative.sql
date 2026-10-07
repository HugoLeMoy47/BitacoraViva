-- ==============================================================================
-- Pruebas negativas de RLS y Reglas Duras (Definition of Done del handoff §4)
--
-- "Demostrar que lo prohibido está efectivamente prohibido."
--
-- Autocontenidas: crean su propio escenario (dos organizaciones, usuarios de cada
-- rol, un usuario sin rol, expedientes, bitácora, consentimientos y auditoría) y
-- terminan SIEMPRE con un error deliberado, de modo que la transaccion completa se
-- revierte y no queda nada en la base. Corren contra cualquier entorno.
--
--   npm run test:rls
--
-- Cada prueba se ejecuta con la identidad real (claims JWT + SET ROLE) de un rol de
-- aplicacion, igual que PostgREST.
-- ==============================================================================

begin;

-- ---------------------------------------------------------------- Escenario
-- Org A (la que se prueba) y org B (ajena)
insert into public.organization (id, slug, legal_name, display_name, active) values
    ('aaaaaaaa-0000-0000-0000-00000000000a', 'tst-a', 'Org A de prueba', 'Org A', true),
    ('bbbbbbbb-0000-0000-0000-00000000000b', 'tst-b', 'Org B de prueba', 'Org B', true);

insert into public.area (id, organization_id, code, name, active) values
    ('aaaaaaaa-1000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', 'trabajo_social', 'TS A', true),
    ('aaaaaaaa-1000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-00000000000a', 'legal', 'Legal A', true),
    ('bbbbbbbb-1000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-00000000000b', 'trabajo_social', 'TS B', true);

-- Eje y valores de estatus en A (el disparador inicial los usa al abrir un caso)
insert into public.status_axis (id, organization_id, code, label_es, is_primary, is_system, sort_order) values
    ('aaaaaaaa-2000-0000-0000-000000000005', 'aaaaaaaa-0000-0000-0000-00000000000a', 'case_stage', 'Etapa', false, true, 5),
    ('aaaaaaaa-2000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-00000000000a', 'engagement_status', 'Situación', true, true, 2),
    ('aaaaaaaa-2000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-00000000000a', 'record_status', 'Estado', false, true, 4);
insert into public.status_value (id, axis_id, organization_id, code, label_es, sort_order, is_system) values
    ('aaaaaaaa-2100-0000-0000-000000000001', 'aaaaaaaa-2000-0000-0000-000000000005', 'aaaaaaaa-0000-0000-0000-00000000000a', 'intake', 'Ingreso', 1, true),
    ('aaaaaaaa-2100-0000-0000-000000000002', 'aaaaaaaa-2000-0000-0000-000000000005', 'aaaaaaaa-0000-0000-0000-00000000000a', 'assessment', 'Valoración', 2, false),
    -- Ejes y valores que necesita la anonimizacion (estatus terminal 'anonymized')
    ('aaaaaaaa-2100-0000-0000-000000000011', 'aaaaaaaa-2000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-00000000000a', 'first_contact', 'Primer contacto', 1, true),
    ('aaaaaaaa-2100-0000-0000-000000000012', 'aaaaaaaa-2000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-00000000000a', 'anonymized', 'Anonimizada', 9, true),
    ('aaaaaaaa-2100-0000-0000-000000000021', 'aaaaaaaa-2000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-00000000000a', 'open', 'Abierto', 1, true),
    ('aaaaaaaa-2100-0000-0000-000000000022', 'aaaaaaaa-2000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-00000000000a', 'anonymized', 'Anonimizado', 4, true);

-- Usuarios: director, caseworker (área TS), intake, viewer y SIN ROL en A; director de B
insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
select u.id::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', u.email, now(), now()
from (values
    ('aaaaaaaa-3000-0000-0000-000000000001', 'dir@tst-a.invalid'),
    ('aaaaaaaa-3000-0000-0000-000000000002', 'cw@tst-a.invalid'),
    ('aaaaaaaa-3000-0000-0000-000000000003', 'in@tst-a.invalid'),
    ('aaaaaaaa-3000-0000-0000-000000000004', 'vw@tst-a.invalid'),
    ('aaaaaaaa-3000-0000-0000-000000000005', 'nr@tst-a.invalid'),
    ('bbbbbbbb-3000-0000-0000-000000000001', 'dir@tst-b.invalid')
) as u(id, email);

insert into public.user_profile (id, organization_id, email, full_name, active) values
    ('aaaaaaaa-3000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', 'dir@tst-a.invalid', 'Dir A', true),
    ('aaaaaaaa-3000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-00000000000a', 'cw@tst-a.invalid', 'Cw A', true),
    ('aaaaaaaa-3000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-00000000000a', 'in@tst-a.invalid', 'In A', true),
    ('aaaaaaaa-3000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-00000000000a', 'vw@tst-a.invalid', 'Vw A', true),
    ('aaaaaaaa-3000-0000-0000-000000000005', 'aaaaaaaa-0000-0000-0000-00000000000a', 'nr@tst-a.invalid', 'Sin rol A', true),
    ('bbbbbbbb-3000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-00000000000b', 'dir@tst-b.invalid', 'Dir B', true);

insert into public.user_role (user_id, role_name, area_id, granted_by, granted_at) values
    ('aaaaaaaa-3000-0000-0000-000000000001', 'director', null, 'aaaaaaaa-3000-0000-0000-000000000001', now()),
    ('aaaaaaaa-3000-0000-0000-000000000002', 'caseworker', 'aaaaaaaa-1000-0000-0000-000000000001', 'aaaaaaaa-3000-0000-0000-000000000001', now()),
    ('aaaaaaaa-3000-0000-0000-000000000003', 'intake_officer', null, 'aaaaaaaa-3000-0000-0000-000000000001', now()),
    ('aaaaaaaa-3000-0000-0000-000000000004', 'viewer', null, 'aaaaaaaa-3000-0000-0000-000000000001', now()),
    ('bbbbbbbb-3000-0000-0000-000000000001', 'director', null, 'bbbbbbbb-3000-0000-0000-000000000001', now());

-- Personas, casos, bitácora, compartición y consentimientos
insert into public.person (id, organization_id, given_name, paternal_family_name, birth_date) values
    ('aaaaaaaa-4000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', 'Ana', 'PruebaA', '1990-01-01'),
    ('bbbbbbbb-4000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-00000000000b', 'Beto', 'PruebaB', '1990-01-01');

insert into public."case" (id, organization_id, case_number, titular_person_id, opened_by, assigned_user_id) values
    ('aaaaaaaa-5000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', 'TST-A-0001', 'aaaaaaaa-4000-0000-0000-000000000001', 'aaaaaaaa-3000-0000-0000-000000000003', 'aaaaaaaa-3000-0000-0000-000000000002'),
    ('bbbbbbbb-5000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-00000000000b', 'TST-B-0001', 'bbbbbbbb-4000-0000-0000-000000000001', 'bbbbbbbb-3000-0000-0000-000000000001', 'bbbbbbbb-3000-0000-0000-000000000001');

insert into public.journal_entry (id, organization_id, case_id, area_id, author_user_id, entry_type_key, body, is_work_note, visibility) values
    ('aaaaaaaa-6000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', 'aaaaaaaa-5000-0000-0000-000000000001', 'aaaaaaaa-1000-0000-0000-000000000001', 'aaaaaaaa-3000-0000-0000-000000000002', 'note', 'Entrada A privada', false, 'area_private'),
    ('aaaaaaaa-6000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-00000000000a', 'aaaaaaaa-5000-0000-0000-000000000001', 'aaaaaaaa-1000-0000-0000-000000000001', 'aaaaaaaa-3000-0000-0000-000000000002', 'note', 'Entrada A compartida', false, 'shared'),
    ('bbbbbbbb-6000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-00000000000b', 'bbbbbbbb-5000-0000-0000-000000000001', 'bbbbbbbb-1000-0000-0000-000000000001', 'bbbbbbbb-3000-0000-0000-000000000001', 'note', 'Entrada B', false, 'area_private');

insert into public.sharing_event (id, organization_id, journal_entry_id, case_id, from_area_id, to_area_id, from_visibility, to_visibility, reason, shared_by_user_id, shared_at) values
    ('aaaaaaaa-7000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', 'aaaaaaaa-6000-0000-0000-000000000002', 'aaaaaaaa-5000-0000-0000-000000000001',
     'aaaaaaaa-1000-0000-0000-000000000001', 'aaaaaaaa-1000-0000-0000-000000000002', 'area_private', 'shared', 'Prueba', 'aaaaaaaa-3000-0000-0000-000000000002', now());

insert into public.consent (id, organization_id, person_id, case_id, consent_type, status, granted_by_user_id) values
    ('aaaaaaaa-8000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', 'aaaaaaaa-4000-0000-0000-000000000001', 'aaaaaaaa-5000-0000-0000-000000000001', 'general_care', 'granted', 'aaaaaaaa-3000-0000-0000-000000000003'),
    ('bbbbbbbb-8000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-00000000000b', 'bbbbbbbb-4000-0000-0000-000000000001', 'bbbbbbbb-5000-0000-0000-000000000001', 'general_care', 'granted', 'bbbbbbbb-3000-0000-0000-000000000001');

-- ---------------------------------------------------------------- Pruebas
create temp table test_res (verdict text, name text, expected text, actual text);
grant all on test_res to authenticated, anon;

-- Ejecuta una sentencia con la identidad de un rol de aplicacion. Devuelve la primera
-- columna del resultado como texto, o 'ERR:<sqlstate>' si la base la rechaza.
create or replace function pg_temp.run_as(p_uid text, p_role text, p_sql text)
returns text language plpgsql as $$
declare v text;
begin
    if p_role is not null then
        perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_role)::text, true);
        execute format('set local role %I', p_role);
    end if;
    begin
        execute p_sql into v;
    exception when others then
        if p_role is not null then execute 'reset role'; end if;
        return 'ERR:' || sqlstate || ':' || left(replace(sqlerrm, E'
', ' '), 70);
    end;
    if p_role is not null then execute 'reset role'; end if;
    return coalesce(v, 'NULL');
end $$;

-- Expectativas: '0', '1', '>0' (positivo), 'ERR' (cualquier rechazo), 'OK' (sin rechazo),
-- 'a|b' (cualquiera de las dos), o un valor literal.
create or replace function pg_temp.expect(p_name text, p_uid text, p_role text, p_sql text, p_expected text)
returns void language plpgsql as $$
declare
    a text := pg_temp.run_as(p_uid, p_role, p_sql);
    ok boolean := false;
    alt text;
begin
    foreach alt in array string_to_array(p_expected, '|') loop
        ok := ok or case alt
            when 'ERR' then a like 'ERR:%'
            when 'OK'  then a not like 'ERR:%'
            when '>0'  then a not like 'ERR:%' and a ~ '^[0-9]+$' and a::bigint > 0
            else a = alt end;
    end loop;
    insert into test_res values (case when ok then 'PASS' else 'FAIL' end, p_name, p_expected, a);
end $$;

do $do$
declare
    DIR  constant text := 'aaaaaaaa-3000-0000-0000-000000000001';
    CW   constant text := 'aaaaaaaa-3000-0000-0000-000000000002';
    INT  constant text := 'aaaaaaaa-3000-0000-0000-000000000003';
    VW   constant text := 'aaaaaaaa-3000-0000-0000-000000000004';
    NR   constant text := 'aaaaaaaa-3000-0000-0000-000000000005';
    DIRB constant text := 'bbbbbbbb-3000-0000-0000-000000000001';
    ORG_A constant text := 'aaaaaaaa-0000-0000-0000-00000000000a';
    ORG_B constant text := 'bbbbbbbb-0000-0000-0000-00000000000b';
    t text;
    new_case text := $nc$select count(*)::text from (select public.fn_create_case_with_person(
        'Nuevo','Caso',null,null,date '2000-01-01',false,1,93,'Honduras',1,null,null,'fija',false,9,1,1,3,null,
        'aaaaaaaa-1000-0000-0000-000000000001'::uuid, array[]::text[])) x$nc$;
    report text;
begin
    -- ===== Aislamiento por organización (BV-1.1): ni una fila de otra organización
    foreach t in array array['person','"case"','case_status','journal_entry','sharing_event','consent','arco_request','audit_event'] loop
        perform pg_temp.expect('aislamiento: director A no ve ' || t || ' de B', DIR, 'authenticated',
            format('select count(*)::text from public.%s where organization_id = %L', t, ORG_B), '0');
        perform pg_temp.expect('aislamiento: director B no ve ' || t || ' de A', DIRB, 'authenticated',
            format('select count(*)::text from public.%s where organization_id = %L', t, ORG_A), '0');
    end loop;
    perform pg_temp.expect('aislamiento: caseworker A no ve consent de B', CW, 'authenticated',
        format('select count(*)::text from public.consent where organization_id = %L', ORG_B), '0');
    perform pg_temp.expect('control positivo: director A sí ve su persona', DIR, 'authenticated',
        'select count(*)::text from public.person', '1');

    -- ===== Viewer: sin datos identificables, solo indicadores agregados (E-05)
    foreach t in array array['person','"case"','case_status','case_vulnerability_marker','journal_entry','sharing_event','consent','arco_request','attachment','privacy_notice'] loop
        perform pg_temp.expect('viewer no ve ' || t, VW, 'authenticated', format('select count(*)::text from public.%s', t), '0');
    end loop;
    perform pg_temp.expect('control positivo: viewer ve áreas (catálogo)', VW, 'authenticated', 'select count(*)::text from public.area', '>0');
    perform pg_temp.expect('control positivo: viewer obtiene indicadores agregados', VW, 'authenticated',
        'select jsonb_array_length(public.fn_aggregate_metrics()->''rows'')::text', 'OK');
    perform pg_temp.expect('viewer no puede abrir casos', VW, 'authenticated', new_case, 'ERR');

    -- ===== Usuario con perfil pero sin rol vigente (BV-1.2): no ve nada
    foreach t in array array['person','"case"','journal_entry','consent','area','status_axis','status_value','organization'] loop
        perform pg_temp.expect('sin rol no ve ' || t, NR, 'authenticated', format('select count(*)::text from public.%s', t), '0');
    end loop;
    perform pg_temp.expect('sin rol: indicadores agregados denegados', NR, 'authenticated', 'select public.fn_aggregate_metrics()::text', 'ERR');

    -- ===== Fronteras entre roles
    perform pg_temp.expect('caseworker no abre casos', CW, 'authenticated', new_case, 'ERR');
    perform pg_temp.expect('control positivo: intake sí abre casos', INT, 'authenticated', new_case, '1');
    foreach t in array array[CW, INT, VW, NR] loop
        perform pg_temp.expect('solo dirección lee auditoría (' || right(t, 1) || ')', t, 'authenticated', 'select count(*)::text from public.audit_event', '0');
    end loop;
    perform pg_temp.expect('control positivo: director lee auditoría', DIR, 'authenticated', 'select count(*)::text from public.audit_event', '>0');
    perform pg_temp.expect('solo dirección lee requerimientos de autoridad', CW, 'authenticated', 'select count(*)::text from public.authority_request', '0');
    perform pg_temp.expect('caseworker no acusa recibo del digest', CW, 'authenticated',
        'select count(*)::text from (select public.fn_acknowledge_sharing(''aaaaaaaa-7000-0000-0000-000000000001''::uuid)) x', 'ERR');
    perform pg_temp.expect('caseworker no anonimiza', CW, 'authenticated',
        'select count(*)::text from (select public.fn_anonymize_person(''aaaaaaaa-4000-0000-0000-000000000001''::uuid, ''x'')) x', 'ERR');
    perform pg_temp.expect('intake no anonimiza', INT, 'authenticated',
        'select count(*)::text from (select public.fn_anonymize_person(''aaaaaaaa-4000-0000-0000-000000000001''::uuid, ''x'')) x', 'ERR');
    perform pg_temp.expect('caseworker no emite extracto ARCO', CW, 'authenticated',
        'select public.fn_generate_arco_access_extract(''aaaaaaaa-4000-0000-0000-000000000001''::uuid)::text', 'ERR');
    perform pg_temp.expect('caseworker no rectifica datos de la persona', CW, 'authenticated',
        'select count(*)::text from (select public.fn_rectify_person(''aaaaaaaa-4000-0000-0000-000000000001''::uuid,''A'',''B'',null,null,date ''1990-01-01'',false,1,1,null,null,''x'')) x', 'ERR');
    perform pg_temp.expect('control positivo: director acusa recibo', DIR, 'authenticated',
        'select count(*)::text from (select public.fn_acknowledge_sharing(''aaaaaaaa-7000-0000-0000-000000000001''::uuid)) x', '1');
    perform pg_temp.expect('control positivo: director emite extracto ARCO', DIR, 'authenticated',
        'select jsonb_array_length(public.fn_generate_arco_access_extract(''aaaaaaaa-4000-0000-0000-000000000001''::uuid)->''cases'')::text', '1');

    -- ===== Funciones que se saltan RLS (security definer): cada una repite la regla de acceso.
    -- Escribir exige sesión, rol operativo y que el registro sea de la propia organización.
    foreach t in array array[
        'select public.fn_register_consent(''aaaaaaaa-4000-0000-0000-000000000001''::uuid, ''general_care'')::text',
        'select public.fn_create_journal_entry(''aaaaaaaa-5000-0000-0000-000000000001''::uuid, ''note'', ''x'', now(), false, ''aaaaaaaa-1000-0000-0000-000000000001''::uuid)::text',
        'select public.fn_create_clarification_note(''aaaaaaaa-6000-0000-0000-000000000001''::uuid, ''x'')::text',
        'select public.fn_share_journal_entry(''aaaaaaaa-6000-0000-0000-000000000001''::uuid, ''aaaaaaaa-1000-0000-0000-000000000002''::uuid, ''x'')::text',
        'select public.fn_change_case_status(''aaaaaaaa-5000-0000-0000-000000000001''::uuid, ''case_stage'', ''assessment'', ''x'')::text'
    ] loop
        perform pg_temp.expect('anon no ejecuta ' || split_part(split_part(t, 'public.', 2), '(', 1), null, 'anon', t, 'ERR');
        perform pg_temp.expect('viewer no ejecuta ' || split_part(split_part(t, 'public.', 2), '(', 1), VW, 'authenticated', t, 'ERR');
        perform pg_temp.expect('sin rol no ejecuta ' || split_part(split_part(t, 'public.', 2), '(', 1), NR, 'authenticated', t, 'ERR');
        perform pg_temp.expect('director de otra organización no ejecuta ' || split_part(split_part(t, 'public.', 2), '(', 1), DIRB, 'authenticated', t, 'ERR');
    end loop;

    perform pg_temp.expect('control positivo: intake registra consentimiento', INT, 'authenticated',
        'select count(*)::text from (select public.fn_register_consent(''aaaaaaaa-4000-0000-0000-000000000001''::uuid, ''internal_sharing'')) x', '1');
    perform pg_temp.expect('control positivo: caseworker escribe en bitácora', CW, 'authenticated',
        'select count(*)::text from (select public.fn_create_journal_entry(''aaaaaaaa-5000-0000-0000-000000000001''::uuid, ''note'', ''x'', now(), false, ''aaaaaaaa-1000-0000-0000-000000000001''::uuid)) x', '1');

    -- ===== Regla Dura 3: nadie tiene DELETE sobre tablas de negocio
    foreach t in array array['person','"case"','case_status','case_vulnerability_marker','journal_entry','sharing_event','consent','arco_request','audit_event','user_role','user_profile','organization','area'] loop
        perform pg_temp.expect('DELETE denegado a director en ' || t, DIR, 'authenticated',
            format('with d as (delete from public.%s returning 1) select count(*)::text from d', t), 'ERR');
    end loop;
    perform pg_temp.expect('sin privilegios DELETE/TRUNCATE para anon/authenticated', null, null,
        $q$select count(*)::text from information_schema.role_table_grants
           where table_schema = 'public' and privilege_type in ('DELETE','TRUNCATE') and grantee in ('anon','authenticated')$q$, '0');

    -- ===== Regla Dura 4: audit_event append-only para todos
    perform pg_temp.expect('director no actualiza audit_event', DIR, 'authenticated',
        'with u as (update public.audit_event set action = ''LOGIN'' returning 1) select count(*)::text from u', 'ERR');
    perform pg_temp.expect('director no inserta audit_event a mano', DIR, 'authenticated',
        format('with i as (insert into public.audit_event (organization_id, action, table_name) values (%L, ''INSERT'', ''x'') returning 1) select count(*)::text from i', ORG_A), 'ERR');
    perform pg_temp.expect('sin privilegios UPDATE/DELETE/TRUNCATE sobre audit_event', null, null,
        $q$select count(*)::text from information_schema.role_table_grants
           where table_schema = 'public' and table_name = 'audit_event'
             and privilege_type in ('UPDATE','DELETE','TRUNCATE') and grantee in ('anon','authenticated')$q$, '0');
    perform pg_temp.expect('disparador: ni el propietario actualiza audit_event', null, null,
        'with u as (update public.audit_event set action = ''LOGIN'' returning 1) select count(*)::text from u', 'ERR');
    perform pg_temp.expect('disparador: ni el propietario borra audit_event', null, null,
        'with d as (delete from public.audit_event returning 1) select count(*)::text from d', 'ERR');

    -- ===== Regla Dura 6: la bitácora nace area_private y no se edita ni se borra
    perform pg_temp.expect('journal_entry nace area_private por defecto de columna', null, null,
        format($q$with i as (insert into public.journal_entry (organization_id, case_id, area_id, author_user_id, entry_type_key, body)
                  values (%L, 'aaaaaaaa-5000-0000-0000-000000000001', 'aaaaaaaa-1000-0000-0000-000000000001', %L, 'note', 'x') returning visibility)
                  select visibility from i$q$, ORG_A, CW), 'area_private');
    perform pg_temp.expect('autor no edita su entrada de bitácora', CW, 'authenticated',
        'with u as (update public.journal_entry set body = ''editado'' where id = ''aaaaaaaa-6000-0000-0000-000000000001'' returning 1) select count(*)::text from u', 'ERR|0');
    perform pg_temp.expect('autor no borra su entrada de bitácora', CW, 'authenticated',
        'with d as (delete from public.journal_entry where id = ''aaaaaaaa-6000-0000-0000-000000000001'' returning 1) select count(*)::text from d', 'ERR');
    perform pg_temp.expect('disparador: ni el propietario borra bitácora', null, null,
        'with d as (delete from public.journal_entry returning 1) select count(*)::text from d', 'ERR');

    -- ===== Regla Dura 7: el estatus no se sobrescribe, se cierra y se abre uno nuevo
    perform pg_temp.expect('caseworker no sobrescribe el estatus vigente', CW, 'authenticated',
        $q$with u as (update public.case_status set value_id = 'aaaaaaaa-2100-0000-0000-000000000002'
                      where case_id = 'aaaaaaaa-5000-0000-0000-000000000001' and valid_to is null returning 1)
           select count(*)::text from u$q$, 'ERR|0');
    perform pg_temp.expect('control positivo: cambio de estatus por función', CW, 'authenticated',
        'select count(*)::text from (select public.fn_change_case_status(''aaaaaaaa-5000-0000-0000-000000000001''::uuid, ''case_stage'', ''assessment'', ''Prueba'')) x', '1');
    perform pg_temp.expect('tras el cambio hay un solo estatus vigente en el eje', null, null,
        $q$select count(*)::text from public.case_status
           where case_id = 'aaaaaaaa-5000-0000-0000-000000000001' and axis_id = 'aaaaaaaa-2000-0000-0000-000000000005' and valid_to is null$q$, '1');
    perform pg_temp.expect('el estatus anterior se conserva (historial)', null, null,
        $q$select count(*)::text from public.case_status
           where case_id = 'aaaaaaaa-5000-0000-0000-000000000001' and axis_id = 'aaaaaaaa-2000-0000-0000-000000000005'$q$, '2');

    perform pg_temp.expect('disparador: ni el propietario sobrescribe un estatus', null, null,
        $q$with u as (update public.case_status set reason = 'x' where case_id = 'aaaaaaaa-5000-0000-0000-000000000001' and valid_to is null returning 1)
           select count(*)::text from u$q$, 'ERR');
    perform pg_temp.expect('disparador: un estatus cerrado es inmutable', null, null,
        $q$with u as (update public.case_status set valid_to = now() + interval '1 day' where case_id = 'aaaaaaaa-5000-0000-0000-000000000001' and valid_to is not null returning 1)
           select count(*)::text from u$q$, 'ERR');

    -- ===== Anónimo: nada
    perform pg_temp.expect('anon no lee personas', null, 'anon', 'select count(*)::text from public.person', 'ERR|0');
    perform pg_temp.expect('anon no abre casos', null, 'anon', new_case, 'ERR');
    perform pg_temp.expect('anon no lee app_config', null, 'anon', 'select count(*)::text from public.app_config', 'ERR');
    perform pg_temp.expect('authenticated no lee app_config', DIR, 'authenticated', 'select count(*)::text from public.app_config', 'ERR');
    perform pg_temp.expect('control positivo: anon consulta el entorno por función', null, 'anon', 'select public.fn_app_environment()', 'demo|production');

    -- ===== Ultima: la anonimización es exclusiva de dirección y funciona (irreversible, en transacción de prueba)
    perform pg_temp.expect('control positivo: director anonimiza', DIR, 'authenticated',
        'select count(*)::text from (select public.fn_anonymize_person(''aaaaaaaa-4000-0000-0000-000000000001''::uuid, ''Prueba'')) x', '1');

    select string_agg(verdict || '^' || name || '^' || expected || '^' || actual, E'\n' order by verdict desc, name)
      into report from test_res;
    raise exception E'RLS_RESULTS\n%', report;
end
$do$;
