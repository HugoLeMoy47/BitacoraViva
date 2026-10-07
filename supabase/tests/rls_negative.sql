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
    ('aaaaaaaa-2000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-00000000000a', 'record_status', 'Estado', false, true, 4),
    ('aaaaaaaa-2000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', 'legal_status', 'Jurídica', false, true, 1),
    ('bbbbbbbb-2000-0000-0000-000000000005', 'bbbbbbbb-0000-0000-0000-00000000000b', 'case_stage', 'Etapa B', false, true, 5);
insert into public.status_value (id, axis_id, organization_id, code, label_es, sort_order, is_system) values
    ('aaaaaaaa-2100-0000-0000-000000000001', 'aaaaaaaa-2000-0000-0000-000000000005', 'aaaaaaaa-0000-0000-0000-00000000000a', 'intake', 'Ingreso', 1, true),
    ('aaaaaaaa-2100-0000-0000-000000000002', 'aaaaaaaa-2000-0000-0000-000000000005', 'aaaaaaaa-0000-0000-0000-00000000000a', 'assessment', 'Valoración', 2, false),
    -- Ejes y valores que necesita la anonimizacion (estatus terminal 'anonymized')
    ('aaaaaaaa-2100-0000-0000-000000000011', 'aaaaaaaa-2000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-00000000000a', 'first_contact', 'Primer contacto', 1, true),
    ('aaaaaaaa-2100-0000-0000-000000000012', 'aaaaaaaa-2000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-00000000000a', 'anonymized', 'Anonimizada', 9, true),
    ('aaaaaaaa-2100-0000-0000-000000000021', 'aaaaaaaa-2000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-00000000000a', 'open', 'Abierto', 1, true),
    ('aaaaaaaa-2100-0000-0000-000000000022', 'aaaaaaaa-2000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-00000000000a', 'anonymized', 'Anonimizado', 4, true),
    ('aaaaaaaa-2100-0000-0000-000000000023', 'aaaaaaaa-2000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-00000000000a', 'closed', 'Cerrado', 3, true),
    -- legal_status: el disparador inicial usa 'undetermined'
    ('aaaaaaaa-2100-0000-0000-000000000031', 'aaaaaaaa-2000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', 'undetermined', 'Sin determinar', 1, true),
    ('aaaaaaaa-2100-0000-0000-000000000032', 'aaaaaaaa-2000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', 'asylum_seeker', 'Solicitante de asilo', 2, false),
    ('bbbbbbbb-2100-0000-0000-000000000001', 'bbbbbbbb-2000-0000-0000-000000000005', 'bbbbbbbb-0000-0000-0000-00000000000b', 'intake', 'Ingreso B', 1, true);

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

-- Datos de la organización B en las demás tablas, para que «no ver nada de B» sea una prueba real
insert into public.area (id, organization_id, code, name, active) values
    ('bbbbbbbb-1000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-00000000000b', 'legal', 'Legal B', true);
insert into public.journal_entry (id, organization_id, case_id, area_id, author_user_id, entry_type_key, body, is_work_note, visibility) values
    ('bbbbbbbb-6000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-00000000000b', 'bbbbbbbb-5000-0000-0000-000000000001', 'bbbbbbbb-1000-0000-0000-000000000001', 'bbbbbbbb-3000-0000-0000-000000000001', 'note', 'Entrada B compartida', false, 'shared');
insert into public.sharing_event (id, organization_id, journal_entry_id, case_id, from_area_id, to_area_id, from_visibility, to_visibility, reason, shared_by_user_id, shared_at) values
    ('bbbbbbbb-7000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-00000000000b', 'bbbbbbbb-6000-0000-0000-000000000002', 'bbbbbbbb-5000-0000-0000-000000000001',
     'bbbbbbbb-1000-0000-0000-000000000001', 'bbbbbbbb-1000-0000-0000-000000000002', 'area_private', 'shared', 'Prueba B', 'bbbbbbbb-3000-0000-0000-000000000001', now());
insert into public.arco_request (organization_id, person_id, case_id, request_type, status, details, reason, requested_by_name, is_legal_representative, received_at) values
    ('bbbbbbbb-0000-0000-0000-00000000000b', 'bbbbbbbb-4000-0000-0000-000000000001', 'bbbbbbbb-5000-0000-0000-000000000001', 'access', 'pending', 'Solicitud B', 'Prueba B', 'Beto PruebaB', false, now());
insert into public.case_vulnerability_marker (organization_id, case_id, marker_code, affirmed_by) values
    ('bbbbbbbb-0000-0000-0000-00000000000b', 'bbbbbbbb-5000-0000-0000-000000000001', 'victim_of_violence', 'bbbbbbbb-3000-0000-0000-000000000001');
insert into public.attachment (organization_id, case_id, journal_entry_id, storage_path, file_name, mime_type, size_bytes, uploaded_by) values
    ('bbbbbbbb-0000-0000-0000-00000000000b', 'bbbbbbbb-5000-0000-0000-000000000001', 'bbbbbbbb-6000-0000-0000-000000000001', 'tst-b/x.pdf', 'x.pdf', 'application/pdf', 1, 'bbbbbbbb-3000-0000-0000-000000000001');
insert into public.privacy_notice (organization_id, version, title, summary, full_text, effective_date, active) values
    ('bbbbbbbb-0000-0000-0000-00000000000b', '1.0', 'Aviso B', 'Resumen B', 'Texto B', current_date, true);
insert into public.authority_request (organization_id, authority_name, request_type, official_letter_ref, received_at, extract_delivered) values
    ('bbbbbbbb-0000-0000-0000-00000000000b', 'Autoridad B', 'Consulta', 'B/0001', now(), false);

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
        'aaaaaaaa-1000-0000-0000-000000000001'::uuid, array[]::text[], '[{"consent_type":"general_care"}]'::jsonb)) x$nc$;
    report text;
begin
    -- ===== Aislamiento por organización (BV-1.1): ni una fila de otra organización
    foreach t in array array['person','"case"','case_status','case_vulnerability_marker','journal_entry','sharing_event','consent','arco_request','attachment','privacy_notice','authority_request','audit_event','area','status_axis','status_value','user_profile'] loop
        perform pg_temp.expect('aislamiento: director A no ve ' || t || ' de B', DIR, 'authenticated',
            format('select count(*)::text from public.%s where organization_id = %L', t, ORG_B), '0');
        perform pg_temp.expect('aislamiento: director B no ve ' || t || ' de A', DIRB, 'authenticated',
            format('select count(*)::text from public.%s where organization_id = %L', t, ORG_A), '0');
        -- Control positivo: el director de B sí ve sus propias filas (demuestra que los datos de B existen)
        perform pg_temp.expect('control positivo: director B ve sus propias filas de ' || t, DIRB, 'authenticated',
            format('select count(*)::text from public.%s where organization_id = %L', t, ORG_B), '>0');
    end loop;
    perform pg_temp.expect('aislamiento: director A no ve la organización B', DIR, 'authenticated',
        format('select count(*)::text from public.organization where id = %L', ORG_B), '0');
    perform pg_temp.expect('aislamiento: director A no ve los roles de la organización B', DIR, 'authenticated',
        'select count(*)::text from public.user_role where user_id = ''bbbbbbbb-3000-0000-0000-000000000001''', '0');
    perform pg_temp.expect('aislamiento: director B no ve los roles de la organización A', DIRB, 'authenticated',
        'select count(*)::text from public.user_role where user_id = ''aaaaaaaa-3000-0000-0000-000000000001''', '0');
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
    -- Indicadores con periodo: la supresión n < 5 se mantiene y la lógica interna no es accesible
    perform pg_temp.expect('indicadores: con 1 caso ninguna cifra es visible (viewer)', VW, 'authenticated',
        $q$select count(*)::text from jsonb_array_elements(public.fn_aggregate_metrics(current_date - 90, current_date)->'rows') r
           where r->>'count' is not null or r->>'prev_count' is not null$q$, '0');
    perform pg_temp.expect('indicadores: periodo invertido se rechaza', VW, 'authenticated',
        'select public.fn_aggregate_metrics(current_date, current_date - 10)::text', 'ERR');
    perform pg_temp.expect('indicadores: anon no los consulta', null, 'anon', 'select public.fn_aggregate_metrics()::text', 'ERR');
    perform pg_temp.expect('indicadores: fn_metric_rows no es ejecutable por roles de aplicación', DIR, 'authenticated',
        format('select count(*)::text from public.fn_metric_rows(%L::uuid, null, null)', ORG_A), 'ERR');

    -- ===== Usuario con perfil pero sin rol vigente (BV-1.2): no ve nada
    foreach t in array array['person','"case"','journal_entry','consent','area','status_axis','status_value','organization'] loop
        perform pg_temp.expect('sin rol no ve ' || t, NR, 'authenticated', format('select count(*)::text from public.%s', t), '0');
    end loop;
    perform pg_temp.expect('sin rol: indicadores agregados denegados', NR, 'authenticated', 'select public.fn_aggregate_metrics()::text', 'ERR');

    -- ===== Fronteras entre roles
    perform pg_temp.expect('caseworker no abre casos', CW, 'authenticated', new_case, 'ERR');
    perform pg_temp.expect('control positivo: intake sí abre casos', INT, 'authenticated', new_case, '1');
    -- Paso cero: la base impone el consentimiento (BV-5.1, P-06, Ethos C2)
    perform pg_temp.expect('sin consentimiento general no se abre expediente', INT, 'authenticated',
        replace(new_case, '''[{"consent_type":"general_care"}]''', '''[]'''), 'ERR');
    perform pg_temp.expect('P-06: sin consentimiento sensible no hay marcadores de vulnerabilidad', INT, 'authenticated',
        replace(new_case, 'array[]::text[]', 'array[''victim_of_violence'']'), 'ERR');
    perform pg_temp.expect('control positivo: con consentimiento sensible sí hay marcadores', INT, 'authenticated',
        replace(replace(new_case, 'array[]::text[]', 'array[''victim_of_violence'']'),
                '''[{"consent_type":"general_care"}]''', '''[{"consent_type":"general_care"},{"consent_type":"sensitive_data"}]'''), '1');
    perform pg_temp.expect('persona menor de 18 sin asentimiento ni representante no se abre', INT, 'authenticated',
        replace(new_case, 'date ''2000-01-01''', 'current_date - 3000'), 'ERR');
    perform pg_temp.expect('control positivo: menor con asentimiento y representante', INT, 'authenticated',
        replace(replace(new_case, 'date ''2000-01-01''', 'current_date - 3000'), '''[{"consent_type":"general_care"}]''',
                '''[{"consent_type":"general_care","is_minor_assent":true,"legal_guardian_name":"Madre"}]'''), '1');
    perform pg_temp.expect('niñez no acompañada sin autoridad ni oficio no se abre', INT, 'authenticated',
        replace(replace(replace(new_case, 'date ''2000-01-01''', 'current_date - 3000'), 'array[]::text[]', 'array[''unaccompanied_child'']'),
                '''[{"consent_type":"general_care"}]''',
                '''[{"consent_type":"general_care","is_minor_assent":true,"legal_guardian_name":"Tutor"},{"consent_type":"sensitive_data"}]'''), 'ERR');
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

    -- ===== BV-2.3: compartimentación por área y gobernanza del cierre
    perform pg_temp.expect('caseworker de otra área no cambia el estatus jurídico', CW, 'authenticated',
        'select count(*)::text from (select public.fn_change_case_status(''aaaaaaaa-5000-0000-0000-000000000001''::uuid, ''legal_status'', ''asylum_seeker'', ''x'')) x', 'ERR');
    perform pg_temp.expect('intake no cierra el expediente', INT, 'authenticated',
        'select count(*)::text from (select public.fn_change_case_status(''aaaaaaaa-5000-0000-0000-000000000001''::uuid, ''record_status'', ''closed'', ''x'')) x', 'ERR');
    perform pg_temp.expect('caseworker no cierra el expediente', CW, 'authenticated',
        'select count(*)::text from (select public.fn_change_case_status(''aaaaaaaa-5000-0000-0000-000000000001''::uuid, ''record_status'', ''closed'', ''x'')) x', 'ERR');
    perform pg_temp.expect('control positivo: director cambia el estatus jurídico', DIR, 'authenticated',
        'select count(*)::text from (select public.fn_change_case_status(''aaaaaaaa-5000-0000-0000-000000000001''::uuid, ''legal_status'', ''asylum_seeker'', ''Prueba'')) x', '1');
    perform pg_temp.expect('control positivo: director cierra el expediente', DIR, 'authenticated',
        'select count(*)::text from (select public.fn_change_case_status(''aaaaaaaa-5000-0000-0000-000000000001''::uuid, ''record_status'', ''closed'', ''Prueba'')) x', '1');

    -- ===== BV-4.3: la visibilidad sólo cambia por sharing_event (nadie la edita directamente)
    perform pg_temp.expect('autor no cambia la visibilidad de su entrada directamente', CW, 'authenticated',
        'with u as (update public.journal_entry set visibility = ''shared'' where id = ''aaaaaaaa-6000-0000-0000-000000000001'' returning 1) select count(*)::text from u', 'ERR|0');

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

    -- ===== Configuración de la organización (E9): identidad, aviso de privacidad y textos de consentimiento
    perform pg_temp.expect('control positivo: director actualiza la identidad de su organización', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_update_organization_identity('Org A renombrada','Org A de prueba','ORA','Acerca de A','Resp A','Calle 1','a@a.invalid','arco@a.invalid')) x$q$, '1');
    perform pg_temp.expect('la identidad queda guardada', null, null,
        $q$select count(*)::text from public.organization where id = 'aaaaaaaa-0000-0000-0000-00000000000a' and display_name = 'Org A renombrada' and folio_prefix = 'ORA'$q$, '1');
    perform pg_temp.expect('la actualización de identidad deja auditoría', null, null,
        $q$select count(*)::text from public.audit_event where table_name = 'organization' and record_id = 'aaaaaaaa-0000-0000-0000-00000000000a' and action = 'UPDATE'$q$, '1');
    perform pg_temp.expect('el siguiente folio usa el prefijo declarado', null, null,
        $q$select split_part(public.fn_generate_case_number('aaaaaaaa-0000-0000-0000-00000000000a'), '-', 1)$q$, 'ORA');
    perform pg_temp.expect('el folio de B no cambia con el prefijo de A', null, null,
        $q$select split_part(public.fn_generate_case_number('bbbbbbbb-0000-0000-0000-00000000000b'), '-', 1)$q$, 'TST');
    perform pg_temp.expect('prefijo de folio inválido se rechaza', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_update_organization_identity('X','X','a1','','','','','')) x$q$, 'ERR');
    perform pg_temp.expect('nombre vacío se rechaza', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_update_organization_identity('  ','X','ORA','','','','','')) x$q$, 'ERR');
    perform pg_temp.expect('caseworker no configura la organización', CW, 'authenticated',
        $q$select count(*)::text from (select public.fn_update_organization_identity('Hack','Hack','HAK','','','','','')) x$q$, 'ERR');
    perform pg_temp.expect('oficial de ingreso no configura la organización', INT, 'authenticated',
        $q$select count(*)::text from (select public.fn_update_organization_identity('Hack','Hack','HAK','','','','','')) x$q$, 'ERR');
    perform pg_temp.expect('viewer no configura la organización', VW, 'authenticated',
        $q$select count(*)::text from (select public.fn_update_organization_identity('Hack','Hack','HAK','','','','','')) x$q$, 'ERR');
    perform pg_temp.expect('usuario sin rol no configura la organización', NR, 'authenticated',
        $q$select count(*)::text from (select public.fn_update_organization_identity('Hack','Hack','HAK','','','','','')) x$q$, 'ERR');
    perform pg_temp.expect('caseworker no publica aviso de privacidad', CW, 'authenticated',
        $q$select count(*)::text from (select public.fn_publish_privacy_notice('T','S','F', current_date)) x$q$, 'ERR');
    perform pg_temp.expect('oficial de ingreso no publica aviso de privacidad', INT, 'authenticated',
        $q$select count(*)::text from (select public.fn_publish_privacy_notice('T','S','F', current_date)) x$q$, 'ERR');
    perform pg_temp.expect('viewer no publica aviso de privacidad', VW, 'authenticated',
        $q$select count(*)::text from (select public.fn_publish_privacy_notice('T','S','F', current_date)) x$q$, 'ERR');
    perform pg_temp.expect('usuario sin rol no publica aviso de privacidad', NR, 'authenticated',
        $q$select count(*)::text from (select public.fn_publish_privacy_notice('T','S','F', current_date)) x$q$, 'ERR');
    perform pg_temp.expect('caseworker no publica textos de consentimiento', CW, 'authenticated',
        $q$select count(*)::text from (select public.fn_publish_consent_text('internal_sharing','T','D', false)) x$q$, 'ERR');
    perform pg_temp.expect('oficial de ingreso no publica textos de consentimiento', INT, 'authenticated',
        $q$select count(*)::text from (select public.fn_publish_consent_text('internal_sharing','T','D', false)) x$q$, 'ERR');
    perform pg_temp.expect('viewer no publica textos de consentimiento', VW, 'authenticated',
        $q$select count(*)::text from (select public.fn_publish_consent_text('internal_sharing','T','D', false)) x$q$, 'ERR');
    perform pg_temp.expect('anon no configura la organización', null, 'anon',
        $q$select count(*)::text from (select public.fn_update_organization_identity('Hack','Hack','HAK','','','','','')) x$q$, 'ERR');
    perform pg_temp.expect('anon no publica aviso de privacidad', null, 'anon',
        $q$select count(*)::text from (select public.fn_publish_privacy_notice('T','S','F', current_date)) x$q$, 'ERR');
    perform pg_temp.expect('anon no publica textos de consentimiento', null, 'anon',
        $q$select count(*)::text from (select public.fn_publish_consent_text('internal_sharing','T','D', false)) x$q$, 'ERR');
    perform pg_temp.expect('el director no cambia la organización con UPDATE directo', DIR, 'authenticated',
        $q$with u as (update public.organization set display_name = 'Directo' where id = 'aaaaaaaa-0000-0000-0000-00000000000a' returning 1) select count(*)::text from u$q$, 'ERR|0');
    perform pg_temp.expect('el director no inserta avisos con INSERT directo', DIR, 'authenticated',
        $q$with i as (insert into public.privacy_notice (organization_id, version, title, summary, full_text) values ('aaaaaaaa-0000-0000-0000-00000000000a','9.0','T','S','F') returning 1) select count(*)::text from i$q$, 'ERR');
    perform pg_temp.expect('el director no edita avisos con UPDATE directo', DIR, 'authenticated',
        $q$with u as (update public.privacy_notice set full_text = 'cambiado' where organization_id = 'aaaaaaaa-0000-0000-0000-00000000000a' returning 1) select count(*)::text from u$q$, 'ERR|0');
    perform pg_temp.expect('el director no inserta textos de consentimiento con INSERT directo', DIR, 'authenticated',
        $q$with i as (insert into public.consent_text (organization_id, consent_type, version, title, description) values ('aaaaaaaa-0000-0000-0000-00000000000a','internal_sharing',9,'T','D') returning 1) select count(*)::text from i$q$, 'ERR');

    perform pg_temp.expect('control positivo: director publica un aviso (versión nueva)', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_publish_privacy_notice('Aviso A','Resumen A','Texto completo A', current_date)) x$q$, '1');
    perform pg_temp.expect('publicar un segundo aviso', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_publish_privacy_notice('Aviso A v2','Resumen A2','Texto completo A2', current_date)) x$q$, '1');
    perform pg_temp.expect('solo un aviso vigente por organización', null, null,
        $q$select count(*)::text from public.privacy_notice where organization_id = 'aaaaaaaa-0000-0000-0000-00000000000a' and active$q$, '1');
    perform pg_temp.expect('los avisos anteriores se conservan (historial)', null, null,
        $q$select count(*)::text from public.privacy_notice where organization_id = 'aaaaaaaa-0000-0000-0000-00000000000a'$q$, '>0');
    perform pg_temp.expect('el aviso vigente es la última versión', null, null,
        $q$select title from public.privacy_notice where organization_id = 'aaaaaaaa-0000-0000-0000-00000000000a' and active$q$, 'Aviso A v2');
    perform pg_temp.expect('aviso con vigencia futura se rechaza', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_publish_privacy_notice('T','S','F', current_date + 5)) x$q$, 'ERR');
    perform pg_temp.expect('aviso con resumen vacío se rechaza', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_publish_privacy_notice('T','','F', current_date)) x$q$, 'ERR');
    perform pg_temp.expect('disparador: ni el propietario edita un aviso publicado', null, null,
        $q$with u as (update public.privacy_notice set full_text = 'cambiado' where organization_id = 'aaaaaaaa-0000-0000-0000-00000000000a' and active returning 1) select count(*)::text from u$q$, 'ERR');
    perform pg_temp.expect('disparador: ni el propietario reactiva un aviso reemplazado', null, null,
        $q$with u as (update public.privacy_notice set active = true where organization_id = 'aaaaaaaa-0000-0000-0000-00000000000a' and not active returning 1) select count(*)::text from u$q$, 'ERR');
    perform pg_temp.expect('la publicación del aviso deja auditoría', null, null,
        $q$select count(*)::text from public.audit_event where table_name = 'privacy_notice' and action = 'INSERT' and organization_id = 'aaaaaaaa-0000-0000-0000-00000000000a'$q$, '>0');
    perform pg_temp.expect('el director de B no ve los avisos de A', DIRB, 'authenticated',
        $q$select count(*)::text from public.privacy_notice where organization_id = 'aaaaaaaa-0000-0000-0000-00000000000a'$q$, '0');
    perform pg_temp.expect('control positivo: el director de B publica en su organización', DIRB, 'authenticated',
        $q$select count(*)::text from (select public.fn_publish_privacy_notice('Aviso B','Resumen B','Texto B', current_date)) x$q$, '1');
    perform pg_temp.expect('publicar en B no toca a A: conserva su único aviso vigente', null, null,
        $q$select count(*)::text from public.privacy_notice where organization_id = 'aaaaaaaa-0000-0000-0000-00000000000a' and active$q$, '1');

    perform pg_temp.expect('control positivo: director publica un texto de consentimiento', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_publish_consent_text('secondary_use_research','Uso secundario A','Texto de A', false)) x$q$, '1');
    perform pg_temp.expect('segunda versión del mismo consentimiento', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_publish_consent_text('secondary_use_research','Uso secundario A v2','Texto de A v2', true)) x$q$, '1');
    perform pg_temp.expect('un solo texto vigente por tipo', null, null,
        $q$select count(*)::text from public.consent_text where organization_id = 'aaaaaaaa-0000-0000-0000-00000000000a' and consent_type = 'secondary_use_research' and active$q$, '1');
    perform pg_temp.expect('las versiones del texto se conservan', null, null,
        $q$select count(*)::text from public.consent_text where organization_id = 'aaaaaaaa-0000-0000-0000-00000000000a' and consent_type = 'secondary_use_research'$q$, '2');
    perform pg_temp.expect('el consentimiento general no puede ser opcional', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_publish_consent_text('general_care','General','Texto', false)) x$q$, 'ERR');
    perform pg_temp.expect('control positivo: el general sí se publica como obligatorio', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_publish_consent_text('general_care','General A','Texto general A', true)) x$q$, '1');
    perform pg_temp.expect('tipo de consentimiento inválido se rechaza', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_publish_consent_text('otro','T','D', false)) x$q$, 'ERR');
    perform pg_temp.expect('disparador: ni el propietario edita un texto publicado', null, null,
        $q$with u as (update public.consent_text set description = 'x' where organization_id = 'aaaaaaaa-0000-0000-0000-00000000000a' and active returning 1) select count(*)::text from u$q$, 'ERR');
    perform pg_temp.expect('disparador: ni el propietario borra un texto publicado', null, null,
        $q$with d as (delete from public.consent_text where organization_id = 'aaaaaaaa-0000-0000-0000-00000000000a' returning 1) select count(*)::text from d$q$, 'ERR');
    perform pg_temp.expect('director B no ve los textos de consentimiento de A', DIRB, 'authenticated',
        $q$select count(*)::text from public.consent_text where organization_id = 'aaaaaaaa-0000-0000-0000-00000000000a'$q$, '0');
    perform pg_temp.expect('control positivo: caseworker A lee los textos vigentes de su organización', CW, 'authenticated',
        $q$select count(*)::text from public.consent_text where organization_id = 'aaaaaaaa-0000-0000-0000-00000000000a' and active$q$, '>0');
    perform pg_temp.expect('viewer no lee textos de consentimiento', VW, 'authenticated',
        $q$select count(*)::text from public.consent_text$q$, '0|ERR');
    perform pg_temp.expect('anon no lee textos de consentimiento', null, 'anon',
        $q$select count(*)::text from public.consent_text$q$, 'ERR|0');
    perform pg_temp.expect('un consentimiento nuevo registra el texto vigente con el que se otorgó', null, null,
        $q$with i as (insert into public.consent (organization_id, person_id, case_id, consent_type, status, granted_by_user_id)
                      values ('aaaaaaaa-0000-0000-0000-00000000000a','aaaaaaaa-4000-0000-0000-000000000001','aaaaaaaa-5000-0000-0000-000000000001','secondary_use_research','granted','aaaaaaaa-3000-0000-0000-000000000003') returning consent_text_id)
           select count(*)::text from i join public.consent_text ct on ct.id = i.consent_text_id where ct.active and ct.version = 2$q$, '1');

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
