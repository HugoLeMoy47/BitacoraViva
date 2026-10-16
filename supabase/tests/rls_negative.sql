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
    ('aaaaaaaa-3000-0000-0000-000000000006', 'tm@tst-a.invalid'),
    ('aaaaaaaa-3000-0000-0000-000000000007', 'vol@tst-a.invalid'),
    ('aaaaaaaa-3000-0000-0000-000000000008', 'vol2@tst-a.invalid'),
    ('bbbbbbbb-3000-0000-0000-000000000001', 'dir@tst-b.invalid'),
    ('bbbbbbbb-3000-0000-0000-000000000002', 'vol@tst-b.invalid')
) as u(id, email);

insert into public.user_profile (id, organization_id, email, full_name, active) values
    ('aaaaaaaa-3000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', 'dir@tst-a.invalid', 'Dir A', true),
    ('aaaaaaaa-3000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-00000000000a', 'cw@tst-a.invalid', 'Cw A', true),
    ('aaaaaaaa-3000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-00000000000a', 'in@tst-a.invalid', 'In A', true),
    ('aaaaaaaa-3000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-00000000000a', 'vw@tst-a.invalid', 'Vw A', true),
    ('aaaaaaaa-3000-0000-0000-000000000005', 'aaaaaaaa-0000-0000-0000-00000000000a', 'nr@tst-a.invalid', 'Sin rol A', true),
    ('aaaaaaaa-3000-0000-0000-000000000006', 'aaaaaaaa-0000-0000-0000-00000000000a', 'tm@tst-a.invalid', 'Coordinación de tareas A', true),
    ('aaaaaaaa-3000-0000-0000-000000000007', 'aaaaaaaa-0000-0000-0000-00000000000a', 'vol@tst-a.invalid', 'Voluntaria A', true),
    ('aaaaaaaa-3000-0000-0000-000000000008', 'aaaaaaaa-0000-0000-0000-00000000000a', 'vol2@tst-a.invalid', 'Voluntario A2', true),
    ('bbbbbbbb-3000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-00000000000b', 'dir@tst-b.invalid', 'Dir B', true),
    ('bbbbbbbb-3000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-00000000000b', 'vol@tst-b.invalid', 'Voluntaria B', true);

insert into public.user_role (user_id, role_name, area_id, granted_by, granted_at) values
    ('aaaaaaaa-3000-0000-0000-000000000001', 'director', null, 'aaaaaaaa-3000-0000-0000-000000000001', now()),
    ('aaaaaaaa-3000-0000-0000-000000000002', 'caseworker', 'aaaaaaaa-1000-0000-0000-000000000001', 'aaaaaaaa-3000-0000-0000-000000000001', now()),
    ('aaaaaaaa-3000-0000-0000-000000000003', 'intake_officer', null, 'aaaaaaaa-3000-0000-0000-000000000001', now()),
    ('aaaaaaaa-3000-0000-0000-000000000004', 'viewer', null, 'aaaaaaaa-3000-0000-0000-000000000001', now()),
    ('aaaaaaaa-3000-0000-0000-000000000006', 'task_manager', null, 'aaaaaaaa-3000-0000-0000-000000000001', now()),
    ('aaaaaaaa-3000-0000-0000-000000000007', 'volunteer', null, 'aaaaaaaa-3000-0000-0000-000000000001', now()),
    ('aaaaaaaa-3000-0000-0000-000000000008', 'volunteer', null, 'aaaaaaaa-3000-0000-0000-000000000001', now()),
    ('bbbbbbbb-3000-0000-0000-000000000001', 'director', null, 'bbbbbbbb-3000-0000-0000-000000000001', now()),
    ('bbbbbbbb-3000-0000-0000-000000000002', 'volunteer', null, 'bbbbbbbb-3000-0000-0000-000000000001', now());

-- Permisos por omisión de cada organización de prueba (lo que las organizaciones reales traen de la migración o del alta)
do $$
begin
    perform public.fn_seed_default_capabilities('aaaaaaaa-0000-0000-0000-00000000000a'::uuid);
    perform public.fn_seed_default_capabilities('bbbbbbbb-0000-0000-0000-00000000000b'::uuid);
exception when others then
    raise notice 'E16B escenario: sin los permisos por omisión todavía (%).', sqlerrm;
end $$;

-- Personas, casos, bitácora, compartición y consentimientos
insert into public.person (id, organization_id, given_name, paternal_family_name, birth_date) values
    ('aaaaaaaa-4000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', 'Ana', 'PruebaA', '1990-01-01'),
    ('bbbbbbbb-4000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-00000000000b', 'Beto', 'PruebaB', '1990-01-01');

insert into public."case" (id, organization_id, case_number, titular_person_id, opened_by, assigned_user_id, intake_window_type) values
    ('aaaaaaaa-5000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', 'TST-A-0001', 'aaaaaaaa-4000-0000-0000-000000000001', 'aaaaaaaa-3000-0000-0000-000000000003', 'aaaaaaaa-3000-0000-0000-000000000002', 'fija'),
    ('bbbbbbbb-5000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-00000000000b', 'TST-B-0001', 'bbbbbbbb-4000-0000-0000-000000000001', 'bbbbbbbb-3000-0000-0000-000000000001', 'bbbbbbbb-3000-0000-0000-000000000001', 'fija');

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

-- Seguidor de tareas (E7): catálogos, rutinas, tareas, evidencia y notas de A y de B
insert into public.task_category (id, organization_id, key, label_es) values
    ('aaaaaaaa-9000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', 'limpieza', 'Limpieza'),
    ('bbbbbbbb-9000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-00000000000b', 'limpieza', 'Limpieza B');
insert into public.work_area (id, organization_id, key, label_es) values
    ('aaaaaaaa-9100-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', 'cocina', 'Cocina'),
    ('bbbbbbbb-9100-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-00000000000b', 'cocina', 'Cocina B');
insert into public.routine_template (id, organization_id, name, work_area_id, task_category_id, created_by) values
    ('aaaaaaaa-9200-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', 'Turno de cocina A', 'aaaaaaaa-9100-0000-0000-000000000001', 'aaaaaaaa-9000-0000-0000-000000000001', 'aaaaaaaa-3000-0000-0000-000000000006'),
    ('bbbbbbbb-9200-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-00000000000b', 'Turno de cocina B', 'bbbbbbbb-9100-0000-0000-000000000001', 'bbbbbbbb-9000-0000-0000-000000000001', 'bbbbbbbb-3000-0000-0000-000000000001');
insert into public.routine_template_item (id, organization_id, routine_template_id, name, sort_order) values
    ('aaaaaaaa-9300-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', 'aaaaaaaa-9200-0000-0000-000000000001', 'Preparar el desayuno', 1),
    ('aaaaaaaa-9300-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-00000000000a', 'aaaaaaaa-9200-0000-0000-000000000001', 'Lavar la loza', 2),
    ('bbbbbbbb-9300-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-00000000000b', 'bbbbbbbb-9200-0000-0000-000000000001', 'Preparar el desayuno B', 1);
-- Tareas de A: 01 coordinación→VOL · 02 VOL en curso con foto · 03 pool · 04 VOL2 · 05 VOL tomada y vencida
--   06 VOL en curso (con evidencia) · 07 pool · 08 VOL tomada hoy · 09 VOL2 · 0a VOL2 en curso · 0b VOL2 en curso con foto
insert into public.task (id, organization_id, name, status, photo_required, assigned_to, claimed_at, task_category_id, work_area_id, created_by) values
    ('aaaaaaaa-a000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', 'Tarea A1', 'pending', false, 'aaaaaaaa-3000-0000-0000-000000000007', null, 'aaaaaaaa-9000-0000-0000-000000000001', 'aaaaaaaa-9100-0000-0000-000000000001', 'aaaaaaaa-3000-0000-0000-000000000006'),
    ('aaaaaaaa-a000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-00000000000a', 'Tarea A2', 'in_progress', true, 'aaaaaaaa-3000-0000-0000-000000000007', null, 'aaaaaaaa-9000-0000-0000-000000000001', 'aaaaaaaa-9100-0000-0000-000000000001', 'aaaaaaaa-3000-0000-0000-000000000006'),
    ('aaaaaaaa-a000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-00000000000a', 'Tarea A3 (pool)', 'pending', false, null, null, 'aaaaaaaa-9000-0000-0000-000000000001', 'aaaaaaaa-9100-0000-0000-000000000001', 'aaaaaaaa-3000-0000-0000-000000000006'),
    ('aaaaaaaa-a000-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-00000000000a', 'Tarea A4', 'pending', false, 'aaaaaaaa-3000-0000-0000-000000000008', null, null, null, 'aaaaaaaa-3000-0000-0000-000000000006'),
    ('aaaaaaaa-a000-0000-0000-000000000005', 'aaaaaaaa-0000-0000-0000-00000000000a', 'Tarea A5 (tomada hace 3 días)', 'pending', false, 'aaaaaaaa-3000-0000-0000-000000000007', now() - interval '3 days', null, 'aaaaaaaa-9100-0000-0000-000000000001', 'aaaaaaaa-3000-0000-0000-000000000006'),
    ('aaaaaaaa-a000-0000-0000-000000000006', 'aaaaaaaa-0000-0000-0000-00000000000a', 'Tarea A6', 'in_progress', false, 'aaaaaaaa-3000-0000-0000-000000000007', null, null, 'aaaaaaaa-9100-0000-0000-000000000001', 'aaaaaaaa-3000-0000-0000-000000000006'),
    ('aaaaaaaa-a000-0000-0000-000000000007', 'aaaaaaaa-0000-0000-0000-00000000000a', 'Tarea A7 (pool)', 'pending', false, null, null, null, 'aaaaaaaa-9100-0000-0000-000000000001', 'aaaaaaaa-3000-0000-0000-000000000006'),
    ('aaaaaaaa-a000-0000-0000-000000000008', 'aaaaaaaa-0000-0000-0000-00000000000a', 'Tarea A8 (tomada hoy)', 'pending', false, 'aaaaaaaa-3000-0000-0000-000000000007', now(), null, 'aaaaaaaa-9100-0000-0000-000000000001', 'aaaaaaaa-3000-0000-0000-000000000006'),
    ('aaaaaaaa-a000-0000-0000-000000000009', 'aaaaaaaa-0000-0000-0000-00000000000a', 'Tarea A9', 'pending', false, 'aaaaaaaa-3000-0000-0000-000000000008', null, null, null, 'aaaaaaaa-3000-0000-0000-000000000006'),
    ('aaaaaaaa-a000-0000-0000-00000000000a', 'aaaaaaaa-0000-0000-0000-00000000000a', 'Tarea A10', 'in_progress', false, 'aaaaaaaa-3000-0000-0000-000000000008', null, null, null, 'aaaaaaaa-3000-0000-0000-000000000006'),
    ('aaaaaaaa-a000-0000-0000-00000000000b', 'aaaaaaaa-0000-0000-0000-00000000000a', 'Tarea A11 (exige foto)', 'in_progress', true, 'aaaaaaaa-3000-0000-0000-000000000008', null, null, null, 'aaaaaaaa-3000-0000-0000-000000000006'),
    ('bbbbbbbb-a000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-00000000000b', 'Tarea B1', 'pending', false, 'bbbbbbbb-3000-0000-0000-000000000002', null, 'bbbbbbbb-9000-0000-0000-000000000001', 'bbbbbbbb-9100-0000-0000-000000000001', 'bbbbbbbb-3000-0000-0000-000000000001'),
    ('bbbbbbbb-a000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-00000000000b', 'Tarea B2 (pool)', 'pending', false, null, null, null, null, 'bbbbbbbb-3000-0000-0000-000000000001');
insert into public.task_evidence (id, organization_id, task_id, storage_path, mime_type, size_bytes) values
    ('aaaaaaaa-9400-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', 'aaaaaaaa-a000-0000-0000-000000000006',
     'aaaaaaaa-0000-0000-0000-00000000000a/aaaaaaaa-a000-0000-0000-000000000006/inicial.jpg', 'image/jpeg', 1000),
    ('bbbbbbbb-9400-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-00000000000b', 'bbbbbbbb-a000-0000-0000-000000000001',
     'bbbbbbbb-0000-0000-0000-00000000000b/bbbbbbbb-a000-0000-0000-000000000001/inicial.jpg', 'image/jpeg', 1000);
insert into public.case_task_kind (id, organization_id, key, label_es) values
    ('aaaaaaaa-9600-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', 'accompaniment', 'Acompañamiento'),
    ('bbbbbbbb-9600-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-00000000000b', 'accompaniment', 'Acompañamiento B');
insert into public.shift_note (id, organization_id, work_area_id, body, created_by) values
    ('aaaaaaaa-9500-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-00000000000a', 'aaaaaaaa-9100-0000-0000-000000000001', 'Nota de turno A (texto libre)', 'aaaaaaaa-3000-0000-0000-000000000007'),
    ('bbbbbbbb-9500-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-00000000000b', 'bbbbbbbb-9100-0000-0000-000000000001', 'Nota de turno B (texto libre)', 'bbbbbbbb-3000-0000-0000-000000000002');

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
    else
        -- Prueba como propietario: sin sesión. Sin esto heredaría la identidad de la prueba anterior
        perform set_config('request.jwt.claims', '', true);
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
        ok := ok or case
            when alt = 'ERR' then a like 'ERR:%'
            -- 'ERR:TK012' exige ese SQLSTATE concreto
            when alt like 'ERR:%' then a like alt || '%'
            when alt = 'OK' then a not like 'ERR:%'
            when alt = '>0' then a not like 'ERR:%' and a ~ '^[0-9]+$' and a::bigint > 0
            else a = alt end;
    end loop;
    insert into test_res values (case when ok then 'PASS' else 'FAIL' end, p_name, p_expected, a);
end $$;

-- Sustituye marcadores como {VOL} o {TA3} por el identificador entre comillas, para que las
-- pruebas de tareas se lean sin repetir cuarenta UUID. A y B son las dos organizaciones.
create or replace function pg_temp.q(p text)
returns text language plpgsql as $$
declare
    r text := p;
    kv text[];
begin
    foreach kv slice 1 in array array[
        ['{ORGA}', 'aaaaaaaa-0000-0000-0000-00000000000a'], ['{ORGB}', 'bbbbbbbb-0000-0000-0000-00000000000b'],
        ['{DIRB2}', 'bbbbbbbb-3000-0000-0000-000000000003'], ['{DIRB}', 'bbbbbbbb-3000-0000-0000-000000000001'],
        ['{VOLB}', 'bbbbbbbb-3000-0000-0000-000000000002'], ['{DIR}', 'aaaaaaaa-3000-0000-0000-000000000001'],
        ['{CW}', 'aaaaaaaa-3000-0000-0000-000000000002'], ['{INT}', 'aaaaaaaa-3000-0000-0000-000000000003'],
        ['{VW}', 'aaaaaaaa-3000-0000-0000-000000000004'], ['{NR}', 'aaaaaaaa-3000-0000-0000-000000000005'],
        ['{TM}', 'aaaaaaaa-3000-0000-0000-000000000006'], ['{VOL2}', 'aaaaaaaa-3000-0000-0000-000000000008'],
        ['{VOL}', 'aaaaaaaa-3000-0000-0000-000000000007'], ['{DIRA2}', 'aaaaaaaa-3000-0000-0000-000000000009'],
        ['{TA10}', 'aaaaaaaa-a000-0000-0000-00000000000a'], ['{TA11}', 'aaaaaaaa-a000-0000-0000-00000000000b'],
        ['{TA1}', 'aaaaaaaa-a000-0000-0000-000000000001'], ['{TA2}', 'aaaaaaaa-a000-0000-0000-000000000002'],
        ['{TA3}', 'aaaaaaaa-a000-0000-0000-000000000003'], ['{TA4}', 'aaaaaaaa-a000-0000-0000-000000000004'],
        ['{TA5}', 'aaaaaaaa-a000-0000-0000-000000000005'], ['{TA6}', 'aaaaaaaa-a000-0000-0000-000000000006'],
        ['{TA7}', 'aaaaaaaa-a000-0000-0000-000000000007'], ['{TA8}', 'aaaaaaaa-a000-0000-0000-000000000008'],
        ['{TA9}', 'aaaaaaaa-a000-0000-0000-000000000009'],
        ['{TB1}', 'bbbbbbbb-a000-0000-0000-000000000001'], ['{TB2}', 'bbbbbbbb-a000-0000-0000-000000000002'],
        ['{RTA}', 'aaaaaaaa-9200-0000-0000-000000000001'], ['{RTB}', 'bbbbbbbb-9200-0000-0000-000000000001'],
        ['{WAA}', 'aaaaaaaa-9100-0000-0000-000000000001'], ['{WAB}', 'bbbbbbbb-9100-0000-0000-000000000001'],
        ['{CATA}', 'aaaaaaaa-9000-0000-0000-000000000001'], ['{CATB}', 'bbbbbbbb-9000-0000-0000-000000000001'],
        ['{EVA}', 'aaaaaaaa-9400-0000-0000-000000000001'], ['{EVB}', 'bbbbbbbb-9400-0000-0000-000000000001'],
        ['{NA}', 'aaaaaaaa-9500-0000-0000-000000000001'], ['{NB}', 'bbbbbbbb-9500-0000-0000-000000000001'],
        ['{KA}', 'aaaaaaaa-9600-0000-0000-000000000001'], ['{KB}', 'bbbbbbbb-9600-0000-0000-000000000001'],
        ['{CASEA}', 'aaaaaaaa-5000-0000-0000-000000000001'], ['{CASEB}', 'bbbbbbbb-5000-0000-0000-000000000001']
    ] loop
        r := replace(r, kv[1], '''' || kv[2] || '''');
    end loop;
    return r;
end $$;

do $do$
declare
    DIR  constant text := 'aaaaaaaa-3000-0000-0000-000000000001';
    CW   constant text := 'aaaaaaaa-3000-0000-0000-000000000002';
    INT  constant text := 'aaaaaaaa-3000-0000-0000-000000000003';
    VW   constant text := 'aaaaaaaa-3000-0000-0000-000000000004';
    NR   constant text := 'aaaaaaaa-3000-0000-0000-000000000005';
    DIRB constant text := 'bbbbbbbb-3000-0000-0000-000000000001';
    TM   constant text := 'aaaaaaaa-3000-0000-0000-000000000006';
    VOL  constant text := 'aaaaaaaa-3000-0000-0000-000000000007';
    VOL2 constant text := 'aaaaaaaa-3000-0000-0000-000000000008';
    VOLB constant text := 'bbbbbbbb-3000-0000-0000-000000000002';
    DIRB2 constant text := 'bbbbbbbb-3000-0000-0000-000000000003';
    DIRA2 constant text := 'aaaaaaaa-3000-0000-0000-000000000009';
    ORG_A constant text := 'aaaaaaaa-0000-0000-0000-00000000000a';
    ORG_B constant text := 'bbbbbbbb-0000-0000-0000-00000000000b';
    t text;
    new_case text := $nc$select count(*)::text from (select public.fn_create_case_with_person(
        'Nuevo','Caso',null,null,date '2000-01-01',false,null,null,null,null,null,null,'fija',false,null,null,null,null,null,
        'aaaaaaaa-1000-0000-0000-000000000001'::uuid, array[]::text[], '[{"consent_type":"general_care","status":"granted"}]'::jsonb)) x$nc$;
    report text;
begin
    -- ===== Aislamiento por organización (BV-1.1): ni una fila de otra organización
    foreach t in array array['person','"case"','case_status','case_vulnerability_marker','journal_entry','sharing_event','consent','arco_request','attachment','privacy_notice','authority_request','audit_event','area','status_axis','status_value','user_profile',
                             'task_category','work_area','routine_template','routine_template_item','task','task_evidence','shift_note','task_setting'] loop
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
        replace(new_case, '''[{"consent_type":"general_care","status":"granted"}]''', '''[]'''), 'ERR');
    perform pg_temp.expect('P-06: sin consentimiento sensible no hay marcadores de vulnerabilidad', INT, 'authenticated',
        replace(new_case, 'array[]::text[]', 'array[''victim_of_violence'']'), 'ERR');
    perform pg_temp.expect('control positivo: con consentimiento sensible sí hay marcadores', INT, 'authenticated',
        replace(replace(new_case, 'array[]::text[]', 'array[''victim_of_violence'']'),
                '''[{"consent_type":"general_care","status":"granted"}]''', '''[{"consent_type":"general_care","status":"granted"},{"consent_type":"sensitive_data","status":"granted"}]'''), '1');
    perform pg_temp.expect('persona menor de 18 sin asentimiento ni representante no se abre', INT, 'authenticated',
        replace(new_case, 'date ''2000-01-01''', 'current_date - 3000'), 'ERR');
    perform pg_temp.expect('control positivo: menor con asentimiento y representante', INT, 'authenticated',
        replace(replace(new_case, 'date ''2000-01-01''', 'current_date - 3000'), '''[{"consent_type":"general_care","status":"granted"}]''',
                '''[{"consent_type":"general_care","status":"granted","is_minor_assent":true,"legal_guardian_name":"Madre"}]'''), '1');
    perform pg_temp.expect('niñez no acompañada sin autoridad ni oficio no se abre', INT, 'authenticated',
        replace(replace(replace(new_case, 'date ''2000-01-01''', 'current_date - 3000'), 'array[]::text[]', 'array[''unaccompanied_child'']'),
                '''[{"consent_type":"general_care","status":"granted"}]''',
                '''[{"consent_type":"general_care","status":"granted","is_minor_assent":true,"legal_guardian_name":"Tutor"},{"consent_type":"sensitive_data","status":"granted"}]'''), 'ERR');
    foreach t in array array[CW, INT, VW, NR, TM, VOL] loop
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
        'select count(*)::text from (select public.fn_rectify_person(''aaaaaaaa-4000-0000-0000-000000000001''::uuid,''A'',''B'',null,null,date ''1990-01-01'',false,null,null,null,null,''x'')) x', 'ERR');
    perform pg_temp.expect('control positivo: director acusa recibo', DIR, 'authenticated',
        'select count(*)::text from (select public.fn_acknowledge_sharing(''aaaaaaaa-7000-0000-0000-000000000001''::uuid)) x', '1');
    perform pg_temp.expect('control positivo: director emite extracto ARCO', DIR, 'authenticated',
        'select jsonb_array_length(public.fn_generate_arco_access_extract(''aaaaaaaa-4000-0000-0000-000000000001''::uuid)->''cases'')::text', '1');

    -- ===== Funciones que se saltan RLS (security definer): cada una repite la regla de acceso.
    -- Escribir exige sesión, rol operativo y que el registro sea de la propia organización.
    foreach t in array array[
        'select public.fn_register_consent(''aaaaaaaa-4000-0000-0000-000000000001''::uuid, ''general_care'', ''granted'')::text',
        'select public.fn_create_journal_entry(''aaaaaaaa-5000-0000-0000-000000000001''::uuid, ''note'', ''x'', now(), false, ''aaaaaaaa-1000-0000-0000-000000000001''::uuid)::text',
        'select public.fn_create_clarification_note(''aaaaaaaa-6000-0000-0000-000000000001''::uuid, ''x'')::text',
        'select public.fn_share_journal_entry(''aaaaaaaa-6000-0000-0000-000000000001''::uuid, ''aaaaaaaa-1000-0000-0000-000000000002''::uuid, ''x'')::text',
        'select public.fn_change_case_status(''aaaaaaaa-5000-0000-0000-000000000001''::uuid, ''case_stage'', ''assessment'', ''x'')::text'
    ] loop
        perform pg_temp.expect('anon no ejecuta ' || split_part(split_part(t, 'public.', 2), '(', 1), null, 'anon', t, 'ERR');
        perform pg_temp.expect('viewer no ejecuta ' || split_part(split_part(t, 'public.', 2), '(', 1), VW, 'authenticated', t, 'ERR');
        perform pg_temp.expect('sin rol no ejecuta ' || split_part(split_part(t, 'public.', 2), '(', 1), NR, 'authenticated', t, 'ERR');
        perform pg_temp.expect('director de otra organización no ejecuta ' || split_part(split_part(t, 'public.', 2), '(', 1), DIRB, 'authenticated', t, 'ERR');
        -- Los roles de tareas no reciben ninguna función del expediente (ADR-0007)
        perform pg_temp.expect('voluntariado no ejecuta ' || split_part(split_part(t, 'public.', 2), '(', 1), VOL, 'authenticated', t, 'ERR');
        perform pg_temp.expect('coordinación de tareas no ejecuta ' || split_part(split_part(t, 'public.', 2), '(', 1), TM, 'authenticated', t, 'ERR');
    end loop;

    perform pg_temp.expect('control positivo: intake registra consentimiento', INT, 'authenticated',
        'select count(*)::text from (select public.fn_register_consent(''aaaaaaaa-4000-0000-0000-000000000001''::uuid, ''internal_sharing'', ''granted'')) x', '1');
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
    foreach t in array array['person','"case"','case_status','case_vulnerability_marker','journal_entry','sharing_event','consent','arco_request','audit_event','user_role','user_profile','organization','area',
                             'task_category','work_area','routine_template','routine_template_item','task','task_evidence','shift_note','task_setting'] loop
        perform pg_temp.expect('DELETE denegado a director en ' || t, DIR, 'authenticated',
            format('with d as (delete from public.%s returning 1) select count(*)::text from d', t), 'ERR');
    end loop;
    -- Ni la coordinación ni el voluntariado borran nada de tareas
    foreach t in array array['task_category','work_area','routine_template','routine_template_item','task','task_evidence','shift_note','task_setting'] loop
        perform pg_temp.expect('DELETE denegado a coordinación de tareas en ' || t, TM, 'authenticated',
            format('with d as (delete from public.%s returning 1) select count(*)::text from d', t), 'ERR');
        perform pg_temp.expect('DELETE denegado a voluntariado en ' || t, VOL, 'authenticated',
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

    -- ============================================================================================
    -- ===== Seguidor de tareas (E7) · ADR-0007: roles agregados
    -- ============================================================================================

    -- ----- Frontera con el expediente: los roles de tareas no reciben ni una fila
    foreach t in array array['person','"case"','case_status','case_vulnerability_marker','journal_entry','sharing_event','consent','arco_request','attachment','privacy_notice','authority_request','audit_event','area','status_axis','status_value'] loop
        perform pg_temp.expect('voluntariado no ve ' || t, VOL, 'authenticated', format('select count(*)::text from public.%s', t), '0');
        perform pg_temp.expect('coordinación de tareas no ve ' || t, TM, 'authenticated', format('select count(*)::text from public.%s', t), '0');
    end loop;
    perform pg_temp.expect('control positivo: el voluntariado ve su organización', VOL, 'authenticated', 'select count(*)::text from public.organization', '1');
    perform pg_temp.expect('control positivo: el voluntariado ve los perfiles de su organización', VOL, 'authenticated', 'select count(*)::text from public.user_profile', '>0');
    perform pg_temp.expect('voluntariado no consulta indicadores de casos', VOL, 'authenticated', 'select public.fn_aggregate_metrics()::text', 'ERR');
    perform pg_temp.expect('coordinación de tareas no consulta indicadores de casos', TM, 'authenticated', 'select public.fn_aggregate_metrics()::text', 'ERR');
    perform pg_temp.expect('voluntariado no abre casos', VOL, 'authenticated', new_case, 'ERR');
    perform pg_temp.expect('has_any_role es «rol de casos»: el voluntariado no lo tiene', VOL, 'authenticated', 'select public.has_any_role()::text', 'false');
    perform pg_temp.expect('has_any_role es «rol de casos»: la coordinación de tareas no lo tiene', TM, 'authenticated', 'select public.has_any_role()::text', 'false');
    perform pg_temp.expect('control positivo: has_any_role sigue siendo cierto para un viewer', VW, 'authenticated', 'select public.has_any_role()::text', 'true');
    perform pg_temp.expect('has_active_role incluye a los roles de tareas', VOL, 'authenticated', 'select public.has_active_role()::text', 'true');
    perform pg_temp.expect('el voluntariado tiene acceso a tareas', VOL, 'authenticated', 'select public.has_task_role()::text', 'true');
    perform pg_temp.expect('el voluntariado no gestiona tareas', VOL, 'authenticated', 'select public.has_task_management()::text', 'false');
    perform pg_temp.expect('la coordinación de tareas gestiona tareas', TM, 'authenticated', 'select public.has_task_management()::text', 'true');
    perform pg_temp.expect('el director gestiona tareas', DIR, 'authenticated', 'select public.has_task_management()::text', 'true');
    perform pg_temp.expect('caseworker tiene acceso a tareas pero no las gestiona', CW, 'authenticated',
        'select (public.has_task_role() and not public.has_task_management())::text', 'true');
    perform pg_temp.expect('intake_officer tiene acceso a tareas pero no las gestiona', INT, 'authenticated',
        'select (public.has_task_role() and not public.has_task_management())::text', 'true');
    perform pg_temp.expect('viewer no tiene acceso a tareas', VW, 'authenticated', 'select public.has_task_role()::text', 'false');
    perform pg_temp.expect('sin rol no tiene acceso a tareas', NR, 'authenticated', 'select public.has_task_role()::text', 'false');
    perform pg_temp.expect('user_has_task_role no es ejecutable por roles de aplicación', DIR, 'authenticated',
        pg_temp.q('select public.user_has_task_role({VOL})::text'), 'ERR');

    -- ----- Quién ve qué tareas
    perform pg_temp.expect('voluntariado ve sus tareas y el pool', VOL, 'authenticated', 'select count(*)::text from public.task', '7');
    perform pg_temp.expect('voluntariado no ve la tarea de otra persona', VOL, 'authenticated',
        pg_temp.q('select count(*)::text from public.task where id = {TA4}'), '0');
    perform pg_temp.expect('voluntariado no ve tareas de otra organización', VOL, 'authenticated',
        pg_temp.q('select count(*)::text from public.task where organization_id = {ORGB}'), '0');
    perform pg_temp.expect('coordinación de tareas ve todas las tareas de su organización', TM, 'authenticated', 'select count(*)::text from public.task', '11');
    perform pg_temp.expect('el director ve todas las tareas de su organización', DIR, 'authenticated', 'select count(*)::text from public.task', '11');
    perform pg_temp.expect('caseworker sin tareas asignadas ve sólo el pool', CW, 'authenticated', 'select count(*)::text from public.task', '2');
    perform pg_temp.expect('viewer no ve tareas', VW, 'authenticated', 'select count(*)::text from public.task', '0');
    perform pg_temp.expect('sin rol no ve tareas', NR, 'authenticated', 'select count(*)::text from public.task', '0');
    perform pg_temp.expect('viewer no ve los ajustes de operación', VW, 'authenticated', 'select count(*)::text from public.task_setting', '0');
    perform pg_temp.expect('viewer no ve los catálogos de tareas', VW, 'authenticated', 'select count(*)::text from public.task_category', '0');
    perform pg_temp.expect('anon no ve tareas', null, 'anon', 'select count(*)::text from public.task', 'ERR|0');
    perform pg_temp.expect('control positivo: el voluntariado ve los catálogos de tareas', VOL, 'authenticated', 'select count(*)::text from public.task_category', '>0');
    perform pg_temp.expect('voluntariado de B no ve las tareas de A', VOLB, 'authenticated',
        pg_temp.q('select count(*)::text from public.task where organization_id = {ORGA}'), '0');

    -- ----- Pool: devolver lo vencido, tomar, tope y soltar
    perform pg_temp.expect('devolución automática: lo tomado y vencido vuelve al pool', VOL2, 'authenticated',
        'select public.fn_release_expired_claims()::text', '1');
    perform pg_temp.expect('la tarea vencida quedó sin asignar', null, null,
        pg_temp.q('select (assigned_to is null and claimed_at is null)::text from public.task where id = {TA5}'), 'true');
    perform pg_temp.expect('lo asignado por coordinación nunca se desasigna solo', null, null,
        pg_temp.q('select (assigned_to = {VOL}::uuid)::text from public.task where id = {TA1}'), 'true');
    perform pg_temp.expect('control positivo: caseworker toma una tarea del pool', CW, 'authenticated',
        pg_temp.q('select public.fn_claim_open_task({TA3})->>''status'''), 'pending');
    perform pg_temp.expect('la tarea tomada queda a nombre de quien la tomó', null, null,
        pg_temp.q('select (assigned_to = {CW}::uuid and claimed_at is not null)::text from public.task where id = {TA3}'), 'true');
    perform pg_temp.expect('una tarea ya tomada no se toma dos veces', VOL2, 'authenticated',
        pg_temp.q('select public.fn_claim_open_task({TA3})::text'), 'ERR:TK012');
    perform pg_temp.expect('no se toma una tarea que ya se empezó', VOL2, 'authenticated',
        pg_temp.q('select public.fn_claim_open_task({TA6})::text'), 'ERR:TK012|ERR:TK013');
    perform pg_temp.expect('control positivo: la dirección fija un tope de 1 tarea tomada sin empezar', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_update_task_setting('all', 30, 1, 1)) x$q$, '1');
    perform pg_temp.expect('el tope se respeta: ya tiene una tomada sin empezar', VOL, 'authenticated',
        pg_temp.q('select public.fn_claim_open_task({TA7})::text'), 'ERR:TK014');
    perform pg_temp.expect('la dirección vuelve el tope a cero', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_update_task_setting('all', 30, 0, 1)) x$q$, '1');
    perform pg_temp.expect('control positivo: sin tope el voluntariado toma otra', VOL, 'authenticated',
        pg_temp.q('select public.fn_claim_open_task({TA7})->>''status'''), 'pending');
    perform pg_temp.expect('viewer no toma tareas', VW, 'authenticated', pg_temp.q('select public.fn_claim_open_task({TA3})::text'), 'ERR:TK010');
    perform pg_temp.expect('sin rol no toma tareas', NR, 'authenticated', pg_temp.q('select public.fn_claim_open_task({TA3})::text'), 'ERR:TK010');
    perform pg_temp.expect('anon no toma tareas', null, 'anon', pg_temp.q('select public.fn_claim_open_task({TA3})::text'), 'ERR');
    perform pg_temp.expect('director de otra organización no toma tareas de A', DIRB, 'authenticated',
        pg_temp.q('select public.fn_claim_open_task({TA3})::text'), 'ERR:TK011');
    perform pg_temp.expect('voluntariado de A no toma tareas de B', VOL, 'authenticated',
        pg_temp.q('select public.fn_claim_open_task({TB2})::text'), 'ERR:TK011');
    perform pg_temp.expect('control positivo: se suelta lo que se tomó y no se empezó', VOL, 'authenticated',
        pg_temp.q('select public.fn_release_task({TA8})->>''status'''), 'pending');
    perform pg_temp.expect('lo soltado vuelve al pool', null, null,
        pg_temp.q('select (assigned_to is null and claimed_at is null)::text from public.task where id = {TA8}'), 'true');
    perform pg_temp.expect('no se suelta lo que coordinación asignó', VOL, 'authenticated',
        pg_temp.q('select public.fn_release_task({TA1})::text'), 'ERR:TK019');
    perform pg_temp.expect('no se suelta la tarea de otra persona', VOL2, 'authenticated',
        pg_temp.q('select public.fn_release_task({TA7})::text'), 'ERR:TK017');
    perform pg_temp.expect('no se suelta lo que ya se empezó', VOL, 'authenticated',
        pg_temp.q('select public.fn_release_task({TA2})::text'), 'ERR:TK018');
    perform pg_temp.expect('viewer no suelta tareas', VW, 'authenticated', pg_temp.q('select public.fn_release_task({TA7})::text'), 'ERR:TK010');
    perform pg_temp.expect('voluntariado no toca el pool por UPDATE directo para llevarse una tarea ajena', VOL, 'authenticated',
        pg_temp.q('with u as (update public.task set assigned_to = {VOL} where id = {TA4} returning 1) select count(*)::text from u'), 'ERR|0');
    perform pg_temp.expect('voluntariado no se asigna una tarea del pool por UPDATE directo sin tomarla', VOL, 'authenticated',
        pg_temp.q('with u as (update public.task set assigned_to = {VOL}, claimed_at = null where id = {TA5} returning 1) select count(*)::text from u'), 'ERR|0');

    -- ----- Rutinas: una vez por plantilla y por día
    perform pg_temp.expect('control positivo: el voluntariado inicia una rutina', VOL, 'authenticated',
        pg_temp.q('select public.fn_start_routine({RTA})->>''tasks_created'''), '2');
    perform pg_temp.expect('la rutina crea sus tareas, asignadas a quien la inició', VOL, 'authenticated',
        pg_temp.q('select count(*)::text from public.task where assigned_to = {VOL} and routine_template_id = {RTA}'), '2');
    perform pg_temp.expect('la misma rutina no se inicia dos veces el mismo día', VOL, 'authenticated',
        pg_temp.q('select public.fn_start_routine({RTA})::text'), 'ERR:TK022');
    perform pg_temp.expect('no se inicia una rutina de otra organización', VOL, 'authenticated',
        pg_temp.q('select public.fn_start_routine({RTB})::text'), 'ERR:TK021');
    perform pg_temp.expect('viewer no inicia rutinas', VW, 'authenticated', pg_temp.q('select public.fn_start_routine({RTA})::text'), 'ERR:TK010');
    perform pg_temp.expect('anon no inicia rutinas', null, 'anon', pg_temp.q('select public.fn_start_routine({RTA})::text'), 'ERR');
    perform pg_temp.expect('voluntariado no crea plantillas de rutina', VOL, 'authenticated',
        pg_temp.q('with i as (insert into public.routine_template (organization_id, name) values ({ORGA}, ''x'') returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('control positivo: la coordinación archiva una plantilla', TM, 'authenticated',
        pg_temp.q('with u as (update public.routine_template set archived_at = now() where id = {RTA} returning 1) select count(*)::text from u'), '1');
    perform pg_temp.expect('una plantilla archivada no se inicia', VOL2, 'authenticated',
        pg_temp.q('select public.fn_start_routine({RTA})::text'), 'ERR:TK021');

    -- ----- Escribir tareas: qué puede cada nivel
    perform pg_temp.expect('voluntariado no crea tareas', VOL, 'authenticated',
        pg_temp.q('with i as (insert into public.task (organization_id, name) values ({ORGA}, ''x'') returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('caseworker no crea tareas', CW, 'authenticated',
        pg_temp.q('with i as (insert into public.task (organization_id, name) values ({ORGA}, ''x'') returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('control positivo: la coordinación crea tareas', TM, 'authenticated',
        pg_temp.q('with i as (insert into public.task (organization_id, name) values ({ORGA}, ''Creada por coordinación'') returning 1) select count(*)::text from i'), '1');
    perform pg_temp.expect('la coordinación no crea tareas en otra organización', TM, 'authenticated',
        pg_temp.q('with i as (insert into public.task (organization_id, name) values ({ORGB}, ''x'') returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('una tarea no usa la categoría de otra organización', TM, 'authenticated',
        pg_temp.q('with i as (insert into public.task (organization_id, name, task_category_id) values ({ORGA}, ''x'', {CATB}) returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('no se asigna una tarea a un viewer', TM, 'authenticated',
        pg_temp.q('with u as (update public.task set assigned_to = {VW} where id = {TA9} returning 1) select count(*)::text from u'), 'ERR:TK007');
    perform pg_temp.expect('no se asigna una tarea a una persona de otra organización', TM, 'authenticated',
        pg_temp.q('with u as (update public.task set assigned_to = {VOLB} where id = {TA9} returning 1) select count(*)::text from u'), 'ERR');
    perform pg_temp.expect('control positivo: la coordinación reasigna una tarea', TM, 'authenticated',
        pg_temp.q('with u as (update public.task set assigned_to = {VOL} where id = {TA9} returning 1) select count(*)::text from u'), '1');
    perform pg_temp.expect('voluntariado no edita el nombre de su tarea', VOL, 'authenticated',
        pg_temp.q('with u as (update public.task set name = ''editada'' where id = {TA1} returning 1) select count(*)::text from u'), 'ERR:TK001');
    perform pg_temp.expect('voluntariado no se reasigna su tarea a otra persona', VOL, 'authenticated',
        pg_temp.q('with u as (update public.task set assigned_to = {VOL2} where id = {TA1} returning 1) select count(*)::text from u'), 'ERR:TK001');
    perform pg_temp.expect('voluntariado no cambia la fecha límite', VOL, 'authenticated',
        pg_temp.q('with u as (update public.task set due_at = current_date where id = {TA1} returning 1) select count(*)::text from u'), 'ERR:TK001');
    perform pg_temp.expect('voluntariado no quita la exigencia de foto', VOL, 'authenticated',
        pg_temp.q('with u as (update public.task set photo_required = false where id = {TA2} returning 1) select count(*)::text from u'), 'ERR:TK001');
    perform pg_temp.expect('voluntariado no archiva su tarea', VOL, 'authenticated',
        pg_temp.q('with u as (update public.task set archived_at = now() where id = {TA1} returning 1) select count(*)::text from u'), 'ERR:TK001');
    perform pg_temp.expect('voluntariado no cambia la organización de su tarea', VOL, 'authenticated',
        pg_temp.q('with u as (update public.task set organization_id = {ORGB} where id = {TA1} returning 1) select count(*)::text from u'), 'ERR');
    perform pg_temp.expect('voluntariado no edita la tarea de otra persona', VOL2, 'authenticated',
        pg_temp.q('with u as (update public.task set status = ''done'' where id = {TA1} returning 1) select count(*)::text from u'), '0|ERR');
    perform pg_temp.expect('control positivo: el voluntariado avanza su tarea', VOL, 'authenticated',
        pg_temp.q('with u as (update public.task set status = ''in_progress'' where id = {TA1} returning 1) select count(*)::text from u'), '1');
    perform pg_temp.expect('la primera vez en curso sella el inicio', null, null,
        pg_temp.q('select (started_at is not null)::text from public.task where id = {TA1}'), 'true');
    perform pg_temp.expect('voluntariado no retrocede una tarea', VOL, 'authenticated',
        pg_temp.q('with u as (update public.task set status = ''pending'' where id = {TA1} returning 1) select count(*)::text from u'), 'ERR:TK002');
    perform pg_temp.expect('sin evidencia no hay cierre cuando la tarea exige foto', VOL, 'authenticated',
        pg_temp.q('with u as (update public.task set status = ''done'' where id = {TA2} returning 1) select count(*)::text from u'), 'ERR:TK003');
    perform pg_temp.expect('voluntariado no sube evidencia a la tarea de otra persona', VOL, 'authenticated',
        pg_temp.q('with i as (insert into public.task_evidence (organization_id, task_id, storage_path, mime_type, size_bytes) values ({ORGA}, {TA4}, {ORGA}::text || ''/'' || {TA4}::text || ''/x.jpg'', ''image/jpeg'', 100) returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('la ruta de la evidencia debe pertenecer a la tarea', VOL, 'authenticated',
        pg_temp.q('with i as (insert into public.task_evidence (organization_id, task_id, storage_path, mime_type, size_bytes) values ({ORGA}, {TA2}, {ORGA}::text || ''/'' || {TA6}::text || ''/x.jpg'', ''image/jpeg'', 100) returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('la evidencia sólo admite imágenes', VOL, 'authenticated',
        pg_temp.q('with i as (insert into public.task_evidence (organization_id, task_id, storage_path, mime_type, size_bytes) values ({ORGA}, {TA2}, {ORGA}::text || ''/'' || {TA2}::text || ''/x.gif'', ''image/gif'', 100) returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('la evidencia pesa a lo sumo 5 MB', VOL, 'authenticated',
        pg_temp.q('with i as (insert into public.task_evidence (organization_id, task_id, storage_path, mime_type, size_bytes) values ({ORGA}, {TA2}, {ORGA}::text || ''/'' || {TA2}::text || ''/x.jpg'', ''image/jpeg'', 6000000) returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('control positivo: el voluntariado sube evidencia a su tarea', VOL, 'authenticated',
        pg_temp.q('with i as (insert into public.task_evidence (organization_id, task_id, storage_path, mime_type, size_bytes) values ({ORGA}, {TA2}, {ORGA}::text || ''/'' || {TA2}::text || ''/foto1.jpg'', ''image/jpeg'', 1000) returning 1) select count(*)::text from i'), '1');
    perform pg_temp.expect('control positivo: con evidencia el voluntariado cierra la tarea', VOL, 'authenticated',
        pg_temp.q('with u as (update public.task set status = ''done'' where id = {TA2} returning 1) select count(*)::text from u'), '1');
    perform pg_temp.expect('no se sube evidencia a una tarea ya cerrada', VOL, 'authenticated',
        pg_temp.q('with i as (insert into public.task_evidence (organization_id, task_id, storage_path, mime_type, size_bytes) values ({ORGA}, {TA2}, {ORGA}::text || ''/'' || {TA2}::text || ''/foto2.jpg'', ''image/jpeg'', 1000) returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('voluntariado no reabre una tarea cerrada', VOL, 'authenticated',
        pg_temp.q('with u as (update public.task set status = ''in_progress'' where id = {TA2} returning 1) select count(*)::text from u'), 'ERR:TK002');
    perform pg_temp.expect('control positivo: la coordinación reabre una tarea cerrada', TM, 'authenticated',
        pg_temp.q('with u as (update public.task set status = ''in_progress'' where id = {TA2} returning 1) select count(*)::text from u'), '1');
    perform pg_temp.expect('al reabrir se borra la marca de cierre', null, null,
        pg_temp.q('select (done_at is null and started_at is not null)::text from public.task where id = {TA2}'), 'true');
    perform pg_temp.expect('voluntariado sin evidencia no cierra la tarea que la exige', VOL2, 'authenticated',
        pg_temp.q('with u as (update public.task set status = ''done'' where id = {TA11} returning 1) select count(*)::text from u'), 'ERR:TK003');
    perform pg_temp.expect('control positivo: la coordinación cierra sin foto (decisión de producto)', TM, 'authenticated',
        pg_temp.q('with u as (update public.task set status = ''done'' where id = {TA11} returning 1) select count(*)::text from u'), '1');
    perform pg_temp.expect('las marcas de tiempo no se falsifican con sesión', VOL, 'authenticated',
        pg_temp.q('with u as (update public.task set status = ''done'', done_at = timestamptz ''2000-01-01'' where id = {TA6} returning done_at) select (done_at > timestamptz ''2020-01-01'')::text from u'), 'true');

    -- ----- Ajustes de operación
    perform pg_temp.expect('voluntariado no cambia los ajustes', VOL, 'authenticated',
        $q$select count(*)::text from (select public.fn_update_task_setting('all', 30, 0, 1)) x$q$, 'ERR:TK010');
    perform pg_temp.expect('la coordinación de tareas no cambia los ajustes', TM, 'authenticated',
        $q$select count(*)::text from (select public.fn_update_task_setting('all', 30, 0, 1)) x$q$, 'ERR:TK010');
    perform pg_temp.expect('caseworker no cambia los ajustes', CW, 'authenticated',
        $q$select count(*)::text from (select public.fn_update_task_setting('all', 30, 0, 1)) x$q$, 'ERR:TK010');
    perform pg_temp.expect('anon no cambia los ajustes', null, 'anon',
        $q$select count(*)::text from (select public.fn_update_task_setting('all', 30, 0, 1)) x$q$, 'ERR');
    perform pg_temp.expect('alcance de notas inválido se rechaza', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_update_task_setting('todos', 30, 0, 1)) x$q$, 'ERR:TK024');
    perform pg_temp.expect('un tope negativo se rechaza', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_update_task_setting('all', 30, -1, 1)) x$q$, 'ERR:TK024');
    perform pg_temp.expect('el director no edita los ajustes con UPDATE directo', DIR, 'authenticated',
        $q$with u as (update public.task_setting set pool_max_unstarted = 9 returning 1) select count(*)::text from u$q$, 'ERR');
    perform pg_temp.expect('el director no inserta ajustes con INSERT directo', DIR, 'authenticated',
        pg_temp.q('with i as (insert into public.task_setting (organization_id) values ({ORGA}) returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('cambiar los ajustes de A no toca los de B', null, null,
        pg_temp.q('select (pool_max_unstarted = 0 and pool_release_days = 1 and shift_note_scope = ''all'')::text from public.task_setting where organization_id = {ORGB}'), 'true');
    perform pg_temp.expect('cada organización nace con sus ajustes', null, null,
        $q$with o as (insert into public.organization (id, slug, legal_name, display_name, active) values ('cccccccc-0000-0000-0000-00000000000c', 'tst-c', 'Org C', 'Org C', true) returning 1)
           select count(*)::text from o$q$, '1');
    perform pg_temp.expect('la organización nueva tiene su fila de ajustes por omisión', null, null,
        $q$select count(*)::text from public.task_setting where organization_id = 'cccccccc-0000-0000-0000-00000000000c'$q$, '1');

    -- ----- Notas de turno
    perform pg_temp.expect('control positivo: el voluntariado deja una nota de turno', VOL, 'authenticated',
        pg_temp.q('with i as (insert into public.shift_note (organization_id, body) values ({ORGA}, ''Se acabó el cloro'') returning 1) select count(*)::text from i'), '1');
    perform pg_temp.expect('la autoría de la nota se sella, no se declara', VOL, 'authenticated',
        pg_temp.q('with i as (insert into public.shift_note (organization_id, body, created_by) values ({ORGA}, ''Suplantada'', {VOL2}) returning created_by) select (created_by = {VOL})::text from i'), 'true');
    perform pg_temp.expect('una nota no se crea en otra organización', VOL, 'authenticated',
        pg_temp.q('with i as (insert into public.shift_note (organization_id, body) values ({ORGB}, ''x'') returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('una nota vacía se rechaza', VOL, 'authenticated',
        pg_temp.q('with i as (insert into public.shift_note (organization_id, body) values ({ORGA}, ''   '') returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('el texto de una nota no se edita', VOL, 'authenticated',
        pg_temp.q('with u as (update public.shift_note set body = ''editada'' where id = {NA} returning 1) select count(*)::text from u'), 'ERR:TK023');
    perform pg_temp.expect('la coordinación tampoco edita el texto de una nota', TM, 'authenticated',
        pg_temp.q('with u as (update public.shift_note set body = ''editada'' where id = {NA} returning 1) select count(*)::text from u'), 'ERR:TK023');
    perform pg_temp.expect('otra persona del voluntariado no retira la nota ajena', VOL2, 'authenticated',
        pg_temp.q('with u as (update public.shift_note set archived_at = now() where id = {NA} returning 1) select count(*)::text from u'), '0|ERR');
    perform pg_temp.expect('el voluntariado de B no ve las notas de A', VOLB, 'authenticated',
        pg_temp.q('select count(*)::text from public.shift_note where organization_id = {ORGA}'), '0');
    perform pg_temp.expect('el texto de la nota no se copia a la auditoría', null, null,
        $q$select count(*)::text from public.audit_event where table_name = 'shift_note' and new_values ? 'body'$q$, '0');
    perform pg_temp.expect('la nota sí deja evento de auditoría', null, null,
        $q$select count(*)::text from public.audit_event where table_name = 'shift_note' and action = 'INSERT'$q$, '>0');
    perform pg_temp.expect('control positivo: el director limita las notas a las propias', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_update_task_setting('own', 30, 0, 1)) x$q$, '1');
    perform pg_temp.expect('alcance «propias»: quien no escribió no ve notas de otros', VOL2, 'authenticated',
        'select count(*)::text from public.shift_note', '0');
    perform pg_temp.expect('alcance «propias»: la autora ve las suyas', VOL, 'authenticated',
        'select count(*)::text from public.shift_note', '>0');
    perform pg_temp.expect('alcance «propias»: la coordinación siempre ve todas', TM, 'authenticated',
        'select count(*)::text from public.shift_note', '>0');
    perform pg_temp.expect('el director limita las notas al área de trabajo', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_update_task_setting('area', 30, 0, 1)) x$q$, '1');
    perform pg_temp.expect('alcance «área»: quien trabaja en esa área ve la nota', VOL, 'authenticated',
        pg_temp.q('select count(*)::text from public.shift_note where id = {NA}'), '1');
    perform pg_temp.expect('alcance «área»: quien aún no tiene tareas en esa área no la ve', VOL2, 'authenticated',
        pg_temp.q('select count(*)::text from public.shift_note where id = {NA}'), '0');
    perform pg_temp.expect('el director abre de nuevo la lectura de notas', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_update_task_setting('all', 30, 0, 1)) x$q$, '1');
    perform pg_temp.expect('control positivo: la autora retira su nota (baja lógica)', VOL, 'authenticated',
        pg_temp.q('with u as (update public.shift_note set archived_at = now() where id = {NA} returning 1) select count(*)::text from u'), '1');
    perform pg_temp.expect('una nota retirada ya no la ve el voluntariado', VOL2, 'authenticated',
        pg_temp.q('select count(*)::text from public.shift_note where id = {NA}'), '0');
    perform pg_temp.expect('la autora conserva la vista de la nota que retiró', VOL, 'authenticated',
        pg_temp.q('select count(*)::text from public.shift_note where id = {NA}'), '1');
    perform pg_temp.expect('la coordinación aún ve la nota retirada', TM, 'authenticated',
        pg_temp.q('select count(*)::text from public.shift_note where id = {NA}'), '1');
    perform pg_temp.expect('una nota retirada no se modifica ni se restaura', null, null,
        pg_temp.q('with u as (update public.shift_note set archived_at = null where id = {NA} returning 1) select count(*)::text from u'), 'ERR:TK009');

    -- ----- Evidencia fotográfica
    perform pg_temp.expect('control positivo: el voluntariado ve la evidencia de su tarea', VOL, 'authenticated',
        pg_temp.q('select count(*)::text from public.task_evidence where id = {EVA}'), '1');
    perform pg_temp.expect('otra persona no ve la evidencia de una tarea ajena', VOL2, 'authenticated',
        pg_temp.q('select count(*)::text from public.task_evidence where id = {EVA}'), '0');
    perform pg_temp.expect('viewer no ve evidencia', VW, 'authenticated', 'select count(*)::text from public.task_evidence', '0');
    perform pg_temp.expect('control positivo: la coordinación ve la evidencia', TM, 'authenticated',
        pg_temp.q('select count(*)::text from public.task_evidence where id = {EVA}'), '1');
    perform pg_temp.expect('el voluntariado no sustituye una evidencia', VOL, 'authenticated',
        pg_temp.q('with u as (update public.task_evidence set storage_path = ''otra'' where id = {EVA} returning 1) select count(*)::text from u'), 'ERR|0');
    perform pg_temp.expect('la coordinación tampoco edita una evidencia', TM, 'authenticated',
        pg_temp.q('with u as (update public.task_evidence set size_bytes = 1 where id = {EVA} returning 1) select count(*)::text from u'), 'ERR:TK023');
    perform pg_temp.expect('control positivo: acceso a la evidencia devuelve la ruta', VOL, 'authenticated',
        pg_temp.q('select (public.fn_task_evidence_access({EVA}) like ''%/inicial.jpg'')::text'), 'true');
    perform pg_temp.expect('el acceso a la evidencia deja evento de auditoría', null, null,
        pg_temp.q('select count(*)::text from public.audit_event where action = ''EVIDENCE_ACCESS'' and record_id = {EVA}'), '1');
    perform pg_temp.expect('quien no tiene la tarea no obtiene la ruta de la evidencia', VOL2, 'authenticated',
        pg_temp.q('select public.fn_task_evidence_access({EVA})::text'), 'ERR:TK010');
    perform pg_temp.expect('viewer no obtiene la ruta de la evidencia', VW, 'authenticated',
        pg_temp.q('select public.fn_task_evidence_access({EVA})::text'), 'ERR:TK010');
    perform pg_temp.expect('otra organización no obtiene la ruta de la evidencia', DIRB, 'authenticated',
        pg_temp.q('select public.fn_task_evidence_access({EVA})::text'), 'ERR:TK011');
    perform pg_temp.expect('anon no obtiene la ruta de la evidencia', null, 'anon',
        pg_temp.q('select public.fn_task_evidence_access({EVA})::text'), 'ERR');

    -- Storage: bucket privado, sin actualización ni borrado
    perform pg_temp.expect('el bucket de evidencia es privado', null, null,
        $q$select "public"::text from storage.buckets where id = 'task-evidence'$q$, 'false');
    perform pg_temp.expect('el bucket limita el tamaño a 5 MB', null, null,
        $q$select file_size_limit::text from storage.buckets where id = 'task-evidence'$q$, '5242880');
    perform pg_temp.expect('control positivo: el voluntariado sube un archivo a su tarea', VOL, 'authenticated',
        pg_temp.q('with i as (insert into storage.objects (bucket_id, name) values (''task-evidence'', {ORGA}::text || ''/'' || {TA1}::text || ''/f2.jpg'') returning 1) select count(*)::text from i'), '1');
    perform pg_temp.expect('no se sube un archivo a la tarea de otra persona', VOL, 'authenticated',
        pg_temp.q('with i as (insert into storage.objects (bucket_id, name) values (''task-evidence'', {ORGA}::text || ''/'' || {TA4}::text || ''/f.jpg'') returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('no se sube un archivo bajo la ruta de otra organización', VOL, 'authenticated',
        pg_temp.q('with i as (insert into storage.objects (bucket_id, name) values (''task-evidence'', {ORGB}::text || ''/'' || {TB1}::text || ''/f.jpg'') returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('viewer no sube archivos de evidencia', VW, 'authenticated',
        pg_temp.q('with i as (insert into storage.objects (bucket_id, name) values (''task-evidence'', {ORGA}::text || ''/'' || {TA1}::text || ''/v.jpg'') returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('anon no sube archivos de evidencia', null, 'anon',
        pg_temp.q('with i as (insert into storage.objects (bucket_id, name) values (''task-evidence'', {ORGA}::text || ''/'' || {TA1}::text || ''/a.jpg'') returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('control positivo: el voluntariado ve el archivo de su tarea', VOL, 'authenticated',
        pg_temp.q('select count(*)::text from storage.objects where bucket_id = ''task-evidence'' and name like {ORGA}::text || ''/'' || {TA1}::text || ''/%'''), '>0');
    perform pg_temp.expect('otra persona no ve el archivo de una tarea ajena', VOL2, 'authenticated',
        pg_temp.q('select count(*)::text from storage.objects where bucket_id = ''task-evidence'' and name like {ORGA}::text || ''/'' || {TA1}::text || ''/%'''), '0');
    perform pg_temp.expect('otra organización no ve el archivo', VOLB, 'authenticated',
        pg_temp.q('select count(*)::text from storage.objects where bucket_id = ''task-evidence'' and name like {ORGA}::text || ''/%'''), '0');
    perform pg_temp.expect('control positivo: la coordinación ve los archivos de evidencia', TM, 'authenticated',
        pg_temp.q('select count(*)::text from storage.objects where bucket_id = ''task-evidence'' and name like {ORGA}::text || ''/%'''), '>0');
    perform pg_temp.expect('nadie sustituye un archivo de evidencia', VOL, 'authenticated',
        pg_temp.q('with u as (update storage.objects set name = {ORGA}::text || ''/'' || {TA1}::text || ''/x.jpg'' where bucket_id = ''task-evidence'' returning 1) select count(*)::text from u'), 'ERR|0');
    perform pg_temp.expect('nadie borra un archivo de evidencia', TM, 'authenticated',
        $q$with d as (delete from storage.objects where bucket_id = 'task-evidence' returning 1) select count(*)::text from d$q$, 'ERR|0');

    -- ----- Baja lógica: archivar, no borrar
    perform pg_temp.expect('control positivo: la coordinación archiva una tarea', TM, 'authenticated',
        pg_temp.q('with u as (update public.task set archived_at = now() where id = {TA10} returning 1) select count(*)::text from u'), '1');
    perform pg_temp.expect('quien tenía la tarea archivada ya no la ve', VOL2, 'authenticated',
        pg_temp.q('select count(*)::text from public.task where id = {TA10}'), '0');
    perform pg_temp.expect('la coordinación aún ve la tarea archivada', TM, 'authenticated',
        pg_temp.q('select count(*)::text from public.task where id = {TA10}'), '1');
    perform pg_temp.expect('la baja deja al archivador como autor', null, null,
        pg_temp.q('select (archived_by = {TM}::uuid)::text from public.task where id = {TA10}'), 'true');
    perform pg_temp.expect('una tarea archivada no se modifica', TM, 'authenticated',
        pg_temp.q('with u as (update public.task set name = ''x'' where id = {TA10} returning 1) select count(*)::text from u'), 'ERR:TK009');
    perform pg_temp.expect('disparador: ni el propietario restaura una tarea archivada', null, null,
        pg_temp.q('with u as (update public.task set archived_at = null where id = {TA10} returning 1) select count(*)::text from u'), 'ERR:TK009');
    perform pg_temp.expect('caseworker no archiva tareas', CW, 'authenticated',
        pg_temp.q('with u as (update public.task set archived_at = now() where id = {TA7} returning 1) select count(*)::text from u'), 'ERR|0');
    perform pg_temp.expect('control positivo: el director archiva una tarea', DIR, 'authenticated',
        pg_temp.q('with u as (update public.task set archived_at = now() where id = {TA4} returning 1) select count(*)::text from u'), '1');
    perform pg_temp.expect('control positivo: el director crea una categoría', DIR, 'authenticated',
        pg_temp.q('with i as (insert into public.task_category (organization_id, key, label_es) values ({ORGA}, ''cocina_x'', ''Cocina X'') returning 1) select count(*)::text from i'), '1');
    perform pg_temp.expect('la coordinación no crea categorías', TM, 'authenticated',
        pg_temp.q('with i as (insert into public.task_category (organization_id, key, label_es) values ({ORGA}, ''otra'', ''Otra'') returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('el voluntariado no edita las áreas de trabajo', VOL, 'authenticated',
        pg_temp.q('with u as (update public.work_area set label_es = ''x'' where id = {WAA} returning 1) select count(*)::text from u'), 'ERR|0');
    perform pg_temp.expect('una categoría repetida se rechaza', DIR, 'authenticated',
        pg_temp.q('with i as (insert into public.task_category (organization_id, key, label_es) values ({ORGA}, ''limpieza'', ''Otra'') returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('la clave de un catálogo debe ser estable y en minúsculas', DIR, 'authenticated',
        pg_temp.q('with i as (insert into public.task_category (organization_id, key, label_es) values ({ORGA}, ''Mala Clave'', ''x'') returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('la organización de un registro no cambia', null, null,
        pg_temp.q('with u as (update public.task set organization_id = {ORGB} where id = {TA1} returning 1) select count(*)::text from u'), 'ERR:TK008');

    -- ----- Auditoría y privilegios
    perform pg_temp.expect('toda escritura de tareas deja auditoría: alta', null, null,
        $q$select count(*)::text from public.audit_event where table_name = 'task' and action = 'INSERT'$q$, '>0');
    perform pg_temp.expect('toda escritura de tareas deja auditoría: avance y pool', null, null,
        $q$select count(*)::text from public.audit_event where table_name = 'task' and action = 'UPDATE'$q$, '>0');
    perform pg_temp.expect('el cambio de ajustes deja auditoría', null, null,
        $q$select count(*)::text from public.audit_event where table_name = 'task_setting' and action = 'UPDATE'$q$, '>0');
    perform pg_temp.expect('el archivo de una categoría o tarea deja auditoría', null, null,
        pg_temp.q('select count(*)::text from public.audit_event where table_name = ''task'' and record_id = {TA10} and action = ''UPDATE'''), '>0');
    perform pg_temp.expect('anon no tiene privilegios sobre las tablas de tareas', null, null,
        $q$select count(*)::text from information_schema.role_table_grants
           where table_schema = 'public' and grantee = 'anon'
             and table_name in ('task','task_category','work_area','task_evidence','routine_template','routine_template_item','shift_note','task_setting')$q$, '0');
    perform pg_temp.expect('nadie escribe los ajustes por privilegio directo', null, null,
        $q$select count(*)::text from information_schema.role_table_grants
           where table_schema = 'public' and table_name = 'task_setting' and grantee = 'authenticated'
             and privilege_type in ('INSERT','UPDATE')$q$, '0');
    foreach t in array array[
        'select public.fn_release_expired_claims()::text',
        'select public.fn_claim_open_task(''aaaaaaaa-a000-0000-0000-000000000003'')::text',
        'select public.fn_release_task(''aaaaaaaa-a000-0000-0000-000000000003'')::text',
        'select public.fn_start_routine(''aaaaaaaa-9200-0000-0000-000000000001'')::text',
        'select public.fn_update_task_setting(''all'', 30, 0, 1)::text',
        'select public.fn_task_evidence_access(''aaaaaaaa-9400-0000-0000-000000000001'')::text'
    ] loop
        perform pg_temp.expect('anon no ejecuta ' || split_part(split_part(t, 'public.', 2), '(', 1), null, 'anon', t, 'ERR');
        perform pg_temp.expect('sin rol no ejecuta ' || split_part(split_part(t, 'public.', 2), '(', 1), NR, 'authenticated', t, 'ERR');
        perform pg_temp.expect('viewer no ejecuta ' || split_part(split_part(t, 'public.', 2), '(', 1), VW, 'authenticated', t, 'ERR');
    end loop;

    -- ===== Vínculo tarea–caso (migración 20261009000007, BV-7.16, decisión 6a)
    -- Control positivo primero: quien opera expedientes crea una tarea ligada y la asigna.
    perform pg_temp.expect('control positivo: el caseworker crea una tarea ligada a su caso', CW, 'authenticated',
        pg_temp.q('select (public.fn_create_case_task({CASEA}, {KA}, {VOL}))::text is not null'), 'true');
    perform pg_temp.expect('la tarea ligada recibe el folio del caso', null, null,
        pg_temp.q('select case_number from public.task where case_id = {CASEA} and assigned_to = {VOL}'), 'TST-A-0001');
    perform pg_temp.expect('el nombre de la tarea ligada sale del catálogo neutro', null, null,
        pg_temp.q('select name from public.task where case_id = {CASEA} and assigned_to = {VOL}'), 'Acompañamiento');
    perform pg_temp.expect('la tarea ligada no tiene texto libre', null, null,
        pg_temp.q('select (details is null)::text from public.task where case_id = {CASEA} and assigned_to = {VOL}'), 'true');
    perform pg_temp.expect('control positivo: el voluntariado ve su tarea ligada con el folio', VOL, 'authenticated',
        pg_temp.q('select case_number from public.task where case_id is not null'), 'TST-A-0001');
    perform pg_temp.expect('el voluntariado con una tarea ligada no lee ni una fila de case', VOL, 'authenticated',
        'select count(*)::text from public."case"', '0');
    perform pg_temp.expect('el voluntariado con una tarea ligada no lee ni una fila de person', VOL, 'authenticated',
        'select count(*)::text from public.person', '0');
    perform pg_temp.expect('el voluntariado no lee el caso por identificador', VOL, 'authenticated',
        pg_temp.q('select count(*)::text from public."case" where id = {CASEA}'), '0');
    perform pg_temp.expect('la coordinación de tareas ve el folio de la tarea ligada', TM, 'authenticated',
        pg_temp.q('select case_number from public.task where case_id = {CASEA} and assigned_to = {VOL}'), 'TST-A-0001');
    perform pg_temp.expect('la coordinación de tareas no lee case ni person', TM, 'authenticated',
        'select ((select count(*) from public."case") + (select count(*) from public.person))::text', '0');

    -- Quien opera expedientes lista las tareas de sus casos; el resto no gana lectura
    perform pg_temp.expect('control positivo: el caseworker ve las tareas ligadas', CW, 'authenticated',
        'select count(*)::text from public.task where case_id is not null', '>0');
    perform pg_temp.expect('el caseworker no gana lectura de tareas ajenas fuera del pool', CW, 'authenticated',
        'select count(*)::text from public.task where case_id is null and assigned_to is distinct from auth.uid() and not (assigned_to is null and status = ''pending'')', '0');
    perform pg_temp.expect('intake ve las tareas ligadas', INT, 'authenticated',
        'select count(*)::text from public.task where case_id is not null', '>0');
    perform pg_temp.expect('viewer no ve tareas ligadas', VW, 'authenticated',
        'select count(*)::text from public.task where case_id is not null', '0');
    perform pg_temp.expect('otra organización no ve tareas ligadas de A', DIRB, 'authenticated',
        pg_temp.q('select count(*)::text from public.task where organization_id = {ORGA}'), '0');
    perform pg_temp.expect('otro voluntariado no ve la tarea ligada de otra persona', VOL2, 'authenticated',
        'select count(*)::text from public.task where case_id is not null', '0');

    -- Quién no vincula
    perform pg_temp.expect('la coordinación de tareas no crea tareas ligadas', TM, 'authenticated',
        pg_temp.q('select public.fn_create_case_task({CASEA}, {KA}, {VOL})::text'), 'ERR:TK026');
    perform pg_temp.expect('la coordinación de tareas no liga una tarea existente', TM, 'authenticated',
        pg_temp.q('select public.fn_set_task_case({TA3}, {CASEA}, {KA})::text'), 'ERR:TK026');
    perform pg_temp.expect('el voluntariado no crea tareas ligadas', VOL, 'authenticated',
        pg_temp.q('select public.fn_create_case_task({CASEA}, {KA}, {VOL})::text'), 'ERR:TK026');
    perform pg_temp.expect('el voluntariado no liga su propia tarea', VOL, 'authenticated',
        pg_temp.q('select public.fn_set_task_case({TA6}, {CASEA}, {KA})::text'), 'ERR:TK026');
    perform pg_temp.expect('viewer no crea tareas ligadas', VW, 'authenticated',
        pg_temp.q('select public.fn_create_case_task({CASEA}, {KA}, {VOL})::text'), 'ERR:TK026');
    perform pg_temp.expect('sin rol no crea tareas ligadas', NR, 'authenticated',
        pg_temp.q('select public.fn_create_case_task({CASEA}, {KA}, {VOL})::text'), 'ERR');
    perform pg_temp.expect('anon no crea tareas ligadas', null, 'anon',
        pg_temp.q('select public.fn_create_case_task({CASEA}, {KA}, {VOL})::text'), 'ERR');
    perform pg_temp.expect('anon no liga tareas', null, 'anon',
        pg_temp.q('select public.fn_set_task_case({TA3}, {CASEA}, {KA})::text'), 'ERR');

    -- Las columnas de vínculo no se escriben a mano, ni siquiera por quien edita tareas
    perform pg_temp.expect('la coordinación no escribe case_id directo', TM, 'authenticated',
        pg_temp.q('with u as (update public.task set case_id = {CASEA} where id = {TA3} returning 1) select count(*)::text from u'), 'ERR:TK025');
    perform pg_temp.expect('el voluntariado no escribe case_id en su tarea', VOL, 'authenticated',
        pg_temp.q('with u as (update public.task set case_id = {CASEA} where id = {TA6} returning 1) select count(*)::text from u'), 'ERR:TK025');
    perform pg_temp.expect('la coordinación no crea una tarea ya ligada por insert directo', TM, 'authenticated',
        pg_temp.q('with i as (insert into public.task (organization_id, name, case_id, case_task_kind_id) values ({ORGA}, ''x'', {CASEA}, {KA}) returning 1) select count(*)::text from i'), 'ERR:TK025');
    perform pg_temp.expect('el folio copiado no se edita', TM, 'authenticated',
        pg_temp.q('with u as (update public.task set case_number = ''OTRO-0001'' where case_id = {CASEA} returning 1) select count(*)::text from u'), 'ERR:TK025');
    perform pg_temp.expect('la coordinación no cambia el nombre de una tarea ligada', TM, 'authenticated',
        pg_temp.q('with u as (update public.task set name = ''Cita médica'' where case_id = {CASEA} returning 1) select count(*)::text from u'), 'ERR:TK025');
    perform pg_temp.expect('la coordinación no agrega texto libre a una tarea ligada', TM, 'authenticated',
        pg_temp.q('with u as (update public.task set details = ''Cita en el hospital'' where case_id = {CASEA} returning 1) select count(*)::text from u'), 'ERR:TK025');
    perform pg_temp.expect('el voluntariado no cambia el nombre de su tarea ligada', VOL, 'authenticated',
        pg_temp.q('with u as (update public.task set name = ''x'' where case_id = {CASEA} returning 1) select count(*)::text from u'), 'ERR');
    perform pg_temp.expect('la base rechaza texto libre en una tarea ligada aun sin sesión', null, null,
        pg_temp.q('with u as (update public.task set details = ''x'' where case_id = {CASEA} returning 1) select count(*)::text from u'), 'ERR:23514');
    perform pg_temp.expect('control positivo: el voluntariado avanza su tarea ligada', VOL, 'authenticated',
        pg_temp.q('with u as (update public.task set status = ''in_progress'' where case_id = {CASEA} and assigned_to = {VOL} returning 1) select count(*)::text from u'), '1');

    -- Validaciones de origen
    perform pg_temp.expect('el caso de otra organización no se liga', DIR, 'authenticated',
        pg_temp.q('select public.fn_create_case_task({CASEB}, {KA}, {VOL})::text'), 'ERR:TK027');
    perform pg_temp.expect('el tipo de otra organización no se usa', DIR, 'authenticated',
        pg_temp.q('select public.fn_create_case_task({CASEA}, {KB}, {VOL})::text'), 'ERR:TK027');
    perform pg_temp.expect('un caso inexistente se rechaza', DIR, 'authenticated',
        pg_temp.q('select public.fn_create_case_task(''aaaaaaaa-5000-0000-0000-0000000000ff'', {KA}, {VOL})::text'), 'ERR:TK027');
    perform pg_temp.expect('otra organización no liga una tarea de A', DIRB, 'authenticated',
        pg_temp.q('select public.fn_set_task_case({TA3}, {CASEB}, {KB})::text'), 'ERR:TK011');
    perform pg_temp.expect('no se liga sin elegir el tipo', DIR, 'authenticated',
        pg_temp.q('select public.fn_set_task_case({TA3}, {CASEA})::text'), 'ERR:TK027');
    perform pg_temp.expect('no se asigna una tarea ligada a quien no tiene acceso a tareas', CW, 'authenticated',
        pg_temp.q('select public.fn_create_case_task({CASEA}, {KA}, {VW})::text'), 'ERR:TK007');
    perform pg_temp.expect('se crea un tipo temporal para probar el archivo', DIR, 'authenticated',
        pg_temp.q('with i as (insert into public.case_task_kind (id, organization_id, key, label_es) values (''aaaaaaaa-9600-0000-0000-0000000000f1'', {ORGA}, ''temporal'', ''Temporal'') returning 1) select count(*)::text from i'), '1');
    perform pg_temp.expect('se archiva el tipo temporal', DIR, 'authenticated',
        pg_temp.q('with u as (update public.case_task_kind set archived_at = now() where id = ''aaaaaaaa-9600-0000-0000-0000000000f1'' returning 1) select count(*)::text from u'), '1');
    perform pg_temp.expect('un tipo archivado no se usa', DIR, 'authenticated',
        pg_temp.q('select public.fn_create_case_task({CASEA}, ''aaaaaaaa-9600-0000-0000-0000000000f1'', {VOL})::text'), 'ERR:TK027');

    -- El pool no incluye lo vinculado
    perform pg_temp.expect('control positivo: la dirección crea una tarea ligada sin asignar', DIR, 'authenticated',
        pg_temp.q('select (public.fn_create_case_task({CASEA}, {KA}, null))::text is not null'), 'true');
    perform pg_temp.expect('la tarea ligada sin asignar no aparece en el pool', VOL2, 'authenticated',
        pg_temp.q('select count(*)::text from public.task where case_id is not null'), '0');
    perform pg_temp.expect('control positivo: sí hay pool para el voluntariado', VOL2, 'authenticated',
        'select count(*)::text from public.task where assigned_to is null', '>0');
    perform pg_temp.expect('el voluntariado no toma una tarea ligada del pool', VOL2, 'authenticated',
        pg_temp.q('select public.fn_claim_open_task((select id from public.task where case_id = {CASEA} and assigned_to is null limit 1))::text'), 'ERR');
    perform pg_temp.expect('la tarea ligada sigue sin dueño tras el intento', null, null,
        pg_temp.q('select count(*)::text from public.task where case_id = {CASEA} and assigned_to is null'), '1');
    perform pg_temp.expect('la coordinación sí ve la tarea ligada sin asignar', TM, 'authenticated',
        pg_temp.q('select count(*)::text from public.task where case_id = {CASEA} and assigned_to is null'), '1');
    perform pg_temp.expect('control positivo: la coordinación la asigna', TM, 'authenticated',
        pg_temp.q('with u as (update public.task set assigned_to = {VOL2} where case_id = {CASEA} and assigned_to is null returning 1) select count(*)::text from u'), '1');
    perform pg_temp.expect('la persona asignada ya ve su tarea ligada', VOL2, 'authenticated',
        pg_temp.q('select case_number from public.task where case_id is not null'), 'TST-A-0001');

    -- Desvincular y volver a vincular, con su rastro de auditoría
    -- El caseworker no ve tareas (no es gestión ni asignado): el identificador se toma como propietario
    declare
        v_linked uuid;
    begin
        select id into v_linked from public.task where case_id = 'aaaaaaaa-5000-0000-0000-000000000001' and assigned_to = VOL::uuid;
        perform pg_temp.expect('control positivo: el caseworker desvincula una tarea', CW, 'authenticated',
            format('select count(*)::text from (select public.fn_set_task_case(%L, null)) x', v_linked), '1');
        perform pg_temp.expect('desvincular limpia el folio', null, null,
            format('select count(*)::text from public.task where id = %L and (case_id is not null or case_number is not null or case_task_kind_id is not null)', v_linked), '0');
        perform pg_temp.expect('el voluntariado deja de ver el folio de la tarea desvinculada', VOL, 'authenticated',
            'select count(*)::text from public.task where case_number is not null', '0');
        perform pg_temp.expect('control positivo: el caseworker vuelve a vincularla', CW, 'authenticated',
            format('select count(*)::text from (select public.fn_set_task_case(%L, %L, %L)) x', v_linked, 'aaaaaaaa-5000-0000-0000-000000000001', 'aaaaaaaa-9600-0000-0000-000000000001'), '1');
    end;
    perform pg_temp.expect('vincular y desvincular dejan auditoría con el valor anterior y el nuevo', null, null,
        $q$select count(*)::text from public.audit_event
           where table_name = 'task' and action = 'UPDATE'
             and (old_values ->> 'case_id') is distinct from (new_values ->> 'case_id')$q$, '>0');
    perform pg_temp.expect('la creación de una tarea ligada deja auditoría con el caso', null, null,
        pg_temp.q('select count(*)::text from public.audit_event where table_name = ''task'' and action = ''INSERT'' and new_values ->> ''case_id'' = {CASEA}::text'), '>0');

    -- Catálogo neutro: lo administra la dirección
    perform pg_temp.expect('control positivo: la dirección agrega un tipo', DIR, 'authenticated',
        pg_temp.q('with i as (insert into public.case_task_kind (organization_id, key, label_es) values ({ORGA}, ''gestion_x'', ''Gestión X'') returning 1) select count(*)::text from i'), '1');
    perform pg_temp.expect('la coordinación no agrega tipos', TM, 'authenticated',
        pg_temp.q('with i as (insert into public.case_task_kind (organization_id, key, label_es) values ({ORGA}, ''otro'', ''Otro'') returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('el caseworker no agrega tipos', CW, 'authenticated',
        pg_temp.q('with i as (insert into public.case_task_kind (organization_id, key, label_es) values ({ORGA}, ''otro2'', ''Otro'') returning 1) select count(*)::text from i'), 'ERR');
    perform pg_temp.expect('el voluntariado no edita tipos', VOL, 'authenticated',
        pg_temp.q('with u as (update public.case_task_kind set label_es = ''x'' where id = {KA} returning 1) select count(*)::text from u'), 'ERR|0');
    perform pg_temp.expect('el caseworker lee los tipos para elegir', CW, 'authenticated',
        'select count(*)::text from public.case_task_kind', '>0');
    perform pg_temp.expect('el voluntariado lee los tipos vigentes', VOL, 'authenticated',
        'select count(*)::text from public.case_task_kind', '>0');
    perform pg_temp.expect('otra organización no ve los tipos de A', DIRB, 'authenticated',
        pg_temp.q('select count(*)::text from public.case_task_kind where organization_id = {ORGA}'), '0');
    perform pg_temp.expect('viewer no lee los tipos', VW, 'authenticated',
        'select count(*)::text from public.case_task_kind', '0');
    perform pg_temp.expect('anon no tiene privilegios sobre el catálogo de tipos', null, null,
        $q$select count(*)::text from information_schema.role_table_grants
           where table_schema = 'public' and table_name = 'case_task_kind' and grantee = 'anon'$q$, '0');
    perform pg_temp.expect('nadie borra tipos (DELETE revocado)', null, null,
        $q$select has_table_privilege('authenticated', 'public.case_task_kind', 'DELETE')::text$q$, 'false');
    perform pg_temp.expect('el cambio de un tipo deja auditoría', null, null,
        $q$select count(*)::text from public.audit_event where table_name = 'case_task_kind'$q$, '>0');

    -- ----- Una cuenta desactivada pierde el acceso a tareas
    perform pg_temp.expect('se desactiva una cuenta', null, null,
        pg_temp.q('with u as (update public.user_profile set active = false where id = {VOL2} returning 1) select count(*)::text from u'), '1');
    perform pg_temp.expect('una cuenta desactivada no ve tareas', VOL2, 'authenticated', 'select count(*)::text from public.task', '0');
    perform pg_temp.expect('una cuenta desactivada no toma tareas', VOL2, 'authenticated',
        pg_temp.q('select public.fn_claim_open_task({TA3})::text'), 'ERR:TK010');
    perform pg_temp.expect('no se asigna una tarea a una cuenta desactivada', TM, 'authenticated',
        pg_temp.q('with u as (update public.task set assigned_to = {VOL2} where id = {TA9} returning 1) select count(*)::text from u'), 'ERR:TK007');
    perform pg_temp.expect('se reactiva la cuenta', null, null,
        pg_temp.q('with u as (update public.user_profile set active = true where id = {VOL2} returning 1) select count(*)::text from u'), '1');

    -- ===== Cuenta desactivada = sin acceso al expediente (migración 20261009000005)
    -- Antes de la migración los helpers sólo miraban user_role.revoked_at: una cuenta con
    -- active = false y roles sin revocar seguía leyendo y escribiendo. Cada negativa va
    -- precedida de su control positivo con LA MISMA sentencia, para que un rechazo no pueda
    -- deberse a otra causa (caso ya cerrado, dato ausente) y pasar por bueno.
    declare
        dis_read text[] := array[
            'select count(*)::text from public.person',
            'select count(*)::text from public."case"',
            'select count(*)::text from public.journal_entry',
            'select count(*)::text from public.consent',
            'select count(*)::text from public.case_status'
        ];
        w_cw text := 'select count(*)::text from (select public.fn_create_journal_entry(''aaaaaaaa-5000-0000-0000-000000000001''::uuid, ''note'', ''desactivada'', now(), false, ''aaaaaaaa-1000-0000-0000-000000000001''::uuid)) x';
        w_int text := 'select count(*)::text from (select public.fn_register_consent(''aaaaaaaa-4000-0000-0000-000000000001''::uuid, ''internal_sharing'', ''granted'')) x';
        w_dir text := 'select jsonb_array_length(public.fn_generate_arco_access_extract(''aaaaaaaa-4000-0000-0000-000000000001''::uuid)->''cases'')::text';
        w_met text := 'select jsonb_array_length(public.fn_aggregate_metrics()->''rows'')::text';
        r text;
        u text;
    begin
        -- Un segundo director vigente en A: sin él TK006 impediría desactivar a DIR
        perform pg_temp.expect('se agrega un segundo director a A', null, null,
            pg_temp.q($q$with a as (insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
                                   values ({DIRA2}, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'dir2@tst-a.invalid', now(), now()) returning id),
                              p as (insert into public.user_profile (id, organization_id, email, full_name, active)
                                    select id, {ORGA}, 'dir2@tst-a.invalid', 'Dir A2', true from a returning id),
                              r as (insert into public.user_role (user_id, role_name, granted_by, granted_at)
                                    select id, 'director', {DIR}, now() from p returning 1)
                         select count(*)::text from r$q$), '1');

        -- Controles positivos: con la cuenta activa todo esto funciona
        foreach r in array dis_read loop
            perform pg_temp.expect('cuenta activa: director lee (control) ' || r, DIR, 'authenticated', r, '>0');
            perform pg_temp.expect('cuenta activa: caseworker lee (control) ' || r, CW, 'authenticated', r, '>0');
            -- intake no lee la bitácora por diseño (area_private): su control es el resto
            if r not like '%journal_entry%' then
                perform pg_temp.expect('cuenta activa: intake lee (control) ' || r, INT, 'authenticated', r, '>0');
            end if;
        end loop;
        perform pg_temp.expect('cuenta activa: caseworker escribe en bitácora (control)', CW, 'authenticated', w_cw, '1');
        perform pg_temp.expect('cuenta activa: intake registra consentimiento (control)', INT, 'authenticated', w_int, '1');
        perform pg_temp.expect('cuenta activa: director emite extracto ARCO (control)', DIR, 'authenticated', w_dir, '1');
        perform pg_temp.expect('cuenta activa: director lee auditoría (control)', DIR, 'authenticated', 'select count(*)::text from public.audit_event', '>0');
        perform pg_temp.expect('cuenta activa: viewer obtiene indicadores (control)', VW, 'authenticated', w_met, 'OK');
        perform pg_temp.expect('cuenta activa: has_role(director) es verdadero (control)', DIR, 'authenticated', 'select public.has_role(''director'')::text', 'true');
        perform pg_temp.expect('cuenta activa: has_operational_role() es verdadero (control)', CW, 'authenticated', 'select public.has_operational_role()::text', 'true');
        perform pg_temp.expect('cuenta activa: has_role_in_area es verdadero (control)', CW, 'authenticated', 'select public.has_role_in_area(''caseworker'', ''trabajo_social'')::text', 'true');
        perform pg_temp.expect('cuenta activa: current_organization_id() existe (control)', DIR, 'authenticated', 'select (public.current_organization_id() is not null)::text', 'true');
        perform pg_temp.expect('cuenta activa: lee su perfil (control)', CW, 'authenticated', 'select count(*)::text from public.user_profile where id = auth.uid()', '1');

        -- Se desactivan cuentas CON sus roles intactos (es justo el caso del hallazgo)
        foreach u in array array[DIR, CW, INT, VW] loop
            perform pg_temp.expect('se desactiva la cuenta ' || right(u, 1) || ' sin revocar sus roles', null, null,
                format('with u as (update public.user_profile set active = false where id = %L returning 1) select count(*)::text from u', u), '1');
        end loop;
        perform pg_temp.expect('los roles de la cuenta desactivada siguen sin revocar', null, null,
            format('select count(*)::text from public.user_role where user_id = %L and revoked_at is null', DIR), '1');

        -- Negativas: lecturas
        foreach r in array dis_read loop
            perform pg_temp.expect('cuenta desactivada: director no lee ' || r, DIR, 'authenticated', r, '0');
            perform pg_temp.expect('cuenta desactivada: caseworker no lee ' || r, CW, 'authenticated', r, '0');
            if r not like '%journal_entry%' then
                perform pg_temp.expect('cuenta desactivada: intake no lee ' || r, INT, 'authenticated', r, '0');
            end if;
        end loop;
        perform pg_temp.expect('cuenta desactivada: director no lee auditoría', DIR, 'authenticated', 'select count(*)::text from public.audit_event', '0');
        perform pg_temp.expect('cuenta desactivada: director no lee requerimientos de autoridad', DIR, 'authenticated', 'select count(*)::text from public.authority_request', '0');
        perform pg_temp.expect('cuenta desactivada: director no ve su organización', DIR, 'authenticated', 'select count(*)::text from public.organization', '0');
        perform pg_temp.expect('cuenta desactivada: director no ve áreas', DIR, 'authenticated', 'select count(*)::text from public.area', '0');
        perform pg_temp.expect('cuenta desactivada: caseworker no ve perfiles (ni el propio)', CW, 'authenticated', 'select count(*)::text from public.user_profile', '0');
        perform pg_temp.expect('cuenta desactivada: caseworker no ve roles', CW, 'authenticated', 'select count(*)::text from public.user_role', '0');

        -- Negativas: escrituras por función SECURITY DEFINER
        perform pg_temp.expect('cuenta desactivada: caseworker no escribe en la bitácora', CW, 'authenticated', w_cw, 'ERR');
        perform pg_temp.expect('cuenta desactivada: intake no registra consentimiento', INT, 'authenticated', w_int, 'ERR');
        perform pg_temp.expect('cuenta desactivada: intake no abre casos', INT, 'authenticated', new_case, 'ERR');
        perform pg_temp.expect('cuenta desactivada: director no emite extracto ARCO', DIR, 'authenticated', w_dir, 'ERR');
        -- (su control positivo es «director anonimiza», al final del archivo)
        perform pg_temp.expect('cuenta desactivada: director no anonimiza', DIR, 'authenticated',
            'select count(*)::text from (select public.fn_anonymize_person(''aaaaaaaa-4000-0000-0000-000000000001''::uuid, ''x'')) x', 'ERR');
        perform pg_temp.expect('cuenta desactivada: viewer no obtiene indicadores', VW, 'authenticated', w_met, 'ERR');
        -- Los helpers mismos
        perform pg_temp.expect('cuenta desactivada: has_role(director) es falso', DIR, 'authenticated', 'select public.has_role(''director'')::text', 'false');
        perform pg_temp.expect('cuenta desactivada: has_role_in_area es falso', CW, 'authenticated', 'select public.has_role_in_area(''caseworker'', ''trabajo_social'')::text', 'false');
        perform pg_temp.expect('cuenta desactivada: has_operational_role() es falso', CW, 'authenticated', 'select public.has_operational_role()::text', 'false');
        perform pg_temp.expect('cuenta desactivada: has_any_role() es falso', VW, 'authenticated', 'select public.has_any_role()::text', 'false');
        perform pg_temp.expect('cuenta desactivada: has_active_role() es falso', CW, 'authenticated', 'select public.has_active_role()::text', 'false');
        perform pg_temp.expect('cuenta desactivada: current_organization_id() es nulo', DIR, 'authenticated', 'select (public.current_organization_id() is null)::text', 'true');

        -- Una cuenta desactivada no se auto-reactiva ni se reactiva a otra
        perform pg_temp.expect('cuenta desactivada: no se reactiva a sí misma', CW, 'authenticated',
            format('with u as (update public.user_profile set active = true where id = %L returning 1) select count(*)::text from u', CW), 'ERR|0');
        perform pg_temp.expect('cuenta desactivada: el director no reactiva cuentas', DIR, 'authenticated',
            format('with u as (update public.user_profile set active = true where id = %L returning 1) select count(*)::text from u', CW), 'ERR|0');

        -- Aislamiento: desactivar a unos no afecta a quienes siguen activos
        perform pg_temp.expect('el segundo director activo conserva su acceso', DIRA2, 'authenticated', 'select count(*)::text from public.person', '>0');
        perform pg_temp.expect('el segundo director activo conserva sus funciones', DIRA2, 'authenticated', w_dir, '1');
        perform pg_temp.expect('el voluntariado activo no gana acceso al expediente', VOL, 'authenticated', 'select count(*)::text from public.person', '0');

        -- TK006 sigue vigente: DIRA2 es ahora el único director activo de A
        perform pg_temp.expect('E16A: el único director activo de A no puede desactivar su cuenta por la función → BV343', DIRA2, 'authenticated',
            pg_temp.q($q$select count(*)::text from (select public.fn_set_user_active({DIRA2}, false, 'x')) x$q$), 'ERR:BV343');
        perform pg_temp.expect('TK006: el disparador sigue vigente a nivel de tabla: el único director activo de A no se desactiva', null, null,
            pg_temp.q('with u as (update public.user_profile set active = false where id = {DIRA2} returning 1) select count(*)::text from u'), 'ERR:TK006');

        -- Reactivar devuelve el acceso (las cuentas no quedan marcadas de forma permanente)
        foreach u in array array[DIR, CW, INT, VW] loop
            perform pg_temp.expect('se reactiva la cuenta ' || right(u, 1), null, null,
                format('with u as (update public.user_profile set active = true where id = %L returning 1) select count(*)::text from u', u), '1');
        end loop;
        perform pg_temp.expect('reactivada: el director vuelve a leer personas', DIR, 'authenticated', 'select count(*)::text from public.person', '>0');
        perform pg_temp.expect('reactivada: el caseworker vuelve a escribir en la bitácora', CW, 'authenticated', w_cw, '1');
    end;

    -- ============================================================================================
    -- ===== Endurecimiento 11 oct 2026 (reporte-auditoria-endurecimiento-2026-10-11.md)
    -- ===== C-1 organización en ARCO · C-2 auditoría sin datos personales · A-2 compartimentación
    -- ===== de la bitácora · A-3 estatus terminal y reapertura · M-1 search_path
    -- ============================================================================================
    declare
        CW2   constant text := 'aaaaaaaa-3000-0000-0000-00000000000a';  -- caseworker del área jurídica
        CW3   constant text := 'aaaaaaaa-3000-0000-0000-00000000000b';  -- caseworker del área de trabajo social (no autor)
        AR_TS constant text := 'aaaaaaaa-1000-0000-0000-000000000001';
        AR_LG constant text := 'aaaaaaaa-1000-0000-0000-000000000002';
        AR_B  constant text := 'bbbbbbbb-1000-0000-0000-000000000001';
        PERS_A constant text := 'aaaaaaaa-4000-0000-0000-000000000001';
        PERS_B constant text := 'bbbbbbbb-4000-0000-0000-000000000001';
        n int;
        sh text := 'select count(*)::text from (select public.fn_share_journal_entry(%L::uuid, %L::uuid, ''Prueba'')) x';
        cl text := 'select count(*)::text from (select public.fn_create_clarification_note(%L::uuid, ''Aclaración'')) x';
        wj text := 'select count(*)::text from (select public.fn_create_journal_entry(%L::uuid, ''note'', ''x'', now(), false, %L::uuid)) x';
        st text := 'select count(*)::text from (select public.fn_change_case_status(%L::uuid, %L, %L, ''Prueba'')) x';
    begin
        create or replace function pg_temp.id(p_kind text, p_n int) returns text language sql as
            $f$ select format('aaaaaaaa-%s-0000-0000-%s', p_kind, lpad(to_hex(p_n), 12, '0')) $f$;

        -- Escenario: otra caseworker de trabajo social (no es autora) y una del área jurídica
        insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
            (CW2::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cw2@tst-a.invalid', now(), now()),
            (CW3::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cw3@tst-a.invalid', now(), now());
        insert into public.user_profile (id, organization_id, email, full_name, active) values
            (CW2::uuid, 'aaaaaaaa-0000-0000-0000-00000000000a', 'cw2@tst-a.invalid', 'Cw2 jurídico', true),
            (CW3::uuid, 'aaaaaaaa-0000-0000-0000-00000000000a', 'cw3@tst-a.invalid', 'Cw3 trabajo social', true);
        insert into public.user_role (user_id, role_name, area_id, granted_by, granted_at) values
            (CW2::uuid, 'caseworker', AR_LG::uuid, 'aaaaaaaa-3000-0000-0000-000000000001', now()),
            (CW3::uuid, 'caseworker', AR_TS::uuid, 'aaaaaaaa-3000-0000-0000-000000000001', now());

        -- Personas y expedientes propios de estas pruebas (cada prueba destructiva usa el suyo)
        insert into public.person (id, organization_id, given_name, paternal_family_name, birth_date) values
            (pg_temp.id('4000', 5)::uuid, 'aaaaaaaa-0000-0000-0000-00000000000a', 'Zeta', 'Anonimizable', '1985-03-04'),
            (pg_temp.id('4000', 6)::uuid, 'aaaaaaaa-0000-0000-0000-00000000000a', 'Eta', 'Rectificable', '1985-03-04'),
            (pg_temp.id('4000', 7)::uuid, 'aaaaaaaa-0000-0000-0000-00000000000a', 'Theta', 'Opositora', '1985-03-04'),
            (pg_temp.id('4000', 2)::uuid, 'aaaaaaaa-0000-0000-0000-00000000000a', 'Iota', 'Estatus', '1985-03-04');
        insert into public."case" (id, organization_id, case_number, titular_person_id, opened_by, assigned_user_id, intake_window_type)
        select pg_temp.id('5000', k)::uuid, 'aaaaaaaa-0000-0000-0000-00000000000a', 'TST-A-000' || k,
               pg_temp.id('4000', 2)::uuid, 'aaaaaaaa-3000-0000-0000-000000000003', 'aaaaaaaa-3000-0000-0000-000000000002', 'fija'
        from generate_series(2, 4) k;

        -- Bitácora: 3, 15, 16, 17 y 19 son notas de trabajo protegidas; el resto, entradas ordinarias del área TS
        for n in 3..19 loop
            insert into public.journal_entry (id, organization_id, case_id, area_id, author_user_id, entry_type_key, body, is_work_note, visibility)
            values (pg_temp.id('6000', n)::uuid, 'aaaaaaaa-0000-0000-0000-00000000000a', 'aaaaaaaa-5000-0000-0000-000000000001', AR_TS::uuid,
                    'aaaaaaaa-3000-0000-0000-000000000002', 'note', 'Texto reservado ' || n, n in (3, 15, 16, 17, 19), 'area_private');
        end loop;

        -- ----- C-1: las funciones de ARCO y el acuse no cruzan organizaciones
        perform pg_temp.expect('C-1: director de B no anonimiza a una persona de A', DIRB, 'authenticated',
            format('select count(*)::text from (select public.fn_anonymize_person(%L::uuid, ''x'')) x', pg_temp.id('4000', 5)), 'ERR');
        perform pg_temp.expect('C-1: director de B no emite el extracto ARCO de una persona de A', DIRB, 'authenticated',
            format('select public.fn_generate_arco_access_extract(%L::uuid)::text', PERS_A), 'ERR');
        perform pg_temp.expect('C-1: director de B no rectifica a una persona de A', DIRB, 'authenticated',
            format('select count(*)::text from (select public.fn_rectify_person(%L::uuid,''X'',''Y'',null,null,date ''1990-01-01'',false,null,null,null,null,''x'')) x', pg_temp.id('4000', 6)), 'ERR');
        perform pg_temp.expect('C-1: director de B no registra oposición de una persona de A', DIRB, 'authenticated',
            format('select count(*)::text from (select public.fn_apply_opposition(%L::uuid, ''x'')) x', pg_temp.id('4000', 7)), 'ERR');
        perform pg_temp.expect('C-1: director de B no acusa recibo de una compartición de A', DIRB, 'authenticated',
            'select count(*)::text from (select public.fn_acknowledge_sharing(''aaaaaaaa-7000-0000-0000-000000000001''::uuid)) x', 'ERR');
        perform pg_temp.expect('C-1 control positivo: director de B registra oposición en su propia organización', DIRB, 'authenticated',
            format('select count(*)::text from (select public.fn_apply_opposition(%L::uuid, ''x'')) x', PERS_B), '1');
        perform pg_temp.expect('C-1 control positivo: director de A rectifica a su persona', DIR, 'authenticated',
            format('select count(*)::text from (select public.fn_rectify_person(%L::uuid,''Ana'',''PruebaA'',null,null,date ''1990-05-17'',false,null,null,null,null,''Corrección de prueba'')) x', PERS_A), '1');
        perform pg_temp.expect('C-1 control positivo: director de A rectifica a otra persona suya', DIR, 'authenticated',
            format('select count(*)::text from (select public.fn_rectify_person(%L::uuid,''Eta'',''Rectificable'',null,null,date ''1985-03-04'',false,null,null,null,null,''x'')) x', pg_temp.id('4000', 6)), '1');

        -- ----- C-2: el log guarda nombres de campos, nunca valores personales (decisión del PO, 11 oct 2026)
        perform pg_temp.expect('C-2: el evento de rectificación no guarda nombres ni fechas', DIR, 'authenticated',
            format($q$select count(*)::text from public.audit_event where action = 'RECTIFICATION' and record_id = %L::uuid
                      and created_at >= transaction_timestamp()
                      and (new_values ? 'given_name' or new_values ? 'paternal_family_name' or new_values ? 'birth_date' or old_values is not null)$q$, PERS_A), '0');
        perform pg_temp.expect('C-2 control positivo: el evento de rectificación dice qué campos cambiaron y el motivo', DIR, 'authenticated',
            format($q$select count(*)::text from public.audit_event where action = 'RECTIFICATION' and record_id = %L::uuid
                      and created_at >= transaction_timestamp()
                      and new_values->'changed_fields' ? 'birth_date' and new_values ? 'reason'$q$, PERS_A), '1');
        perform pg_temp.expect('C-2: persona, consentimiento, solicitud ARCO, perfil y requerimiento solo auditan nombres de campos', DIR, 'authenticated',
            $q$select count(*)::text from public.audit_event
               where table_name in ('person', 'consent', 'arco_request', 'user_profile', 'authority_request')
                 and action in ('INSERT', 'UPDATE') and created_at >= transaction_timestamp()
                 and (old_values is not null or new_values is null or (new_values - 'changed_fields') <> '{}'::jsonb)$q$, '0');
        perform pg_temp.expect('C-2 control positivo: el UPDATE de una persona sí deja qué campo cambió', DIR, 'authenticated',
            format($q$select count(*)::text from public.audit_event where table_name = 'person' and record_id = %L::uuid and action = 'UPDATE'
                      and created_at >= transaction_timestamp() and new_values->'changed_fields' ? 'birth_date'$q$, PERS_A), '>0');
        perform pg_temp.expect('C-2: el extracto ARCO no deja el nombre de la persona en el log', DIR, 'authenticated',
            format($q$select count(*)::text from public.audit_event where action = 'ARCO_ACCESS_EXTRACT_ISSUED' and record_id = %L::uuid
                      and created_at >= transaction_timestamp() and new_values ? 'issued_to'$q$, PERS_A), '0');

        -- ----- A-2: compartir una entrada = autoría, personas del área y dirección
        perform pg_temp.expect('A-2: quien es de otra área no comparte una entrada ajena', CW2, 'authenticated',
            format(sh, pg_temp.id('6000', 4), AR_LG), 'ERR');
        perform pg_temp.expect('A-2: ingreso (sin área) no comparte una entrada ajena', INT, 'authenticated',
            format(sh, pg_temp.id('6000', 5), AR_LG), 'ERR');
        perform pg_temp.expect('A-2 control positivo: quien es del área de la entrada la comparte', CW3, 'authenticated',
            format(sh, pg_temp.id('6000', 6), AR_LG), '1');
        perform pg_temp.expect('A-2 control positivo: la persona autora la comparte', CW, 'authenticated',
            format(sh, pg_temp.id('6000', 7), AR_LG), '1');
        perform pg_temp.expect('A-2 control positivo: dirección la comparte', DIR, 'authenticated',
            format(sh, pg_temp.id('6000', 8), AR_LG), '1');
        perform pg_temp.expect('A-2: no se comparte hacia un área de otra organización', CW, 'authenticated',
            format(sh, pg_temp.id('6000', 9), AR_B), 'ERR');
        perform pg_temp.expect('A-2: una nota de trabajo protegida no se comparte (ni su autora)', CW, 'authenticated',
            format(sh, pg_temp.id('6000', 15), AR_LG), 'ERR');
        perform pg_temp.expect('A-2: una nota de trabajo protegida no se comparte (ni dirección)', DIR, 'authenticated',
            format(sh, pg_temp.id('6000', 16), AR_LG), 'ERR');
        -- La nota de trabajo la ven solo autoría, área y dirección
        perform pg_temp.expect('A-2 control positivo: la autora lee su nota de trabajo', CW, 'authenticated',
            format('select count(*)::text from public.journal_entry where id = %L::uuid', pg_temp.id('6000', 3)), '1');
        perform pg_temp.expect('A-2: quien es del área lee la nota de trabajo', CW3, 'authenticated',
            format('select count(*)::text from public.journal_entry where id = %L::uuid', pg_temp.id('6000', 3)), '1');
        perform pg_temp.expect('A-2: dirección lee la nota de trabajo', DIR, 'authenticated',
            format('select count(*)::text from public.journal_entry where id = %L::uuid', pg_temp.id('6000', 3)), '1');
        perform pg_temp.expect('A-2: quien es de otra área no lee la nota de trabajo', CW2, 'authenticated',
            format('select count(*)::text from public.journal_entry where id = %L::uuid', pg_temp.id('6000', 3)), '0');
        perform pg_temp.expect('A-2: ingreso (sin área) no lee la nota de trabajo', INT, 'authenticated',
            format('select count(*)::text from public.journal_entry where id = %L::uuid', pg_temp.id('6000', 3)), '0');

        -- ----- A-2: aclarar una entrada = los mismos tres
        perform pg_temp.expect('A-2: quien es de otra área no aclara una entrada ajena', CW2, 'authenticated',
            format(cl, pg_temp.id('6000', 10)), 'ERR');
        perform pg_temp.expect('A-2: ingreso (sin área) no aclara una entrada ajena', INT, 'authenticated',
            format(cl, pg_temp.id('6000', 11)), 'ERR');
        perform pg_temp.expect('A-2 control positivo: quien es del área aclara', CW3, 'authenticated',
            format(cl, pg_temp.id('6000', 12)), '1');
        perform pg_temp.expect('A-2 control positivo: dirección aclara', DIR, 'authenticated',
            format(cl, pg_temp.id('6000', 13)), '1');
        perform pg_temp.expect('A-2 control positivo: la persona autora aclara', CW, 'authenticated',
            format(cl, pg_temp.id('6000', 14)), '1');
        perform pg_temp.expect('A-2 control positivo: la autora aclara su nota de trabajo', CW, 'authenticated',
            format(cl, pg_temp.id('6000', 17)), '1');
        perform pg_temp.expect('A-2: la aclaración de una nota de trabajo sigue siendo nota de trabajo y privada', CW, 'authenticated',
            format($q$select (je.is_work_note and je.visibility = 'area_private')::text
                      from public.journal_entry o join public.journal_entry je on je.id = o.superseded_by_id where o.id = %L::uuid$q$, pg_temp.id('6000', 17)), 'true');
        perform pg_temp.expect('A-2: una aclaración vacía se rechaza', CW, 'authenticated',
            format('select count(*)::text from (select public.fn_create_clarification_note(%L::uuid, ''   '')) x', pg_temp.id('6000', 18)), 'ERR');

        -- ----- A-2: escribir en el nombre de un área exige ser de esa área (o dirección)
        perform pg_temp.expect('A-2: quien es de otra área no escribe a nombre del área de trabajo social', CW2, 'authenticated',
            format(wj, 'aaaaaaaa-5000-0000-0000-000000000001', AR_TS), 'ERR');
        perform pg_temp.expect('A-2: la caseworker de trabajo social no escribe a nombre del área jurídica', CW, 'authenticated',
            format(wj, 'aaaaaaaa-5000-0000-0000-000000000001', AR_LG), 'ERR');
        perform pg_temp.expect('A-2: nadie escribe a nombre de un área de otra organización', CW, 'authenticated',
            format(wj, 'aaaaaaaa-5000-0000-0000-000000000001', AR_B), 'ERR');
        perform pg_temp.expect('A-2: ingreso (sin área) no escribe a nombre de un área operativa', INT, 'authenticated',
            format(wj, 'aaaaaaaa-5000-0000-0000-000000000001', AR_TS), 'ERR');
        perform pg_temp.expect('A-2 control positivo: la caseworker escribe a nombre de su propia área', CW, 'authenticated',
            format(wj, 'aaaaaaaa-5000-0000-0000-000000000001', AR_TS), '1');
        perform pg_temp.expect('A-2 control positivo: dirección escribe a nombre de cualquier área de su organización', DIR, 'authenticated',
            format(wj, 'aaaaaaaa-5000-0000-0000-000000000001', AR_LG), '1');
        perform pg_temp.expect('A-2 control positivo: sin área indicada se usa el área de quien escribe', CW, 'authenticated',
            'select count(*)::text from (select public.fn_create_journal_entry(''aaaaaaaa-5000-0000-0000-000000000001''::uuid, ''note'', ''x'')) x', '1');

        -- ----- A-2: la base impide que una nota de trabajo cambie de naturaleza o de visibilidad
        perform pg_temp.expect('A-2: una nota de trabajo no pasa a compartida ni por el propietario', null, null,
            format('with u as (update public.journal_entry set visibility = ''shared'' where id = %L::uuid returning 1) select count(*)::text from u', pg_temp.id('6000', 19)), 'ERR');
        perform pg_temp.expect('A-2: una nota de trabajo no deja de serlo', null, null,
            format('with u as (update public.journal_entry set is_work_note = false where id = %L::uuid returning 1) select count(*)::text from u', pg_temp.id('6000', 19)), 'ERR');

        -- ----- A-3: anonymized solo por fn_anonymize_person; reabrir, solo dirección
        perform pg_temp.expect('A-3 control positivo: un caseworker cambia la etapa', CW, 'authenticated',
            format(st, pg_temp.id('5000', 2), 'case_stage', 'assessment'), '1');
        perform pg_temp.expect('A-3: un caseworker no deja «anonimizada» la situación de un expediente', CW, 'authenticated',
            format(st, pg_temp.id('5000', 2), 'engagement_status', 'anonymized'), 'ERR');
        perform pg_temp.expect('A-3: ni dirección deja «anonimizada» la situación sin anonimizar a la persona', DIR, 'authenticated',
            format(st, pg_temp.id('5000', 3), 'engagement_status', 'anonymized'), 'ERR');
        perform pg_temp.expect('A-3: ni dirección deja «anonimizado» el estado del expediente sin anonimizar a la persona', DIR, 'authenticated',
            format(st, pg_temp.id('5000', 3), 'record_status', 'anonymized'), 'ERR');
        perform pg_temp.expect('A-3 control positivo: dirección cierra el expediente', DIR, 'authenticated',
            format(st, pg_temp.id('5000', 4), 'record_status', 'closed'), '1');
        perform pg_temp.expect('A-3: un caseworker no reabre un expediente cerrado', CW, 'authenticated',
            format(st, pg_temp.id('5000', 4), 'record_status', 'open'), 'ERR');
        perform pg_temp.expect('A-3: ingreso no reabre un expediente cerrado', INT, 'authenticated',
            format(st, pg_temp.id('5000', 4), 'record_status', 'open'), 'ERR');
        perform pg_temp.expect('A-3 control positivo: dirección reabre un expediente cerrado', DIR, 'authenticated',
            format(st, pg_temp.id('5000', 4), 'record_status', 'open'), '1');

        -- ----- M-1: toda función security definer fija su search_path
        perform pg_temp.expect('M-1: ninguna función security definer de public queda sin search_path fijo', null, null,
            $q$select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.prosecdef
                 and not exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) c where c like 'search_path=%')$q$, '0');
    end;

    -- ============================================================================================
    -- ===== A-1: el núcleo se escribe SOLO por funciones (migración 20261011000002)
    -- ===== L-1: terceros pseudonimizados al anonimizar (migración 20261011000003)
    -- ============================================================================================
    declare
        CW3   constant text := 'aaaaaaaa-3000-0000-0000-00000000000b';
        AR_TS constant text := 'aaaaaaaa-1000-0000-0000-000000000001';
        ORG_A_ constant text := 'aaaaaaaa-0000-0000-0000-00000000000a';
        ORG_B_ constant text := 'bbbbbbbb-0000-0000-0000-00000000000b';
        CASE_A constant text := 'aaaaaaaa-5000-0000-0000-000000000001';
        PERS_A constant text := 'aaaaaaaa-4000-0000-0000-000000000001';
        t2 text;
        who text;
    begin
        -- Datos de terceros que la anonimización debe pseudonimizar (L-1): se siembran como propietario
        update public.consent
           set legal_guardian_name = 'Tutora Secreta', authority_letter_ref = 'OFICIO-SECRETO-123', notes = 'nota privada del caso'
         where id = 'aaaaaaaa-8000-0000-0000-000000000001';
        insert into public.arco_request (organization_id, person_id, case_id, request_type, status, details, reason, requested_by_name, is_legal_representative, received_at)
        values (ORG_A_::uuid, PERS_A::uuid, CASE_A::uuid, 'access', 'pending', 'Detalle secreto', 'Motivo secreto', 'Solicitante Secreto', false, now());

        -- Ningún rol de aplicación conserva INSERT/UPDATE sobre las tablas de datos del núcleo
        perform pg_temp.expect('A-1: sin INSERT/UPDATE directos para anon/authenticated en el núcleo', null, null,
            $q$select count(*)::text from information_schema.role_table_grants
               where table_schema = 'public' and privilege_type in ('INSERT', 'UPDATE') and grantee in ('anon', 'authenticated')
                 and table_name in ('person', 'case', 'case_status', 'case_vulnerability_marker', 'journal_entry',
                                    'sharing_event', 'attachment', 'consent', 'arco_request')$q$, '0');

        -- Intentos concretos, con la identidad real de cada rol
        perform pg_temp.expect('A-1: no se firma una entrada de bitácora con la autoría de otra persona', CW, 'authenticated',
            format($q$with i as (insert into public.journal_entry (organization_id, case_id, area_id, author_user_id, entry_type_key, body)
                      values (%L, %L, %L, %L, 'note', 'suplantada') returning 1) select count(*)::text from i$q$, ORG_A_, CASE_A, AR_TS, DIR), 'ERR');
        perform pg_temp.expect('A-1: no se inserta una entrada ya «compartida» sin sharing_event', CW, 'authenticated',
            format($q$with i as (insert into public.journal_entry (organization_id, case_id, area_id, author_user_id, entry_type_key, body, visibility)
                      values (%L, %L, %L, %L, 'note', 'sin motivo', 'shared') returning 1) select count(*)::text from i$q$, ORG_A_, CASE_A, AR_TS, CW), 'ERR');
        perform pg_temp.expect('A-1: no se escribe bitácora con la organización de otra', CW, 'authenticated',
            format($q$with i as (insert into public.journal_entry (organization_id, case_id, area_id, author_user_id, entry_type_key, body)
                      values (%L, %L, %L, %L, 'note', 'cruzada') returning 1) select count(*)::text from i$q$,
                   ORG_B_, 'bbbbbbbb-5000-0000-0000-000000000001', 'bbbbbbbb-1000-0000-0000-000000000001', CW), 'ERR');
        foreach who in array array[CW, INT, DIR] loop
            perform pg_temp.expect('A-1: no se actualiza a una persona por escritura directa (' || right(who, 2) || ')', who, 'authenticated',
                format($q$with u as (update public.person set phone_number = '5500000000' where id = %L returning 1) select count(*)::text from u$q$, PERS_A), 'ERR');
            perform pg_temp.expect('A-1: no se revierte la anonimización por escritura directa (' || right(who, 2) || ')', who, 'authenticated',
                format($q$with u as (update public.person set is_anonymized = false where id = %L returning 1) select count(*)::text from u$q$, PERS_A), 'ERR');
        end loop;
        perform pg_temp.expect('A-1: ingreso no inserta una persona directamente (se saltaría el consentimiento)', INT, 'authenticated',
            format($q$with i as (insert into public.person (organization_id, given_name, paternal_family_name, birth_date) values (%L, 'Directa', 'Sin consentimiento', '1990-01-01') returning 1) select count(*)::text from i$q$, ORG_A_), 'ERR');
        perform pg_temp.expect('A-1: dirección no inserta una persona directamente', DIR, 'authenticated',
            format($q$with i as (insert into public.person (organization_id, given_name, paternal_family_name, birth_date) values (%L, 'Directa', 'Dirección', '1990-01-01') returning 1) select count(*)::text from i$q$, ORG_A_), 'ERR');
        perform pg_temp.expect('A-1: ingreso no abre un caso directamente', INT, 'authenticated',
            format($q$with i as (insert into public."case" (organization_id, case_number, titular_person_id, opened_by) values (%L, 'DIRECTO-1', %L, %L) returning 1) select count(*)::text from i$q$, ORG_A_, PERS_A, INT), 'ERR');
        perform pg_temp.expect('A-1: ingreso no afirma marcadores de vulnerabilidad directamente (P-06)', INT, 'authenticated',
            format($q$with i as (insert into public.case_vulnerability_marker (organization_id, case_id, marker_code, affirmed_by) values (%L, %L, 'victim_of_violence', %L) returning 1) select count(*)::text from i$q$, ORG_A_, CASE_A, INT), 'ERR');
        perform pg_temp.expect('A-1: no se fabrica historial de estatus por inserción directa', CW, 'authenticated',
            format($q$with i as (insert into public.case_status (organization_id, case_id, axis_id, value_id, valid_from, valid_to, reason)
                      values (%L, %L, 'aaaaaaaa-2000-0000-0000-000000000005', 'aaaaaaaa-2100-0000-0000-000000000002', now() - interval '3 days', now() - interval '1 day', 'falso') returning 1) select count(*)::text from i$q$, ORG_A_, CASE_A), 'ERR');
        perform pg_temp.expect('A-1: no se cierra un estatus por UPDATE directo', CW, 'authenticated',
            format($q$with u as (update public.case_status set valid_to = now() where case_id = %L and valid_to is null returning 1) select count(*)::text from u$q$, CASE_A), 'ERR');
        perform pg_temp.expect('A-1: no se registra un consentimiento por inserción directa', INT, 'authenticated',
            format($q$with i as (insert into public.consent (organization_id, person_id, consent_type, status, granted_by_user_id) values (%L, %L, 'sensitive_data', 'granted', %L) returning 1) select count(*)::text from i$q$, ORG_A_, PERS_A, INT), 'ERR');
        perform pg_temp.expect('A-1: no se edita un consentimiento ya otorgado', DIR, 'authenticated',
            $q$with u as (update public.consent set status = 'revoked' where id = 'aaaaaaaa-8000-0000-0000-000000000001' returning 1) select count(*)::text from u$q$, 'ERR');
        perform pg_temp.expect('A-1: no se crea una solicitud ARCO por inserción directa', DIR, 'authenticated',
            format($q$with i as (insert into public.arco_request (organization_id, person_id, request_type, status, details, reason, requested_by_name, received_at)
                      values (%L, %L, 'access', 'pending', 'x', 'x', 'x', now()) returning 1) select count(*)::text from i$q$, ORG_A_, PERS_A), 'ERR');
        perform pg_temp.expect('A-1: no se modifica una solicitud ARCO por UPDATE directo', DIR, 'authenticated',
            format($q$with u as (update public.arco_request set status = 'rejected' where person_id = %L returning 1) select count(*)::text from u$q$, PERS_A), 'ERR');
        perform pg_temp.expect('A-1: no se altera la compartición por escritura directa', CW3, 'authenticated',
            $q$with u as (update public.sharing_event set reason = 'otra' where id = 'aaaaaaaa-7000-0000-0000-000000000001' returning 1) select count(*)::text from u$q$, 'ERR');

        -- Controles positivos: las funciones, que son el único camino, siguen funcionando
        perform pg_temp.expect('A-1 control positivo: ingreso abre un expediente por la función', INT, 'authenticated', new_case, '1');
        perform pg_temp.expect('A-1 control positivo: dirección abre un expediente por la función', DIR, 'authenticated', new_case, '1');
        perform pg_temp.expect('A-1: quien no es de ingreso ni dirección no abre expedientes por la función', CW, 'authenticated', new_case, 'ERR');
        -- Motivo inicial de los estatus: una clave de traducción, no un texto en un idioma (la interfaz lo traduce)
        perform pg_temp.expect('el estatus inicial de un expediente nuevo guarda la clave de traducción como motivo', null, null,
            $q$select count(*)::text from public.case_status where valid_from >= transaction_timestamp() and reason = 'i18n:status.reason_initial'$q$, '>0');
        perform pg_temp.expect('ningún estatus inicial nuevo guarda el texto técnico antiguo como motivo', null, null,
            $q$select count(*)::text from public.case_status where valid_from >= transaction_timestamp() and reason like 'Apertura de expediente%'$q$, '0');
        perform pg_temp.expect('A-1: el área asignada debe ser de la propia organización', INT, 'authenticated',
            replace(new_case, 'aaaaaaaa-1000-0000-0000-000000000001', 'bbbbbbbb-1000-0000-0000-000000000001'), 'ERR');
        perform pg_temp.expect('A-1: la función interna del alta no es ejecutable por los roles de aplicación', INT, 'authenticated',
            $q$select count(*)::text from (select public.fn_create_case_with_person_impl('X','Y',null,null,date '2000-01-01',false,null,null,null,null,null,null,'fija',false,null,null,null,null,null,
               'aaaaaaaa-1000-0000-0000-000000000001'::uuid, array[]::text[], '[{"consent_type":"general_care","status":"granted"}]'::jsonb)) x$q$, 'ERR');
    end;

    -- ============================================================================================
    -- ===== M-2 / R-19: indicadores sin re-identificación por resta (migración 20261011000004)
    -- ===== Escenario: 13 casos nuevos. intake_window_type: movil 7 · transaccional 6.
    -- ===== sexo: sin dato → (existentes + 4) · 2 → 6 · 3 → 3 (una sola celda menor a 5)
    -- ============================================================================================
    declare
        mk text := $q$select coalesce(r->>%L, 'NULL') from jsonb_array_elements(public.fn_aggregate_metrics()->'rows') r
                       where r->>'metric' = %L and r->>'bucket' = %L$q$;
        i int;
    begin
        for i in 1..13 loop
            insert into public.person (id, organization_id, given_name, paternal_family_name, birth_date, sex_id)
            values (pg_temp.id('4100', i)::uuid, 'aaaaaaaa-0000-0000-0000-00000000000a', 'Indicador' || i, 'Prueba', '1990-06-15',
                    case when i <= 4 then null when i <= 7 then 3 else 2 end);
            insert into public."case" (id, organization_id, case_number, titular_person_id, opened_by, assigned_user_id, intake_window_type)
            values (pg_temp.id('5100', i)::uuid, 'aaaaaaaa-0000-0000-0000-00000000000a', 'TST-A-M' || i, pg_temp.id('4100', i)::uuid,
                    'aaaaaaaa-3000-0000-0000-000000000003', 'aaaaaaaa-3000-0000-0000-000000000002',
                    case when i <= 7 then 'movil' else 'transaccional' end);
        end loop;

        -- Opción 1: las cifras se redondean a múltiplos de 5 para quien no es de Dirección
        perform pg_temp.expect('M-2: el observador ve la cifra redondeada a múltiplos de 5 (7 → 5)', VW, 'authenticated',
            format(mk, 'count', 'intake_window_type', 'movil'), '5');
        perform pg_temp.expect('M-2 control positivo: Dirección ve la cifra exacta (7)', DIR, 'authenticated',
            format(mk, 'count', 'intake_window_type', 'movil'), '7');
        -- Decisión del PO (11 oct 2026, opción B): quien trabaja en la organización ve lo exacto (ya accede
        -- a los expedientes); solo el observador externo ve cifras redondeadas. Confiabilidad donde se decide.
        perform pg_temp.expect('M-2 (B): el caseworker ve la cifra exacta (7)', CW, 'authenticated',
            format(mk, 'count', 'intake_window_type', 'movil'), '7');
        perform pg_temp.expect('M-2 (B): ingreso ve la cifra exacta (7)', INT, 'authenticated',
            format(mk, 'count', 'intake_window_type', 'movil'), '7');
        perform pg_temp.expect('M-2 (B): el resultado dice que es exacto (caseworker)', CW, 'authenticated',
            $q$select public.fn_aggregate_metrics()->>'exact'$q$, 'true');
        perform pg_temp.expect('M-2 (B): el resultado dice que es exacto (ingreso)', INT, 'authenticated',
            $q$select public.fn_aggregate_metrics()->>'exact'$q$, 'true');
        perform pg_temp.expect('M-2: ninguna cifra visible del observador deja de ser múltiplo de 5', VW, 'authenticated',
            $q$select count(*)::text from jsonb_array_elements(public.fn_aggregate_metrics()->'rows') r
               where r->>'count' is not null and (r->>'count')::int % 5 <> 0$q$, '0');
        perform pg_temp.expect('M-2: el redondeo nunca deja una cifra visible por debajo del umbral', VW, 'authenticated',
            $q$select (coalesce(min((r->>'count')::int), 5) >= 5)::text from jsonb_array_elements(public.fn_aggregate_metrics()->'rows') r$q$, 'true');
        perform pg_temp.expect('M-2: el resultado dice que está redondeado (observador)', VW, 'authenticated',
            $q$select public.fn_aggregate_metrics()->>'exact'$q$, 'false');
        perform pg_temp.expect('M-2 control positivo: el resultado dice que es exacto (Dirección)', DIR, 'authenticated',
            $q$select public.fn_aggregate_metrics()->>'exact'$q$, 'true');

        -- Opción 3: si en una partición se oculta una sola celda, se oculta también la visible más pequeña
        perform pg_temp.expect('M-2: la celda menor a 5 sigue oculta por su tamaño', VW, 'authenticated',
            format(mk, 'hidden_reason', 'sex', '3'), 'small');
        perform pg_temp.expect('M-2: la celda visible más pequeña se oculta por complemento (no se deduce por resta)', VW, 'authenticated',
            format(mk, 'hidden_reason', 'sex', '2'), 'complement');
        perform pg_temp.expect('M-2: la celda protegida por complemento no trae cifra', VW, 'authenticated',
            format(mk, 'count', 'sex', '2'), 'NULL');
        perform pg_temp.expect('M-2: la protección por complemento también rige para Dirección', DIR, 'authenticated',
            format(mk, 'hidden_reason', 'sex', '2'), 'complement');
        perform pg_temp.expect('M-2 control positivo: la celda mayor sigue visible', VW, 'authenticated',
            format(mk, 'suppressed', 'sex', 'sin_dato'), 'false');
        perform pg_temp.expect('M-2 control positivo: una partición sin celdas pequeñas no oculta nada', VW, 'authenticated',
            format(mk, 'suppressed', 'intake_window_type', 'movil'), 'false');
        perform pg_temp.expect('M-2: restar las celdas visibles del total ya no revela la celda oculta', DIR, 'authenticated',
            $q$select count(*)::text from jsonb_array_elements(public.fn_aggregate_metrics()->'rows') r
               where r->>'metric' = 'sex' and r->>'count' is not null$q$, '1');
    end;

    -- ============================================================================================
    -- ===== Aclarar una entrada ya compartida: la aclaración le llega a quien recibió la original
    -- ===== (migración 20261011000005)
    -- ============================================================================================
    declare
        CW2 constant text := 'aaaaaaaa-3000-0000-0000-00000000000a';  -- caseworker del área jurídica (destino)
        AR_LG constant text := 'aaaaaaaa-1000-0000-0000-000000000002';
        nuevo text := $q$select count(*)::text from public.journal_entry n
                         where n.id = (select o.superseded_by_id from public.journal_entry o where o.id = %L::uuid)$q$;
    begin
        insert into public.journal_entry (id, organization_id, case_id, area_id, author_user_id, entry_type_key, body, is_work_note, visibility)
        values (pg_temp.id('6000', 20)::uuid, 'aaaaaaaa-0000-0000-0000-00000000000a', 'aaaaaaaa-5000-0000-0000-000000000001',
                'aaaaaaaa-1000-0000-0000-000000000001', 'aaaaaaaa-3000-0000-0000-000000000002', 'note', 'Entrada que se compartirá y luego se aclara', false, 'area_private'),
               (pg_temp.id('6000', 21)::uuid, 'aaaaaaaa-0000-0000-0000-00000000000a', 'aaaaaaaa-5000-0000-0000-000000000001',
                'aaaaaaaa-1000-0000-0000-000000000001', 'aaaaaaaa-3000-0000-0000-000000000002', 'note', 'Entrada privada que se aclara', false, 'area_private');

        perform pg_temp.expect('aclaración compartida: la autora comparte la original con el área jurídica', CW, 'authenticated',
            format('select count(*)::text from (select public.fn_share_journal_entry(%L::uuid, %L::uuid, ''Prueba'')) x', pg_temp.id('6000', 20), AR_LG), '1');
        perform pg_temp.expect('aclaración compartida control positivo: el área jurídica lee la original compartida', CW2, 'authenticated',
            format('select count(*)::text from public.journal_entry where id = %L::uuid', pg_temp.id('6000', 20)), '1');
        perform pg_temp.expect('aclaración compartida: la autora aclara la original', CW, 'authenticated',
            format('select count(*)::text from (select public.fn_create_clarification_note(%L::uuid, ''Aclaración de la entrada compartida'')) x', pg_temp.id('6000', 20)), '1');
        perform pg_temp.expect('aclaración compartida: el área jurídica lee la aclaración de lo que recibió', CW2, 'authenticated',
            format(nuevo, pg_temp.id('6000', 20)), '1');
        perform pg_temp.expect('aclaración compartida: dirección sigue leyéndola', DIR, 'authenticated',
            format(nuevo, pg_temp.id('6000', 20)), '1');
        perform pg_temp.expect('aclaración compartida: quien no es de esa área ni autor no la lee', INT, 'authenticated',
            format(nuevo, pg_temp.id('6000', 20)), '0');
        perform pg_temp.expect('aclaración compartida: no se inventan acuses (hereda el estado de la original)', null, null,
            format($q$select count(*)::text from public.sharing_event s
                      where s.journal_entry_id = (select superseded_by_id from public.journal_entry where id = %L::uuid)
                        and s.acknowledged_by_user_id is not null$q$, pg_temp.id('6000', 20)), '0');
        perform pg_temp.expect('aclaración privada: una entrada que nunca se compartió sigue privada (la otra área no la lee)', CW, 'authenticated',
            format('select count(*)::text from (select public.fn_create_clarification_note(%L::uuid, ''Aclaración privada'')) x', pg_temp.id('6000', 21)), '1');
        perform pg_temp.expect('aclaración privada control: el área jurídica no lee la aclaración privada', CW2, 'authenticated',
            format($q$select count(*)::text from public.journal_entry n where n.id = (select o.superseded_by_id from public.journal_entry o where o.id = %L::uuid)$q$, pg_temp.id('6000', 21)), '0');
        perform pg_temp.expect('aclaración privada control: dirección sí la lee', DIR, 'authenticated',
            format($q$select count(*)::text from public.journal_entry n where n.id = (select o.superseded_by_id from public.journal_entry o where o.id = %L::uuid)$q$, pg_temp.id('6000', 21)), '1');
    end;

    -- ===== Anónimo: nada
    perform pg_temp.expect('anon no lee personas', null, 'anon', 'select count(*)::text from public.person', 'ERR|0');
    perform pg_temp.expect('anon no abre casos', null, 'anon', new_case, 'ERR');
    perform pg_temp.expect('anon no lee app_config', null, 'anon', 'select count(*)::text from public.app_config', 'ERR');
    perform pg_temp.expect('authenticated no lee app_config', DIR, 'authenticated', 'select count(*)::text from public.app_config', 'ERR');
    perform pg_temp.expect('control positivo: anon consulta el entorno por función', null, 'anon', 'select public.fn_app_environment()', 'demo|production');

    -- ===== TK006: la organización no se queda sin dirección (se prueba aquí porque cambia a B)
    perform pg_temp.expect('el último director no puede revocar su propio rol (disparador a nivel de tabla)', null, null,
        pg_temp.q('with u as (update public.user_role set revoked_at = now(), revoked_by = {DIRB} where user_id = {DIRB} and role_name = ''director'' returning 1) select count(*)::text from u'), 'ERR:TK006');
    perform pg_temp.expect('el último director no puede desactivar su cuenta (disparador a nivel de tabla)', null, null,
        pg_temp.q('with u as (update public.user_profile set active = false where id = {DIRB} returning 1) select count(*)::text from u'), 'ERR:TK006');
    perform pg_temp.expect('E16A: el último director tampoco se revoca ni se desactiva por las funciones → BV343', DIRB, 'authenticated',
        pg_temp.q($q$select count(*)::text from (select public.fn_set_user_active({DIRB}, false, 'x')) x$q$), 'ERR:BV343');
    perform pg_temp.expect('se agrega un segundo director a B', null, null,
        pg_temp.q($q$with a as (insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
                               values ({DIRB2}, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'dir2@tst-b.invalid', now(), now()) returning id),
                          p as (insert into public.user_profile (id, organization_id, email, full_name, active)
                                select id, {ORGB}, 'dir2@tst-b.invalid', 'Dir B2', true from a returning id),
                          r as (insert into public.user_role (user_id, role_name, granted_by, granted_at)
                                select id, 'director', {DIRB}, now() from p returning 1)
                     select count(*)::text from r$q$), '1');
    perform pg_temp.expect('control positivo: con otro director vigente, la dirección sí puede quitarle el rol a otro director', DIRB2, 'authenticated',
        pg_temp.q($q$select count(*)::text from (select public.fn_revoke_role((select id from public.user_role where user_id = {DIRB} and role_name = 'director' and revoked_at is null), 'Deja la dirección')) x$q$), '1');
    perform pg_temp.expect('el director que queda no puede dejar su propio rol por la función → BV343', DIRB2, 'authenticated',
        pg_temp.q($q$select count(*)::text from (select public.fn_revoke_role((select id from public.user_role where user_id = {DIRB2} and role_name = 'director' and revoked_at is null), 'x')) x$q$), 'ERR:BV343');
    perform pg_temp.expect('el director que queda no pierde su rol (disparador a nivel de tabla)', null, null,
        pg_temp.q('with u as (update public.user_role set revoked_at = now(), revoked_by = {DIRB2} where user_id = {DIRB2} and role_name = ''director'' returning 1) select count(*)::text from u'), 'ERR:TK006');

    -- ============================================================================================
    -- ===== BV-3.2: subfolio de niñez y adolescencia acompañadas (migración 20261012000001)
    declare
        sub text := $sf$select count(*)::text from (select public.fn_create_subfolio(
            'aaaaaaaa-5000-0000-0000-0000000000d1'::uuid, 'Niño','HijoA',null,null,(current_date - interval '8 years')::date,false,null,null,null,null,null,
            'madre','Viaja con su madre; se abre su expediente propio.', array[]::text[],
            '[{"consent_type":"general_care","status":"granted","is_minor_assent":true}]'::jsonb)) x$sf$;
    begin
        perform pg_temp.expect('BV-3.2: se prepara un caso padre abierto y principal', null, null,
            pg_temp.q($q$with c as (insert into public."case" (id, organization_id, case_number, titular_person_id, opened_by, assigned_user_id, intake_window_type)
                                    values ('aaaaaaaa-5000-0000-0000-0000000000d1', {ORGA}, 'TST-A-0099', 'aaaaaaaa-4000-0000-0000-000000000001', {INT}, {CW}, 'fija') returning 1)
                         select count(*)::text from c$q$), '1');
        perform pg_temp.expect('BV-3.2 control positivo: ingreso crea el subfolio', INT, 'authenticated', sub, '1');
        perform pg_temp.expect('BV-3.2: el primer subfolio toma el folio del caso padre con -S1', null, null,
            $q$select case_number from public."case" where parent_case_id = 'aaaaaaaa-5000-0000-0000-0000000000d1' order by created_at limit 1$q$, 'TST-A-0099-S1');
        perform pg_temp.expect('BV-3.2 control positivo: dirección también crea subfolios', DIR, 'authenticated', sub, '1');
        perform pg_temp.expect('BV-3.2: el segundo subfolio es -S2 (nunca repite el folio)', null, null,
            $q$select string_agg(case_number, ',' order by case_number) from public."case" where parent_case_id = 'aaaaaaaa-5000-0000-0000-0000000000d1'$q$, 'TST-A-0099-S1,TST-A-0099-S2');
        perform pg_temp.expect('BV-3.2: trabajo social no crea subfolios', CW, 'authenticated', sub, 'ERR:BV114');
        perform pg_temp.expect('BV-3.2: el observador no crea subfolios', VW, 'authenticated', sub, 'ERR:BV114');
        perform pg_temp.expect('BV-3.2: el voluntariado no crea subfolios', VOL, 'authenticated', sub, 'ERR:BV114');
        perform pg_temp.expect('BV-3.2: sin sesión no se crean subfolios', null, 'anon', sub, 'ERR');
        perform pg_temp.expect('BV-3.2: dirección de otra organización no cuelga subfolios de un caso ajeno', DIRB2, 'authenticated', sub, 'ERR:BV201');
        perform pg_temp.expect('BV-3.2: un subfolio no admite subfolios (profundidad 1)', INT, 'authenticated',
            replace(sub, 'aaaaaaaa-5000-0000-0000-0000000000d1', (select id::text from public."case" where case_number = 'TST-A-0099-S1' limit 1)), 'ERR:BV505');
        perform pg_temp.expect('BV-3.2: la persona del subfolio debe ser menor de 18 años', INT, 'authenticated',
            replace(sub, '(current_date - interval ''8 years'')::date', 'date ''2000-01-01'''), 'ERR:BV406');
        perform pg_temp.expect('BV-3.2: la nota de justificación es obligatoria', INT, 'authenticated',
            replace(sub, 'Viaja con su madre; se abre su expediente propio.', '   '), 'ERR:BV312');
        perform pg_temp.expect('BV-3.2: la nota de justificación no puede ser una palabra suelta', INT, 'authenticated',
            replace(sub, 'Viaja con su madre; se abre su expediente propio.', 'ok'), 'ERR:BV312');
        perform pg_temp.expect('BV-3.2: el parentesco de quien representa es obligatorio', INT, 'authenticated',
            replace(sub, '''madre''', ''''''), 'ERR:BV311');
        perform pg_temp.expect('BV-3.2: sin consentimiento general no se abre el subfolio', INT, 'authenticated',
            replace(sub, '"consent_type":"general_care","status":"granted"', '"consent_type":"general_care","status":"revoked"'), 'ERR:BV401');
        perform pg_temp.expect('BV-3.2 (P-06): sin consentimiento de datos sensibles no se afirman marcadores', INT, 'authenticated',
            replace(sub, 'array[]::text[]', 'array[''disability'']::text[]'), 'ERR:BV402');
        perform pg_temp.expect('BV-3.2: el subfolio es de niñez acompañada; el marcador de no acompañada se rechaza', INT, 'authenticated',
            replace(replace(sub, 'array[]::text[]', 'array[''unaccompanied_child'']::text[]'), '"is_minor_assent":true}]', '"is_minor_assent":true},{"consent_type":"sensitive_data","status":"granted","is_minor_assent":true}]'), 'ERR:BV407');
        perform pg_temp.expect('BV-3.2: el caso padre no cambia por crear subfolios', null, null,
            $q$select count(*)::text from public."case" where id = 'aaaaaaaa-5000-0000-0000-0000000000d1' and parent_case_id is null and closed_at is null$q$, '1');
        perform pg_temp.expect('BV-3.2: quien representa se toma del caso padre, no de lo que envía el cliente', null, null,
            $q$select count(*)::text from public.consent c join public."case" k on k.id = c.case_id
               where k.parent_case_id = 'aaaaaaaa-5000-0000-0000-0000000000d1' and c.legal_guardian_name = 'Ana PruebaA'
                 and c.legal_guardian_role = 'madre' and c.is_minor_assent$q$, '>0');
        perform pg_temp.expect('BV-3.2: aunque el cliente mande otro nombre de representante, se guarda el del caso padre', INT, 'authenticated',
            replace(sub, '"is_minor_assent":true}]', '"is_minor_assent":true,"legal_guardian_name":"Persona Ajena"}]'), '1');
        perform pg_temp.expect('BV-3.2: ningún consentimiento del subfolio quedó con un representante distinto al del caso padre', null, null,
            $q$select count(*)::text from public.consent c join public."case" k on k.id = c.case_id
               where k.parent_case_id = 'aaaaaaaa-5000-0000-0000-0000000000d1' and c.legal_guardian_name <> 'Ana PruebaA'$q$, '0');
        perform pg_temp.expect('BV-3.2: la nota de justificación queda en la bitácora del subfolio', null, null,
            $q$select count(*)::text from public.journal_entry j join public."case" k on k.id = j.case_id
               where k.parent_case_id = 'aaaaaaaa-5000-0000-0000-0000000000d1' and j.body like '%Viaja con su madre; se abre su expediente propio.%'
                 and j.visibility = 'area_private' and not j.is_work_note$q$, '>0');
        perform pg_temp.expect('BV-3.2: el alta del subfolio deja evento de auditoría', null, null,
            $q$select count(*)::text from public.audit_event a join public."case" k on k.id = a.record_id
               where a.table_name = 'case' and a.action = 'INSERT' and k.parent_case_id = 'aaaaaaaa-5000-0000-0000-0000000000d1'$q$, '>0');
        perform pg_temp.expect('BV-3.2: el subfolio nace abierto, en la organización del caso padre', null, null,
            $q$select count(*)::text from public."case" where parent_case_id = 'aaaaaaaa-5000-0000-0000-0000000000d1'
               and closed_at is null and organization_id = 'aaaaaaaa-0000-0000-0000-00000000000a'$q$, '>0');
        perform pg_temp.expect('BV-3.2 (D-14): con consentimiento sensible el subfolio guarda sexo, nacionalidad y lengua capturados', INT, 'authenticated',
            replace(replace(sub, 'false,null,null,null,null,null,', 'false,1,93,''Honduras'',null,null,'),
                    '"is_minor_assent":true}]', '"is_minor_assent":true},{"consent_type":"sensitive_data","status":"granted","is_minor_assent":true}]'), '1');
        perform pg_temp.expect('BV-3.2: la persona del subfolio conserva la nacionalidad y el idioma capturados', null, null,
            $q$select count(*)::text from public.person p join public."case" k on k.titular_person_id = p.id
               where k.parent_case_id = 'aaaaaaaa-5000-0000-0000-0000000000d1' and p.other_nationality = 'Honduras'$q$, '>0');
        perform pg_temp.expect('BV-3.2: se prepara un caso padre cerrado', null, null,
            pg_temp.q($q$with c as (insert into public."case" (id, organization_id, case_number, titular_person_id, closed_at, intake_window_type)
                                    values ('aaaaaaaa-5000-0000-0000-0000000000c1', {ORGA}, 'TST-A-CERRADO', 'aaaaaaaa-4000-0000-0000-000000000001', now(), 'fija') returning 1)
                         select count(*)::text from c$q$), '1');
        perform pg_temp.expect('BV-3.2: a un caso padre cerrado no se le cuelgan subfolios', INT, 'authenticated',
            replace(sub, 'aaaaaaaa-5000-0000-0000-0000000000d1', 'aaaaaaaa-5000-0000-0000-0000000000c1'), 'ERR:BV506');
    end;

    -- ============================================================================================
    -- ===== E13 fase 1: errores de dominio con código estable (migración 20261014000001)
    -- Candado BV-13.2: ninguna función vigente de public levanta un error de dominio sin código (BVnnn de la
    -- plataforma o TKnnn de tareas). Cuenta las sentencias `raise exception` sin `errcode`.
    perform pg_temp.expect('E13: ninguna función vigente levanta un error con mensaje sin código estable', null, null,
        $q$select count(*)::text from (
             select p.proname
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             cross join lateral regexp_matches(p.prosrc, 'raise\s+exception\s+(E?''(?:[^'']|'''')*'')([^;]*);', 'gi') m
             where n.nspname = 'public' and p.prokind = 'f' and m[2] !~* 'errcode\s*=\s*''(BV|TK)[0-9]{3}'''
           ) x$q$, '0');
    perform pg_temp.expect('E13: tampoco levanta un error armado solo con USING sin código estable', null, null,
        $q$select count(*)::text from (
             select p.proname
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             cross join lateral regexp_matches(p.prosrc, 'raise\s+exception\s+using([^;]*);', 'gi') m
             where n.nspname = 'public' and p.prokind = 'f' and m[1] !~* 'errcode\s*=\s*''(BV|TK)[0-9]{3}'''
           ) x$q$, '0');
    -- Códigos concretos: el mismo error llega con el mismo código, venga del rol, del dato o de la protección
    perform pg_temp.expect('E13: abrir un expediente sin ser de ingreso ni dirección → BV113', CW, 'authenticated', new_case, 'ERR:BV113');
    perform pg_temp.expect('E13: sin consentimiento general no se abre el expediente → BV401', DIR, 'authenticated',
        replace(new_case, '[{"consent_type":"general_care","status":"granted"}]', '[]'), 'ERR:BV401');
    perform pg_temp.expect('E13: marcadores sin consentimiento de datos sensibles → BV402', DIR, 'authenticated',
        replace(new_case, 'array[]::text[]', 'array[''disability'']::text[]'), 'ERR:BV402');
    perform pg_temp.expect('E13: anonimizar sin ser dirección → BV104', INT, 'authenticated',
        $q$select count(*)::text from (select public.fn_anonymize_person('aaaaaaaa-4000-0000-0000-000000000001'::uuid, 'Prueba')) x$q$, 'ERR:BV104');
    perform pg_temp.expect('E13: un registro de otra organización no se distingue de uno inexistente → BV201', DIRB2, 'authenticated',
        $q$select public.fn_assert_same_org('case', 'aaaaaaaa-5000-0000-0000-000000000001'::uuid)::text$q$, 'ERR:BV201');
    perform pg_temp.expect('E13: la auditoría no se edita (ni siquiera con el propietario) → BV605', null, null,
        $q$with u as (update public.audit_event set action = action where id = (select id from public.audit_event limit 1) returning 1) select count(*)::text from u$q$, 'ERR:BV605');
    perform pg_temp.expect('E13: el contenido de una entrada de bitácora no se edita → BV611', null, null,
        $q$with u as (update public.journal_entry set body = 'otro texto' where id = 'aaaaaaaa-6000-0000-0000-000000000001' returning 1) select count(*)::text from u$q$, 'ERR:BV611');

    -- ============================================================================================
    -- ===== E14 fase 1: documentos de la persona, religión, detalle de marcadores y referencia heredada
    -- ===== (migración 20261015000001). Datos sensibles: solo con consentimiento sensible vigente (D-14);
    -- ===== el log guarda nombres de campos, nunca valores; nada se borra: lo corregido se cierra.
    -- ============================================================================================
    -- Escenario propio: P1 con consentimiento sensible y marcador; P2 sin él; P3 con él revocado; P4 anonimizada
    insert into public.person (id, organization_id, given_name, paternal_family_name, birth_date) values
        (pg_temp.id('4000', 32)::uuid, ORG_A::uuid, 'Kappa', 'Documentada', '1985-03-04'),
        (pg_temp.id('4000', 33)::uuid, ORG_A::uuid, 'Lambda', 'SinSensible', '1985-03-04'),
        (pg_temp.id('4000', 34)::uuid, ORG_A::uuid, 'Mu', 'Revocada', '1985-03-04');
    insert into public.person (id, organization_id, given_name, paternal_family_name, birth_date, is_anonymized) values
        (pg_temp.id('4000', 35)::uuid, ORG_A::uuid, 'PERSONA ANONIMIZADA', 'SUPRIMIDO', '1985-01-01', true);
    insert into public."case" (id, organization_id, case_number, titular_person_id, opened_by, assigned_user_id, intake_window_type)
    select pg_temp.id('5000', 32 + k)::uuid, ORG_A::uuid, 'TST-A-0E' || (1 + k), pg_temp.id('4000', 32 + k)::uuid,
           'aaaaaaaa-3000-0000-0000-000000000003', 'aaaaaaaa-3000-0000-0000-000000000002', 'fija'
    from generate_series(0, 2) k;
    insert into public.consent (organization_id, person_id, case_id, consent_type, status, granted_by_user_id)
    select ORG_A::uuid, pg_temp.id('4000', 32 + k)::uuid, pg_temp.id('5000', 32 + k)::uuid, 'general_care', 'granted', 'aaaaaaaa-3000-0000-0000-000000000003'
    from generate_series(0, 2) k;
    insert into public.consent (organization_id, person_id, case_id, consent_type, status, granted_by_user_id) values
        (ORG_A::uuid, pg_temp.id('4000', 32)::uuid, pg_temp.id('5000', 32)::uuid, 'sensitive_data', 'granted', 'aaaaaaaa-3000-0000-0000-000000000003'),
        (ORG_A::uuid, 'aaaaaaaa-4000-0000-0000-000000000001'::uuid, 'aaaaaaaa-5000-0000-0000-000000000001', 'sensitive_data', 'granted', 'aaaaaaaa-3000-0000-0000-000000000003');
    -- P3: lo concedió hace dos días y lo retiró hoy; el vigente es el último (el consentimiento es un registro por evento)
    insert into public.consent (organization_id, person_id, case_id, consent_type, status, granted_by_user_id, granted_at)
    values (ORG_A::uuid, pg_temp.id('4000', 34)::uuid, pg_temp.id('5000', 34)::uuid, 'sensitive_data', 'granted', 'aaaaaaaa-3000-0000-0000-000000000003',
            now() - interval '2 days');
    insert into public.consent (organization_id, person_id, case_id, consent_type, status, granted_by_user_id, revoked_at, revoked_by_user_id, revocation_reason)
    values (ORG_A::uuid, pg_temp.id('4000', 34)::uuid, pg_temp.id('5000', 34)::uuid, 'sensitive_data', 'revoked', 'aaaaaaaa-3000-0000-0000-000000000003',
            now(), 'aaaaaaaa-3000-0000-0000-000000000003', 'Retiró el consentimiento');
    insert into public.case_vulnerability_marker (organization_id, case_id, marker_code, affirmed_by) values
        (ORG_A::uuid, pg_temp.id('5000', 32)::uuid, 'disability', 'aaaaaaaa-3000-0000-0000-000000000003'),
        (ORG_A::uuid, pg_temp.id('5000', 34)::uuid, 'disability', 'aaaaaaaa-3000-0000-0000-000000000003'),
        (ORG_A::uuid, 'aaaaaaaa-5000-0000-0000-000000000001', 'disability', 'aaaaaaaa-3000-0000-0000-000000000003');
    -- Catálogo de tipos de documento (lo escribe dirección; aquí el escenario lo siembra)
    begin
        insert into public.document_type (id, organization_id, key, label_es, is_active, sort_order) values
            (pg_temp.id('d000', 1)::uuid, ORG_A::uuid, 'curp', 'CURP de prueba', true, 1),
            (pg_temp.id('d000', 2)::uuid, ORG_A::uuid, 'passport', 'Pasaporte de prueba', true, 2),
            (pg_temp.id('d000', 3)::uuid, ORG_A::uuid, 'retired', 'Tipo retirado', false, 3),
            ('bbbbbbbb-d000-0000-0000-000000000001'::uuid, ORG_B::uuid, 'curp', 'CURP B', true, 1);
    exception when others then
        raise notice 'E14 escenario: sin tabla document_type todavía (%).', sqlerrm;
    end;

    -- ----- La estructura nueva existe y está protegida
    perform pg_temp.expect('E14: document_type y person_document tienen RLS activa', null, null,
        $q$select count(*)::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relname in ('document_type', 'person_document') and c.relrowsecurity$q$, '2');

    -- ----- Documentos de la persona: roles
    perform pg_temp.expect('E14 control positivo: dirección registra un documento (CURP)', DIR, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_document(%L::uuid, %L::uuid, 'CURP-FICTICIA-0001')) x$q$, pg_temp.id('4000', 32), pg_temp.id('d000', 1)), '1');
    perform pg_temp.expect('E14 control positivo: quien atiende el caso registra otro tipo de documento', CW, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_document(%L::uuid, %L::uuid, 'PASAPORTE-FICTICIO-77')) x$q$, pg_temp.id('4000', 32), pg_temp.id('d000', 2)), '1');
    perform pg_temp.expect('E14: el rol de solo lectura no registra documentos → BV120', VW, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_document(%L::uuid, %L::uuid, 'X-1')) x$q$, pg_temp.id('4000', 33), pg_temp.id('d000', 1)), 'ERR:BV120');
    perform pg_temp.expect('E14: el voluntariado no registra documentos → BV120', VOL, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_document(%L::uuid, %L::uuid, 'X-1')) x$q$, pg_temp.id('4000', 33), pg_temp.id('d000', 1)), 'ERR:BV120');
    perform pg_temp.expect('E14: sin rol vigente no registra documentos → BV120', NR, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_document(%L::uuid, %L::uuid, 'X-1')) x$q$, pg_temp.id('4000', 33), pg_temp.id('d000', 1)), 'ERR:BV120');
    perform pg_temp.expect('E14: anónimo no registra documentos', null, 'anon',
        format($q$select count(*)::text from (select public.fn_set_person_document(%L::uuid, %L::uuid, 'X-1')) x$q$, pg_temp.id('4000', 33), pg_temp.id('d000', 1)), 'ERR');
    perform pg_temp.expect('E14: dirección de otra organización no ve a la persona → BV201', DIRB2, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_document(%L::uuid, 'bbbbbbbb-d000-0000-0000-000000000001'::uuid, 'X-1')) x$q$, pg_temp.id('4000', 32)), 'ERR:BV201');
    perform pg_temp.expect('E14: no se usa un tipo de documento de otra organización → BV211', DIR, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_document(%L::uuid, 'bbbbbbbb-d000-0000-0000-000000000001'::uuid, 'X-1')) x$q$, pg_temp.id('4000', 33)), 'ERR:BV211');
    perform pg_temp.expect('E14: no se usa un tipo de documento retirado → BV211', DIR, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_document(%L::uuid, %L::uuid, 'X-1')) x$q$, pg_temp.id('4000', 33), pg_temp.id('d000', 3)), 'ERR:BV211');
    perform pg_temp.expect('E14: a una persona anonimizada no se le agregan documentos → BV507', DIR, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_document(%L::uuid, %L::uuid, 'X-1')) x$q$, pg_temp.id('4000', 35), pg_temp.id('d000', 1)), 'ERR:BV507');
    perform pg_temp.expect('E14: el número de documento no puede ir vacío → BV320', DIR, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_document(%L::uuid, %L::uuid, '   ')) x$q$, pg_temp.id('4000', 33), pg_temp.id('d000', 1)), 'ERR:BV320');
    perform pg_temp.expect('E14: el número de documento no puede ser larguísimo → BV321', DIR, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_document(%L::uuid, %L::uuid, repeat('9', 61))) x$q$, pg_temp.id('4000', 33), pg_temp.id('d000', 1)), 'ERR:BV321');

    -- ----- Documentos: lo corregido se cierra, no se sobrescribe
    perform pg_temp.expect('E14: cambiar el número de un documento exige motivo → BV304', DIR, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_document(%L::uuid, %L::uuid, 'CURP-FICTICIA-0002')) x$q$, pg_temp.id('4000', 32), pg_temp.id('d000', 1)), 'ERR:BV304');
    perform pg_temp.expect('E14 control positivo: con motivo se reemplaza el número', DIR, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_document(%L::uuid, %L::uuid, 'CURP-FICTICIA-0002', 'Error de captura')) x$q$, pg_temp.id('4000', 32), pg_temp.id('d000', 1)), '1');
    perform pg_temp.expect('E14: tras reemplazar hay un solo documento vigente de ese tipo', null, null,
        format($q$select count(*)::text from public.person_document where person_id = %L::uuid and document_type_id = %L::uuid and valid_to is null$q$, pg_temp.id('4000', 32), pg_temp.id('d000', 1)), '1');
    perform pg_temp.expect('E14: el anterior no se borró: queda cerrado con su motivo', null, null,
        format($q$select count(*)::text from public.person_document where person_id = %L::uuid and document_type_id = %L::uuid and valid_to is not null and change_reason = 'Error de captura'$q$, pg_temp.id('4000', 32), pg_temp.id('d000', 1)), '1');
    perform pg_temp.expect('E14: repetir el mismo número no crea otro registro', DIR, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_document(%L::uuid, %L::uuid, 'CURP-FICTICIA-0002')) x$q$, pg_temp.id('4000', 32), pg_temp.id('d000', 1)), '1');
    perform pg_temp.expect('E14: sigue habiendo 2 registros del tipo (uno cerrado y uno vigente)', null, null,
        format($q$select count(*)::text from public.person_document where person_id = %L::uuid and document_type_id = %L::uuid$q$, pg_temp.id('4000', 32), pg_temp.id('d000', 1)), '2');

    -- ----- Documentos: nada de escritura directa, nadie ve lo ajeno
    perform pg_temp.expect('E14: no se inserta un documento por la API directa', DIR, 'authenticated',
        format($q$with i as (insert into public.person_document (organization_id, person_id, document_type_id, document_number, created_by)
                  values (%L, %L::uuid, %L::uuid, 'DIRECTO-1', %L) returning 1) select count(*)::text from i$q$,
               ORG_A::uuid, pg_temp.id('4000', 33), pg_temp.id('d000', 1), DIR), 'ERR');
    perform pg_temp.expect('E14: no se edita un documento por la API directa', DIR, 'authenticated',
        $q$with u as (update public.person_document set document_number = 'EDITADO' returning 1) select count(*)::text from u$q$, 'ERR');
    perform pg_temp.expect('E14: no se borra un documento por la API directa (Regla Dura 3)', DIR, 'authenticated',
        $q$with d as (delete from public.person_document returning 1) select count(*)::text from d$q$, 'ERR');
    perform pg_temp.expect('E14 control positivo: dirección ve los documentos de su organización', DIR, 'authenticated',
        'select count(*)::text from public.person_document', '>0');
    perform pg_temp.expect('E14 control positivo: quien atiende los ve', CW, 'authenticated',
        'select count(*)::text from public.person_document', '>0');
    perform pg_temp.expect('E14: el rol de solo lectura no ve documentos', VW, 'authenticated',
        'select count(*)::text from public.person_document', '0');
    perform pg_temp.expect('E14: sin rol no se ven documentos', NR, 'authenticated',
        'select count(*)::text from public.person_document', '0');
    perform pg_temp.expect('E14: otra organización no ve los documentos de A', DIRB2, 'authenticated',
        'select count(*)::text from public.person_document', '0');
    perform pg_temp.expect('E14: el log de auditoría deja eventos del documento', null, null,
        $q$select count(*)::text from public.audit_event where table_name = 'person_document' and created_at >= transaction_timestamp()$q$, '>0');
    perform pg_temp.expect('E14: ningún número de documento aparece en el log de auditoría', null, null,
        $q$select count(*)::text from public.audit_event where created_at >= transaction_timestamp()
           and (coalesce(new_values::text, '') ilike '%CURP-FICTICIA%' or coalesce(old_values::text, '') ilike '%CURP-FICTICIA%'
                or coalesce(new_values::text, '') ilike '%PASAPORTE-FICTICIO%')$q$, '0');

    -- ----- Quitar un documento: se cierra con motivo, no se borra
    perform pg_temp.expect('E14: quitar un documento exige motivo → BV304', CW, 'authenticated',
        format($q$select count(*)::text from (select public.fn_remove_person_document(d.id, '') from public.person_document d where d.person_id = %L::uuid and d.document_type_id = %L::uuid and d.valid_to is null) x$q$, pg_temp.id('4000', 32), pg_temp.id('d000', 2)), 'ERR:BV304');
    perform pg_temp.expect('E14 control positivo: con motivo se quita (se cierra) el documento', CW, 'authenticated',
        format($q$select count(*)::text from (select public.fn_remove_person_document(d.id, 'Documento equivocado') from public.person_document d where d.person_id = %L::uuid and d.document_type_id = %L::uuid and d.valid_to is null) x$q$, pg_temp.id('4000', 32), pg_temp.id('d000', 2)), '1');
    perform pg_temp.expect('E14: quitar un documento ya cerrado → BV509', CW, 'authenticated',
        format($q$select count(*)::text from (select public.fn_remove_person_document(d.id, 'Otra vez') from public.person_document d where d.person_id = %L::uuid and d.document_type_id = %L::uuid and d.valid_to is not null) x$q$, pg_temp.id('4000', 32), pg_temp.id('d000', 2)), 'ERR:BV509');
    perform pg_temp.expect('E14: un documento que no existe → BV212', CW, 'authenticated',
        $q$select count(*)::text from (select public.fn_remove_person_document('aaaaaaaa-d000-0000-0000-0000000000ff'::uuid, 'x')) x$q$, 'ERR:BV212');
    perform pg_temp.expect('E14: dirección de otra organización no quita documentos de A → BV212', DIRB2, 'authenticated',
        format($q$select count(*)::text from (select public.fn_remove_person_document(d.id, 'x') from public.person_document d where d.person_id = %L::uuid and d.valid_to is null limit 1) x$q$, pg_temp.id('4000', 32)), '0|ERR:BV212');

    -- ----- Catálogo de tipos de documento
    perform pg_temp.expect('E14 control positivo: dirección agrega un tipo de documento', DIR, 'authenticated',
        format($q$with i as (insert into public.document_type (organization_id, key, label_es, sort_order) values (%L, 'nuevo_tipo', 'Nuevo tipo', 9) returning 1) select count(*)::text from i$q$, ORG_A), '1');
    perform pg_temp.expect('E14 control positivo: Trabajo Social (caseworker del área) administra el catálogo', CW, 'authenticated',
        format($q$with i as (insert into public.document_type (organization_id, key, label_es, sort_order) values (%L, 'tipo_de_ts', 'Tipo de TS', 9) returning 1) select count(*)::text from i$q$, ORG_A), '1');
    perform pg_temp.expect('E14: el área jurídica no administra el catálogo', 'aaaaaaaa-3000-0000-0000-00000000000a', 'authenticated',
        format($q$with i as (insert into public.document_type (organization_id, key, label_es, sort_order) values (%L, 'otro_tipo', 'Otro tipo', 9) returning 1) select count(*)::text from i$q$, ORG_A), 'ERR');
    perform pg_temp.expect('E14: ingreso sin área de Trabajo Social no administra el catálogo', INT, 'authenticated',
        format($q$with i as (insert into public.document_type (organization_id, key, label_es, sort_order) values (%L, 'otro_tipo2', 'Otro tipo', 9) returning 1) select count(*)::text from i$q$, ORG_A), 'ERR');
    perform pg_temp.expect('E14: el rol de solo lectura no administra el catálogo', VW, 'authenticated',
        format($q$with i as (insert into public.document_type (organization_id, key, label_es, sort_order) values (%L, 'otro_tipo3', 'Otro tipo', 9) returning 1) select count(*)::text from i$q$, ORG_A), 'ERR');
    perform pg_temp.expect('E14: Trabajo Social no cambia el catálogo de otra organización', CW, 'authenticated',
        format($q$with i as (insert into public.document_type (organization_id, key, label_es, sort_order) values (%L, 'ajeno_ts', 'Ajeno', 9) returning 1) select count(*)::text from i$q$, ORG_B), 'ERR');
    perform pg_temp.expect('E14: Trabajo Social desactiva un tipo (no lo borra)', CW, 'authenticated',
        format($q$with u as (update public.document_type set is_active = false where id = %L::uuid returning 1) select count(*)::text from u$q$, pg_temp.id('d000', 2)), '1');
    perform pg_temp.expect('E14: el catálogo de A no admite tipos en la organización B', DIR, 'authenticated',
        format($q$with i as (insert into public.document_type (organization_id, key, label_es, sort_order) values (%L, 'ajeno', 'Ajeno', 9) returning 1) select count(*)::text from i$q$, ORG_B), 'ERR');
    perform pg_temp.expect('E14: no se borra un tipo de documento (se desactiva)', DIR, 'authenticated',
        $q$with d as (delete from public.document_type returning 1) select count(*)::text from d$q$, 'ERR');
    perform pg_temp.expect('E14: dirección de B no ve los tipos de A', DIRB2, 'authenticated',
        format('select count(*)::text from public.document_type where organization_id = %L', ORG_A), '0');
    perform pg_temp.expect('E14: sin rol no se ve el catálogo de tipos', NR, 'authenticated',
        'select count(*)::text from public.document_type', '0');

    -- ----- Diccionarios editables (E14 fase 4a): idioma y religión; la religión es un valor del diccionario + detalle
    begin
        insert into public.catalog_item (id, organization_id, catalog, key, label_es, is_active, is_system, sort_order) values
            ('aaaaaaaa-c000-0000-0000-000000000001', ORG_A::uuid, 'religion', 'catholic', 'Católico (prueba)', true, false, 1),
            ('aaaaaaaa-c000-0000-0000-000000000002', ORG_A::uuid, 'religion', 'other', 'Otro (prueba)', true, false, 2),
            ('aaaaaaaa-c000-0000-0000-000000000003', ORG_A::uuid, 'religion', 'no_response', 'La persona no quiso responder', true, true, 99),
            ('aaaaaaaa-c000-0000-0000-000000000004', ORG_A::uuid, 'religion', 'retired', 'Valor retirado', false, false, 5),
            ('aaaaaaaa-c000-0000-0000-000000000011', ORG_A::uuid, 'language', 'spanish', 'Español (prueba)', true, false, 1),
            ('aaaaaaaa-c000-0000-0000-000000000012', ORG_A::uuid, 'language', 'indigenous', 'Lengua indígena (prueba)', true, false, 2),
            ('aaaaaaaa-c000-0000-0000-000000000013', ORG_A::uuid, 'language', 'no_response', 'La persona no quiso responder', true, true, 99),
            ('bbbbbbbb-c000-0000-0000-000000000001', ORG_B::uuid, 'religion', 'catholic', 'Católico B', true, false, 1);
    exception when others then
        raise notice 'F4a escenario: sin tabla catalog_item todavía (%).', sqlerrm;
    end;

    -- ----- Religión: dato sensible, solo con consentimiento sensible vigente («no quiso responder» no es dato sensible)
    perform pg_temp.expect('F4a control positivo: ingreso registra la religión (valor del diccionario) con consentimiento sensible', INT, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_religion(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000001'::uuid, null, null)) x$q$, pg_temp.id('4000', 32)), '1');
    perform pg_temp.expect('F4a: sin consentimiento sensible no se registra una religión → BV408', INT, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_religion(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000001'::uuid, null, null)) x$q$, pg_temp.id('4000', 33)), 'ERR:BV408');
    perform pg_temp.expect('F4a: con el consentimiento sensible revocado tampoco → BV408', INT, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_religion(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000001'::uuid, null, null)) x$q$, pg_temp.id('4000', 34)), 'ERR:BV408');
    perform pg_temp.expect('F4a control positivo: «la persona no quiso responder» se registra sin consentimiento sensible (no es un dato)', INT, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_religion(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000003'::uuid, null, null)) x$q$, pg_temp.id('4000', 33)), '1');
    perform pg_temp.expect('F4a: quien atiende el caso no registra la religión → BV121', CW, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_religion(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000001'::uuid, null, null)) x$q$, pg_temp.id('4000', 32)), 'ERR:BV121');
    perform pg_temp.expect('F4a: el rol de solo lectura no registra la religión → BV121', VW, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_religion(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000001'::uuid, null, null)) x$q$, pg_temp.id('4000', 32)), 'ERR:BV121');
    perform pg_temp.expect('F4a: dirección de otra organización no la registra → BV201', DIRB2, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_religion(%L::uuid, 'bbbbbbbb-c000-0000-0000-000000000001'::uuid, null, null)) x$q$, pg_temp.id('4000', 32)), 'ERR:BV201');
    perform pg_temp.expect('F4a: una persona anonimizada no admite religión → BV507', DIR, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_religion(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000001'::uuid, null, null)) x$q$, pg_temp.id('4000', 35)), 'ERR:BV507');
    perform pg_temp.expect('F4a: un valor de otra organización no se usa → BV220', DIR, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_religion(%L::uuid, 'bbbbbbbb-c000-0000-0000-000000000001'::uuid, null, 'x')) x$q$, pg_temp.id('4000', 32)), 'ERR:BV220');
    perform pg_temp.expect('F4a: un valor retirado del diccionario no se usa → BV220', DIR, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_religion(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000004'::uuid, null, 'x')) x$q$, pg_temp.id('4000', 32)), 'ERR:BV220');
    perform pg_temp.expect('F4a: un valor de otro diccionario (idioma) no vale como religión → BV220', DIR, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_religion(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000011'::uuid, null, 'x')) x$q$, pg_temp.id('4000', 32)), 'ERR:BV220');
    perform pg_temp.expect('F4a: cambiar la religión ya registrada exige motivo → BV304', INT, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_religion(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000002'::uuid, 'Detalle de prueba', null)) x$q$, pg_temp.id('4000', 32)), 'ERR:BV304');
    perform pg_temp.expect('F4a control positivo: con motivo se cambia la religión y se agrega su detalle', INT, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_religion(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000002'::uuid, 'Detalle de prueba', 'La persona lo precisó')) x$q$, pg_temp.id('4000', 32)), '1');
    perform pg_temp.expect('F4a: quitar la religión ya registrada también exige motivo → BV304', INT, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_religion(%L::uuid, null, null, null)) x$q$, pg_temp.id('4000', 32)), 'ERR:BV304');
    perform pg_temp.expect('F4a: el detalle es un texto acotado → BV321', INT, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_religion(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000002'::uuid, repeat('r', 121), 'x')) x$q$, pg_temp.id('4000', 32)), 'ERR:BV321');
    perform pg_temp.expect('F4a: un detalle sin valor del diccionario no se acepta → BV333', INT, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_religion(%L::uuid, null, 'Solo detalle', 'x')) x$q$, pg_temp.id('4000', 32)), 'ERR:BV333');
    perform pg_temp.expect('F4a: la religión quedó guardada como valor del diccionario', null, null,
        format('select religion_item_id::text from public.person where id = %L::uuid', pg_temp.id('4000', 32)), 'aaaaaaaa-c000-0000-0000-000000000002');
    perform pg_temp.expect('F4a: y su detalle', null, null,
        format('select religion_detail from public.person where id = %L::uuid', pg_temp.id('4000', 32)), 'Detalle de prueba');
    perform pg_temp.expect('F4a: el detalle de la religión no aparece en el log de auditoría', null, null,
        $q$select count(*)::text from public.audit_event where created_at >= transaction_timestamp()
           and (coalesce(new_values::text, '') ilike '%Detalle de prueba%' or coalesce(old_values::text, '') ilike '%Detalle de prueba%')$q$, '0');

    -- ----- Idioma: valor del diccionario + detalle; dato sensible (D-14), «no quiso responder» no lo es
    perform pg_temp.expect('F4a control positivo: quien atiende registra el idioma con consentimiento sensible', CW, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_language(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000012'::uuid, 'Tzotzil', null)) x$q$, pg_temp.id('4000', 32)), '1');
    perform pg_temp.expect('F4a: sin consentimiento sensible no se registra un idioma → BV408', CW, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_language(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000011'::uuid, null, null)) x$q$, pg_temp.id('4000', 34)), 'ERR:BV408');
    perform pg_temp.expect('F4a control positivo: «la persona no quiso responder» en idioma sin consentimiento sensible', CW, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_language(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000013'::uuid, null, null)) x$q$, pg_temp.id('4000', 34)), '1');
    perform pg_temp.expect('F4a: el rol de solo lectura no registra el idioma → BV120', VW, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_language(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000011'::uuid, null, null)) x$q$, pg_temp.id('4000', 32)), 'ERR:BV120');
    perform pg_temp.expect('F4a: el voluntariado no registra el idioma → BV120', VOL, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_language(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000011'::uuid, null, null)) x$q$, pg_temp.id('4000', 32)), 'ERR:BV120');
    perform pg_temp.expect('F4a: dirección de otra organización no lo registra → BV201', DIRB2, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_language(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000011'::uuid, null, null)) x$q$, pg_temp.id('4000', 32)), 'ERR:BV201');
    perform pg_temp.expect('F4a: una persona anonimizada no admite idioma → BV507', DIR, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_language(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000011'::uuid, null, null)) x$q$, pg_temp.id('4000', 35)), 'ERR:BV507');
    perform pg_temp.expect('F4a: un valor de religión no vale como idioma → BV220', DIR, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_language(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000001'::uuid, null, 'x')) x$q$, pg_temp.id('4000', 32)), 'ERR:BV220');
    perform pg_temp.expect('F4a: cambiar el idioma ya registrado exige motivo → BV304', DIR, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_language(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000011'::uuid, null, null)) x$q$, pg_temp.id('4000', 32)), 'ERR:BV304');
    perform pg_temp.expect('F4a control positivo: con motivo se cambia el idioma', DIR, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_language(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000011'::uuid, null, 'Era otro')) x$q$, pg_temp.id('4000', 32)), '1');
    perform pg_temp.expect('F4a: el idioma quedó guardado como valor del diccionario', null, null,
        format('select primary_language_item_id::text from public.person where id = %L::uuid', pg_temp.id('4000', 32)), 'aaaaaaaa-c000-0000-0000-000000000011');
    perform pg_temp.expect('F4a: el detalle del idioma es un texto acotado → BV321', DIR, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_language(%L::uuid, 'aaaaaaaa-c000-0000-0000-000000000012'::uuid, repeat('l', 121), 'x')) x$q$, pg_temp.id('4000', 32)), 'ERR:BV321');

    -- ----- El diccionario lo administran dirección y Trabajo Social; los valores del sistema no se retiran
    perform pg_temp.expect('F4a control positivo: Trabajo Social agrega un valor a un diccionario', CW, 'authenticated',
        format($q$with i as (insert into public.catalog_item (organization_id, catalog, key, label_es, sort_order) values (%L, 'religion', 'nuevo_valor', 'Valor nuevo', 8) returning 1) select count(*)::text from i$q$, ORG_A), '1');
    perform pg_temp.expect('F4a: el área jurídica no administra los diccionarios', 'aaaaaaaa-3000-0000-0000-00000000000a', 'authenticated',
        format($q$with i as (insert into public.catalog_item (organization_id, catalog, key, label_es, sort_order) values (%L, 'religion', 'otro_valor', 'Otro', 9) returning 1) select count(*)::text from i$q$, ORG_A), 'ERR');
    perform pg_temp.expect('F4a: no se inventan diccionarios nuevos desde la API', DIR, 'authenticated',
        format($q$with i as (insert into public.catalog_item (organization_id, catalog, key, label_es, sort_order) values (%L, 'inventado', 'x', 'X', 9) returning 1) select count(*)::text from i$q$, ORG_A), 'ERR');
    perform pg_temp.expect('F4a: dirección no escribe en los diccionarios de otra organización', DIR, 'authenticated',
        format($q$with i as (insert into public.catalog_item (organization_id, catalog, key, label_es, sort_order) values (%L, 'religion', 'ajeno', 'Ajeno', 9) returning 1) select count(*)::text from i$q$, ORG_B), 'ERR');
    perform pg_temp.expect('F4a control positivo: se desactiva un valor (no se borra)', DIR, 'authenticated',
        $q$with u as (update public.catalog_item set is_active = false where id = 'aaaaaaaa-c000-0000-0000-000000000001' returning 1) select count(*)::text from u$q$, '1');
    perform pg_temp.expect('F4a: no se borra un valor de diccionario', DIR, 'authenticated',
        $q$with d as (delete from public.catalog_item returning 1) select count(*)::text from d$q$, 'ERR');
    perform pg_temp.expect('F4a: el valor del sistema «no quiso responder» no se desactiva → BV614', DIR, 'authenticated',
        $q$with u as (update public.catalog_item set is_active = false where id = 'aaaaaaaa-c000-0000-0000-000000000003' returning 1) select count(*)::text from u$q$, 'ERR:BV614');
    perform pg_temp.expect('F4a: ni cambia de clave → BV614', DIR, 'authenticated',
        $q$with u as (update public.catalog_item set key = 'otra_clave' where id = 'aaaaaaaa-c000-0000-0000-000000000003' returning 1) select count(*)::text from u$q$, 'ERR:BV614');
    perform pg_temp.expect('F4a control positivo: sí se le puede editar la etiqueta', DIR, 'authenticated',
        $q$with u as (update public.catalog_item set label_es = 'No quiso responder' where id = 'aaaaaaaa-c000-0000-0000-000000000003' returning 1) select count(*)::text from u$q$, '1');
    perform pg_temp.expect('F4a: el rol de solo lectura ve los diccionarios', VW, 'authenticated', 'select (count(*) > 0)::text from public.catalog_item', 'true');
    perform pg_temp.expect('F4a: sin rol no se ven los diccionarios', NR, 'authenticated', 'select count(*)::text from public.catalog_item', '0');
    perform pg_temp.expect('F4a: otra organización no ve los diccionarios de A', DIRB2, 'authenticated',
        format('select count(*)::text from public.catalog_item where organization_id = %L', ORG_A), '0');

    -- ----- Detalle de los marcadores de vulnerabilidad
    perform pg_temp.expect('E14 control positivo: quien atiende detalla un marcador existente', CW, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_marker_detail(%L::uuid, 'disability', 'DETALLE-SECRETO-visual')) x$q$, pg_temp.id('5000', 32)), '1');
    perform pg_temp.expect('E14: el detalle quedó en el marcador', null, null,
        format($q$select notes from public.case_vulnerability_marker where case_id = %L::uuid and marker_code = 'disability'$q$, pg_temp.id('5000', 32)), 'DETALLE-SECRETO-visual');
    perform pg_temp.expect('E14: no se detalla un marcador que el expediente no tiene → BV213', CW, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_marker_detail(%L::uuid, 'lgbtiq', 'x')) x$q$, pg_temp.id('5000', 32)), 'ERR:BV213');
    perform pg_temp.expect('E14: el rol de solo lectura no detalla marcadores → BV120', VW, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_marker_detail(%L::uuid, 'disability', 'x')) x$q$, pg_temp.id('5000', 32)), 'ERR:BV120');
    perform pg_temp.expect('E14: dirección de otra organización no detalla marcadores de A → BV201', DIRB2, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_marker_detail(%L::uuid, 'disability', 'x')) x$q$, pg_temp.id('5000', 32)), 'ERR:BV201');
    perform pg_temp.expect('E14: el detalle del marcador es un texto acotado → BV321', CW, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_marker_detail(%L::uuid, 'disability', repeat('d', 501))) x$q$, pg_temp.id('5000', 32)), 'ERR:BV321');
    perform pg_temp.expect('E14: con el consentimiento sensible revocado no se agrega detalle → BV408', CW, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_marker_detail(%L::uuid, 'disability', 'detalle nuevo')) x$q$, pg_temp.id('5000', 34)), 'ERR:BV408');
    perform pg_temp.expect('E14: sí se puede quitar el detalle aunque el consentimiento esté revocado', CW, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_marker_detail(%L::uuid, 'disability', '')) x$q$, pg_temp.id('5000', 34)), '1');
    perform pg_temp.expect('E14: el detalle del marcador no aparece en el log de auditoría', null, null,
        $q$select count(*)::text from public.audit_event where created_at >= transaction_timestamp()
           and (coalesce(new_values::text, '') ilike '%DETALLE-SECRETO%' or coalesce(old_values::text, '') ilike '%DETALLE-SECRETO%')$q$, '0');

    -- ----- Referencia heredada (el EXPEDIENTE de la hoja anterior)
    perform pg_temp.expect('E14 control positivo: ingreso registra la referencia heredada', INT, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_case_legacy_reference(%L::uuid, 'HOJA-0001')) x$q$, pg_temp.id('5000', 33)), '1');
    perform pg_temp.expect('E14: el rol de solo lectura no registra referencias → BV120', VW, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_case_legacy_reference(%L::uuid, 'HOJA-9')) x$q$, pg_temp.id('5000', 33)), 'ERR:BV120');
    perform pg_temp.expect('E14: dirección de otra organización no la registra → BV201', DIRB2, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_case_legacy_reference(%L::uuid, 'HOJA-9')) x$q$, pg_temp.id('5000', 33)), 'ERR:BV201');
    perform pg_temp.expect('E14: cambiar la referencia ya registrada exige motivo → BV304', INT, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_case_legacy_reference(%L::uuid, 'HOJA-0002')) x$q$, pg_temp.id('5000', 33)), 'ERR:BV304');
    perform pg_temp.expect('E14 control positivo: con motivo se cambia la referencia', INT, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_case_legacy_reference(%L::uuid, 'HOJA-0002', 'Estaba mal copiada')) x$q$, pg_temp.id('5000', 33)), '1');
    perform pg_temp.expect('E14: la referencia es un texto acotado → BV321', INT, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_case_legacy_reference(%L::uuid, repeat('h', 121), 'x')) x$q$, pg_temp.id('5000', 33)), 'ERR:BV321');
    perform pg_temp.expect('E14: el expediente se encuentra por su referencia heredada', DIR, 'authenticated',
        $q$select case_number from public."case" where legacy_reference = 'HOJA-0002'$q$, 'TST-A-0E2');
    perform pg_temp.expect('E14: el folio de caso no cambia al poner la referencia heredada', null, null,
        format('select case_number from public."case" where id = %L::uuid', pg_temp.id('5000', 33)), 'TST-A-0E2');
    perform pg_temp.expect('E14: la referencia heredada no se escribe por la API directa', INT, 'authenticated',
        format($q$with u as (update public."case" set legacy_reference = 'DIRECTA' where id = %L::uuid returning 1) select count(*)::text from u$q$, pg_temp.id('5000', 33)), 'ERR');

    -- ----- El extracto de acceso ARCO incluye lo nuevo (derecho de acceso)
    perform pg_temp.expect('E14: el extracto ARCO incluye los documentos de la persona', DIR, 'authenticated',
        format($q$select jsonb_array_length(public.fn_generate_arco_access_extract(%L::uuid)->'documents')::text$q$, pg_temp.id('4000', 32)), '>0');
    perform pg_temp.expect('F4a: el extracto ARCO incluye la religión (valor y detalle)', DIR, 'authenticated',
        format($q$select (public.fn_generate_arco_access_extract(%L::uuid)->'person'->>'religion') || '/' || (public.fn_generate_arco_access_extract(%L::uuid)->'person'->>'religion_detail')$q$, pg_temp.id('4000', 32), pg_temp.id('4000', 32)), 'Otro (prueba)/Detalle de prueba');
    perform pg_temp.expect('F4a: el extracto ARCO incluye el idioma', DIR, 'authenticated',
        format($q$select public.fn_generate_arco_access_extract(%L::uuid)->'person'->>'language'$q$, pg_temp.id('4000', 32)), 'Español (prueba)');
    perform pg_temp.expect('E14: el extracto ARCO incluye el detalle de los marcadores', DIR, 'authenticated',
        format($q$select jsonb_array_length(public.fn_generate_arco_access_extract(%L::uuid)->'vulnerability_markers')::text$q$, pg_temp.id('4000', 32)), '>0');

    -- ----- Para la prueba de anonimización: PERS_A también tiene documento, religión y detalle de marcador
    perform pg_temp.expect('E14 prep: documento de la persona que se anonimiza', DIR, 'authenticated',
        format($q$select count(*)::text from (select public.fn_set_person_document('aaaaaaaa-4000-0000-0000-000000000001'::uuid, %L::uuid, 'CURP-PARA-BORRAR-1')) x$q$, pg_temp.id('d000', 1)), '1');
    perform pg_temp.expect('E14 prep: religión de la persona que se anonimiza', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_set_person_religion('aaaaaaaa-4000-0000-0000-000000000001'::uuid, 'aaaaaaaa-c000-0000-0000-000000000002'::uuid, 'RELIGION-PARA-BORRAR', null)) x$q$, '1');
    perform pg_temp.expect('F4a prep: idioma de la persona que se anonimiza', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_set_person_language('aaaaaaaa-4000-0000-0000-000000000001'::uuid, 'aaaaaaaa-c000-0000-0000-000000000012'::uuid, 'IDIOMA-PARA-BORRAR', null)) x$q$, '1');
    perform pg_temp.expect('E14 prep: detalle de marcador de la persona que se anonimiza', DIR, 'authenticated',
        $q$select count(*)::text from (select public.fn_set_marker_detail('aaaaaaaa-5000-0000-0000-000000000001'::uuid, 'disability', 'DETALLE-PARA-BORRAR')) x$q$, '1');

    -- ============================================================================================
    -- ===== E14 fase 1b: cero valores supuestos y bloqueo de campos sensibles (migraciones 20261015000002/3)
    -- ===== Obligatorio no resuelto → la base detiene; opcional no resuelto → vacío, nunca un valor puesto por el sistema.
    -- ============================================================================================
    declare
        b6 constant text := 'false,null,null,null,null,null,null,''fija''';           -- sexo, nacionalidad, otra nacionalidad, lengua, otra lengua, teléfono
        ctx constant text := '''fija'',false,null,null,null,null,null,';              -- ventanilla, viaja, estado, municipio, canal, vía, fecha de ingreso
        sens text := '"consent_type":"general_care","status":"granted"}]';
        sens_new text := '"consent_type":"general_care","status":"granted"},{"consent_type":"sensitive_data","status":"granted"}]';
        subf text := $sf$select count(*)::text from (select public.fn_create_subfolio(
            'aaaaaaaa-5000-0000-0000-0000000000d1'::uuid, 'Niña','HijaB',null,null,(current_date - interval '6 years')::date,false,null,null,null,null,null,
            'madre','Viaja con su madre; se abre su expediente propio.', array[]::text[],
            '[{"consent_type":"general_care","status":"granted","is_minor_assent":true}]'::jsonb)) x$sf$;
    begin
        -- Catálogos de ingreso de la organización A (el escenario de la prueba no pasa por la migración)
        insert into public.intake_channel (organization_id, code, label_es) values (ORG_A::uuid, 1, 'Empresa'), (ORG_A::uuid, 5, 'Ventanilla');
        insert into public.entry_route (organization_id, code, label_es) values (ORG_A::uuid, 1, 'Aérea'), (ORG_A::uuid, 3, 'Terrestre');

        -- ----- La estructura: nada de valores por defecto en datos de personas ni de casos
        perform pg_temp.expect('1b: sexo, nacionalidad, lengua y «se considera migrante» no tienen valor por defecto ni son obligatorios', null, null,
            $q$select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'person'
               and column_name in ('sex_id', 'nationality_country_id', 'primary_language_id', 'is_self_identified_migrant')
               and (column_default is not null or is_nullable = 'NO')$q$, '0');
        perform pg_temp.expect('1b: estado, canal, vía de ingreso y «viaja con familia» no tienen valor por defecto ni son obligatorios', null, null,
            $q$select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'case'
               and column_name in ('intake_state_id', 'intake_municipality_key', 'intake_channel_id', 'entry_route_id', 'travels_with_family')
               and (column_default is not null or is_nullable = 'NO')$q$, '0');
        perform pg_temp.expect('1b: el tipo de ventanilla es obligatorio y sin valor por defecto', null, null,
            $q$select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'case'
               and column_name = 'intake_window_type' and column_default is null and is_nullable = 'NO'$q$, '1');
        perform pg_temp.expect('1b: el estado de un consentimiento no tiene valor por defecto', null, null,
            $q$select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'consent'
               and column_name = 'status' and column_default is null$q$, '1');
        perform pg_temp.expect('1b: ninguna columna de dato de persona o de caso trae valor por defecto (salvo las técnicas)', null, null,
            $q$select count(*)::text from information_schema.columns
               where table_schema = 'public' and table_name in ('person', 'case', 'consent', 'case_vulnerability_marker', 'person_document')
                 and column_default is not null
                 and column_name not in ('id', 'created_at', 'updated_at', 'opened_at', 'intake_date', 'granted_at', 'affirmed_at',
                                         'birth_date_is_estimated', 'is_anonymized', 'occupations', 'is_minor_assent')$q$, '0');
        perform pg_temp.expect('1b: una persona sin esos datos queda con ellos vacíos, no inventados', null, null,
            format($q$select (sex_id is null and nationality_country_id is null and primary_language_id is null and is_self_identified_migrant is null)::text
                      from public.person where id = %L::uuid$q$, pg_temp.id('4000', 33)), 'true');
        perform pg_temp.expect('1b: un expediente sin contexto de ingreso queda con él vacío, no inventado', null, null,
            $q$select (intake_state_id is null and intake_municipality_key is null and intake_channel_id is null and entry_route_id is null and travels_with_family is null)::text
               from public."case" where case_number = 'TST-A-0E2'$q$, 'true');
        perform pg_temp.expect('1b: el sexo vacío cuenta como «sin dato» en los indicadores', null, null,
            format($q$select count(*)::text from public.fn_metric_rows(%L::uuid, null, null) where metric = 'sex' and bucket = 'sin_dato'$q$, ORG_A), '>0');

        -- ----- Alta: obligatorio no resuelto → la base detiene
        perform pg_temp.expect('1b control positivo: el alta sin datos opcionales se abre y no inventa nada', INT, 'authenticated', new_case, '1');
        perform pg_temp.expect('1b: sin tipo de ventanilla no se abre el expediente → BV323', INT, 'authenticated',
            replace(new_case, '''fija''', 'null'), 'ERR:BV323');
        perform pg_temp.expect('1b: sin fecha de nacimiento no se abre el expediente → BV324', INT, 'authenticated',
            replace(new_case, 'date ''2000-01-01''', 'null::date'), 'ERR:BV324');
        perform pg_temp.expect('1b: un consentimiento sin estado ya no se guarda como concedido → BV322', INT, 'authenticated',
            replace(new_case, '"consent_type":"general_care","status":"granted"', '"consent_type":"general_care"'), 'ERR:BV322');
        perform pg_temp.expect('1b: un consentimiento con un estado inventado tampoco → BV322', INT, 'authenticated',
            replace(new_case, '"status":"granted"', '"status":"quizas"'), 'ERR:BV322');
        perform pg_temp.expect('1b: registrar un consentimiento sin indicar su estado → BV322', INT, 'authenticated',
            $q$select public.fn_register_consent('aaaaaaaa-4000-0000-0000-000000000001'::uuid, 'internal_sharing')::text$q$, 'ERR:BV322');

        -- ----- Alta: campos sensibles solo con consentimiento sensible
        perform pg_temp.expect('1b (D-14): sin consentimiento sensible no se acepta el sexo → BV402', INT, 'authenticated',
            replace(new_case, b6, 'false,1,null,null,null,null,null,''fija'''), 'ERR:BV402');
        perform pg_temp.expect('1b (D-14): sin consentimiento sensible no se acepta la nacionalidad → BV402', INT, 'authenticated',
            replace(new_case, b6, 'false,null,93,null,null,null,null,''fija'''), 'ERR:BV402');
        perform pg_temp.expect('1b (D-14): sin consentimiento sensible no se acepta el nombre de la nacionalidad → BV402', INT, 'authenticated',
            replace(new_case, b6, 'false,null,null,''Honduras'',null,null,null,''fija'''), 'ERR:BV402');
        perform pg_temp.expect('1b (D-14): sin consentimiento sensible no se acepta la lengua → BV402', INT, 'authenticated',
            replace(new_case, b6, 'false,null,null,null,''aaaaaaaa-c000-0000-0000-000000000011''::uuid,null,null,''fija'''), 'ERR:BV402');
        perform pg_temp.expect('1b (D-14): sin consentimiento sensible no se acepta el teléfono → BV402', INT, 'authenticated',
            replace(new_case, b6, 'false,null,null,null,null,null,''5512345678'',''fija'''), 'ERR:BV402');
        perform pg_temp.expect('1b (D-14) control positivo: con consentimiento sensible sí se aceptan sexo, nacionalidad, lengua y teléfono', INT, 'authenticated',
            replace(replace(new_case, b6, 'false,1,93,''Honduras'',''aaaaaaaa-c000-0000-0000-000000000011''::uuid,''Detalle del idioma'',''5512345678'',''fija'''), sens, sens_new), '1');
        perform pg_temp.expect('F4a control positivo: «la persona no quiso responder» en el idioma del alta no exige consentimiento sensible', INT, 'authenticated',
            replace(new_case, b6, 'false,null,null,null,''aaaaaaaa-c000-0000-0000-000000000013''::uuid,null,null,''fija'''), '1');
        perform pg_temp.expect('F4a: el alta con un valor de idioma de otro diccionario → BV220', INT, 'authenticated',
            replace(replace(new_case, b6, 'false,1,93,''Honduras'',''aaaaaaaa-c000-0000-0000-000000000001''::uuid,null,null,''fija'''), sens, sens_new), 'ERR:BV220');
        perform pg_temp.expect('F4a: el detalle del idioma sin valor del diccionario → BV333', INT, 'authenticated',
            replace(replace(new_case, b6, 'false,1,93,''Honduras'',null,''Solo detalle'',null,''fija'''), sens, sens_new), 'ERR:BV333');
        perform pg_temp.expect('1b (D-14): con el consentimiento sensible RETIRADO tampoco se aceptan → BV402', INT, 'authenticated',
            replace(replace(new_case, b6, 'false,1,null,null,null,null,null,''fija'''), sens,
                    '"consent_type":"general_care","status":"granted"},{"consent_type":"sensitive_data","status":"revoked"}]'), 'ERR:BV402');

        -- ----- Alta: contexto de ingreso real (catálogos oficiales y de la organización)
        perform pg_temp.expect('1b control positivo: estado, municipio, canal y vía válidos', INT, 'authenticated',
            replace(new_case, ctx, '''fija'',false,9,''09015'',1,3,null,'), '1');
        perform pg_temp.expect('1b: un estado que no existe → BV214', INT, 'authenticated',
            replace(new_case, ctx, '''fija'',false,99,null,null,null,null,'), 'ERR:BV214');
        perform pg_temp.expect('1b: un municipio que no existe → BV215', INT, 'authenticated',
            replace(new_case, ctx, '''fija'',false,null,''99999'',null,null,null,'), 'ERR:BV215');
        perform pg_temp.expect('1b: un municipio de otro estado → BV215', INT, 'authenticated',
            replace(new_case, ctx, '''fija'',false,9,''15015'',null,null,null,'), 'ERR:BV215');
        perform pg_temp.expect('1b: un canal que no existe en la organización → BV216', INT, 'authenticated',
            replace(new_case, ctx, '''fija'',false,null,null,99,null,null,'), 'ERR:BV216');
        perform pg_temp.expect('1b: una vía de ingreso que no existe en la organización → BV217', INT, 'authenticated',
            replace(new_case, ctx, '''fija'',false,null,null,null,99,null,'), 'ERR:BV217');
        perform pg_temp.expect('1b: el contexto de ingreso queda guardado tal como se capturó', null, null,
            $q$select count(*)::text from public."case" where intake_state_id = 9 and intake_municipality_key = '09015' and intake_channel_id = 1 and entry_route_id = 3$q$, '>0');

        -- ----- Rectificar: el valor sensible solo cambia con consentimiento sensible (y solo si CAMBIA)
        update public.person set sex_id = 2 where id = pg_temp.id('4000', 33)::uuid;
        perform pg_temp.expect('1b (D-14): rectificar sin tocar el sexo ya guardado no exige consentimiento nuevo', DIR, 'authenticated',
            format($q$select count(*)::text from (select public.fn_rectify_person(%L::uuid,'Lambda','SinSensible',null,null,date '1985-03-04',false,2,null,null,null,'Corrección de nombre')) x$q$, pg_temp.id('4000', 33)), '1');
        perform pg_temp.expect('1b (D-14): cambiar el sexo sin consentimiento sensible → BV402', DIR, 'authenticated',
            format($q$select count(*)::text from (select public.fn_rectify_person(%L::uuid,'Lambda','SinSensible',null,null,date '1985-03-04',false,1,null,null,null,'Cambio')) x$q$, pg_temp.id('4000', 33)), 'ERR:BV402');
        perform pg_temp.expect('1b (D-14): agregar un teléfono sin consentimiento sensible → BV402', DIR, 'authenticated',
            format($q$select count(*)::text from (select public.fn_rectify_person(%L::uuid,'Lambda','SinSensible',null,null,date '1985-03-04',false,2,null,'5512345678',null,'Teléfono')) x$q$, pg_temp.id('4000', 33)), 'ERR:BV402');
        perform pg_temp.expect('1b (D-14): agregar un correo sin consentimiento sensible → BV402', DIR, 'authenticated',
            format($q$select count(*)::text from (select public.fn_rectify_person(%L::uuid,'Lambda','SinSensible',null,null,date '1985-03-04',false,2,null,null,'a@b.invalid','Correo')) x$q$, pg_temp.id('4000', 33)), 'ERR:BV402');
        perform pg_temp.expect('1b (D-14): con el consentimiento sensible vigente sí se puede agregar el sexo', DIR, 'authenticated',
            format($q$select count(*)::text from (select public.fn_rectify_person(%L::uuid,'Kappa','Documentada',null,null,date '1985-03-04',false,2,null,'5512345678',null,'Datos que la persona dio')) x$q$, pg_temp.id('4000', 32)), '1');

        -- ----- Subfolio: sin supuestos y con el asentimiento que se capturó
        perform pg_temp.expect('1b control positivo: el subfolio sin datos opcionales se abre', INT, 'authenticated', subf, '1');
        perform pg_temp.expect('1b (D-14): el sexo del subfolio sin consentimiento sensible → BV402', INT, 'authenticated',
            replace(subf, 'false,null,null,null,null,null,', 'false,1,null,null,null,null,'), 'ERR:BV402');
        perform pg_temp.expect('1b: sin asentimiento de la niña o el niño no se abre el subfolio → BV403', INT, 'authenticated',
            replace(subf, '"is_minor_assent":true', '"is_minor_assent":false'), 'ERR:BV403');
        perform pg_temp.expect('1b: si no se indica el asentimiento tampoco se da por hecho → BV403', INT, 'authenticated',
            replace(subf, ',"is_minor_assent":true', ''), 'ERR:BV403');
        perform pg_temp.expect('1b: un consentimiento del subfolio sin estado → BV322', INT, 'authenticated',
            replace(subf, '"status":"granted",', ''), 'ERR:BV322');
        perform pg_temp.expect('1b: el asentimiento de cada consentimiento es el que se capturó (no se fuerza a «sí»)', INT, 'authenticated',
            replace(subf, '"is_minor_assent":true}]', '"is_minor_assent":true},{"consent_type":"secondary_use_research","status":"granted","is_minor_assent":false}]'), '1');
        perform pg_temp.expect('1b: el consentimiento sin asentimiento quedó registrado sin asentimiento', null, null,
            $q$select count(*)::text from public.consent where consent_type = 'secondary_use_research' and is_minor_assent = false
               and case_id in (select id from public."case" where parent_case_id = 'aaaaaaaa-5000-0000-0000-0000000000d1')$q$, '>0');

        -- ----- Catálogos: de la organización (los administran dirección y Trabajo Social) y oficiales (de nadie)
        perform pg_temp.expect('1b control positivo: Trabajo Social agrega un canal de procedencia', CW, 'authenticated',
            format($q$with i as (insert into public.intake_channel (organization_id, code, label_es) values (%L, 7, 'Canal nuevo') returning 1) select count(*)::text from i$q$, ORG_A), '1');
        perform pg_temp.expect('1b: el área jurídica no administra los canales', 'aaaaaaaa-3000-0000-0000-00000000000a', 'authenticated',
            format($q$with i as (insert into public.intake_channel (organization_id, code, label_es) values (%L, 8, 'Otro') returning 1) select count(*)::text from i$q$, ORG_A), 'ERR');
        perform pg_temp.expect('1b control positivo: dirección agrega una vía de ingreso', DIR, 'authenticated',
            format($q$with i as (insert into public.entry_route (organization_id, code, label_es) values (%L, 4, 'Vía nueva') returning 1) select count(*)::text from i$q$, ORG_A), '1');
        perform pg_temp.expect('1b: el rol de solo lectura no administra las vías', VW, 'authenticated',
            format($q$with i as (insert into public.entry_route (organization_id, code, label_es) values (%L, 5, 'Otra') returning 1) select count(*)::text from i$q$, ORG_A), 'ERR');
        perform pg_temp.expect('1b: no se borra un canal (se desactiva)', DIR, 'authenticated',
            $q$with d as (delete from public.intake_channel returning 1) select count(*)::text from d$q$, 'ERR');
        perform pg_temp.expect('1b: dirección de otra organización no ve los canales de A', DIRB2, 'authenticated',
            format('select count(*)::text from public.intake_channel where organization_id = %L', ORG_A), '0');
        perform pg_temp.expect('1b control positivo: dirección lee los 32 estados oficiales', DIR, 'authenticated',
            'select count(*)::text from public.geo_state', '32');
        perform pg_temp.expect('1b control positivo: dirección lee los municipios oficiales', DIR, 'authenticated',
            'select (count(*) > 2000)::text from public.geo_municipality', 'true');
        perform pg_temp.expect('1b: nadie edita los estados oficiales, ni dirección', DIR, 'authenticated',
            $q$with u as (update public.geo_state set name = 'X' returning 1) select count(*)::text from u$q$, 'ERR');
        perform pg_temp.expect('1b: nadie agrega municipios, ni dirección', DIR, 'authenticated',
            $q$with i as (insert into public.geo_municipality (cvegeo, cve_ent, cve_mun, name) values ('99999', '09', '999', 'X') returning 1) select count(*)::text from i$q$, 'ERR');
        perform pg_temp.expect('1b: sin rol vigente no se leen los municipios', NR, 'authenticated',
            'select count(*)::text from public.geo_municipality', '0');
        perform pg_temp.expect('1b: el catálogo oficial no se lee sin sesión', null, 'anon',
            'select count(*)::text from public.geo_state', 'ERR');
    end;

    -- ============================================================================================
    -- ===== E14 fase 2: las cuatro fechas del caso, con precisión flexible (día, mes o año)
    -- ===== (migración 20261016000001). Ingreso y egreso a la nación y al albergue; lo corregido se cierra con motivo.
    -- ============================================================================================
    declare
        c1 constant text := pg_temp.id('5000', 32);   -- TST-A-0E1, persona nacida el 1985-03-04
        sd text := $q$select count(*)::text from (select public.fn_set_case_date(%L::uuid, %L, %L::date, %L, %L)) x$q$;
        nc2 text := replace(new_case, '::jsonb)) x', '::jsonb, %L::jsonb)) x');
    begin
        perform pg_temp.expect('F2 control positivo: ingreso registra el ingreso a la nación con día exacto', INT, 'authenticated',
            format(sd, c1, 'nation_entry', '2026-03-15', 'day', null), '1');
        perform pg_temp.expect('F2 control positivo: Trabajo Social registra el ingreso al albergue solo con mes', CW, 'authenticated',
            format(sd, c1, 'shelter_entry', '2026-09-17', 'month', null), '1');
        perform pg_temp.expect('F2: con precisión de mes se guarda el primer día del mes', null, null,
            format($q$select value::text || '/' || precision from public.case_date where case_id = %L::uuid and kind = 'shelter_entry' and valid_to is null$q$, c1), '2026-09-01/month');
        perform pg_temp.expect('F2: con precisión de año se guarda el primero de enero', DIR, 'authenticated',
            format(sd, c1, 'nation_exit', '2026-11-30', 'year', null), '1');
        perform pg_temp.expect('F2: el año queda como 1 de enero con su precisión', null, null,
            format($q$select value::text || '/' || precision from public.case_date where case_id = %L::uuid and kind = 'nation_exit' and valid_to is null$q$, c1), '2026-01-01/year');

        -- ----- Roles y organización
        perform pg_temp.expect('F2: el rol de solo lectura no registra fechas → BV120', VW, 'authenticated',
            format(sd, c1, 'nation_entry', '2026-03-16', 'day', 'x'), 'ERR:BV120');
        perform pg_temp.expect('F2: el voluntariado no registra fechas → BV120', VOL, 'authenticated',
            format(sd, c1, 'nation_entry', '2026-03-16', 'day', 'x'), 'ERR:BV120');
        perform pg_temp.expect('F2: sin rol vigente no registra fechas → BV120', NR, 'authenticated',
            format(sd, c1, 'nation_entry', '2026-03-16', 'day', 'x'), 'ERR:BV120');
        perform pg_temp.expect('F2: anónimo no registra fechas', null, 'anon',
            format(sd, c1, 'nation_entry', '2026-03-16', 'day', 'x'), 'ERR');
        perform pg_temp.expect('F2: dirección de otra organización no ve el expediente → BV201', DIRB2, 'authenticated',
            format(sd, c1, 'nation_entry', '2026-03-16', 'day', 'x'), 'ERR:BV201');

        -- ----- Validaciones
        perform pg_temp.expect('F2: un tipo de fecha que no existe → BV325', DIR, 'authenticated',
            format(sd, c1, 'cumpleanos', '2026-03-16', 'day', null), 'ERR:BV325');
        perform pg_temp.expect('F2: una precisión que no existe → BV325', DIR, 'authenticated',
            format(sd, c1, 'nation_entry', '2026-03-16', 'semana', null), 'ERR:BV325');
        perform pg_temp.expect('F2: una fecha futura no se registra → BV326', DIR, 'authenticated',
            format(sd, c1, 'shelter_exit', (current_date + 10)::text, 'day', null), 'ERR:BV326');
        perform pg_temp.expect('F2: un ingreso anterior al nacimiento es imposible → BV327', DIR, 'authenticated',
            format(sd, c1, 'nation_entry', '1980-01-01', 'day', 'x'), 'ERR:BV327');
        perform pg_temp.expect('F2: con precisión de año el año de nacimiento sí cabe (puede ser después del nacimiento)', DIR, 'authenticated',
            format(sd, pg_temp.id('5000', 34), 'nation_entry', '1985-06-01', 'year', null), '1');
        perform pg_temp.expect('F2: un egreso del albergue anterior a su ingreso → BV327', DIR, 'authenticated',
            format(sd, c1, 'shelter_exit', '2026-08-01', 'day', null), 'ERR:BV327');
        perform pg_temp.expect('F2 control positivo: un egreso posterior al ingreso sí se registra', DIR, 'authenticated',
            format(sd, c1, 'shelter_exit', '2026-09-20', 'day', null), '1');
        perform pg_temp.expect('F2: un ingreso posterior al egreso ya registrado → BV327', DIR, 'authenticated',
            format(sd, c1, 'shelter_entry', '2026-10-05', 'day', 'x'), 'ERR:BV327');

        -- ----- Lo corregido se cierra con motivo; nada se borra
        perform pg_temp.expect('F2: cambiar una fecha ya registrada exige motivo → BV304', DIR, 'authenticated',
            format(sd, c1, 'nation_entry', '2026-03-14', 'day', null), 'ERR:BV304');
        perform pg_temp.expect('F2 control positivo: con motivo se corrige la fecha', DIR, 'authenticated',
            format(sd, c1, 'nation_entry', '2026-03-14', 'day', 'La persona recordó otra fecha'), '1');
        perform pg_temp.expect('F2: solo hay una fecha vigente de cada tipo', null, null,
            format($q$select count(*)::text from public.case_date where case_id = %L::uuid and kind = 'nation_entry' and valid_to is null$q$, c1), '1');
        perform pg_temp.expect('F2: la anterior quedó cerrada con su motivo (no se borró)', null, null,
            format($q$select count(*)::text from public.case_date where case_id = %L::uuid and kind = 'nation_entry' and valid_to is not null and change_reason = 'La persona recordó otra fecha'$q$, c1), '1');
        perform pg_temp.expect('F2: repetir la misma fecha y precisión no crea otro registro', DIR, 'authenticated',
            format(sd, c1, 'nation_entry', '2026-03-14', 'day', null), '1');
        perform pg_temp.expect('F2: siguen siendo 2 registros del tipo (uno cerrado y uno vigente)', null, null,
            format($q$select count(*)::text from public.case_date where case_id = %L::uuid and kind = 'nation_entry'$q$, c1), '2');
        perform pg_temp.expect('F2: quitar una fecha exige motivo → BV304', DIR, 'authenticated',
            format($q$select count(*)::text from (select public.fn_set_case_date(%L::uuid, 'nation_exit', null, null, null)) x$q$, c1), 'ERR:BV304');
        perform pg_temp.expect('F2 control positivo: con motivo se quita (se cierra) la fecha', DIR, 'authenticated',
            format($q$select count(*)::text from (select public.fn_set_case_date(%L::uuid, 'nation_exit', null, null, 'Se registró por error')) x$q$, c1), '1');
        perform pg_temp.expect('F2: quitada la fecha ya no hay vigente de ese tipo', null, null,
            format($q$select count(*)::text from public.case_date where case_id = %L::uuid and kind = 'nation_exit' and valid_to is null$q$, c1), '0');
        perform pg_temp.expect('F2: quitar una fecha que no existe no hace nada', DIR, 'authenticated',
            format($q$select count(*)::text from (select public.fn_set_case_date(%L::uuid, 'nation_exit', null, null, null)) x$q$, c1), '1');

        -- ----- Sin escritura directa y con visibilidad de roles operativos
        perform pg_temp.expect('F2: no se inserta una fecha por la API directa', DIR, 'authenticated',
            format($q$with i as (insert into public.case_date (organization_id, case_id, kind, value, precision, created_by) values (%L, %L::uuid, 'nation_entry', '2026-01-01', 'day', %L) returning 1) select count(*)::text from i$q$, ORG_A, c1, DIR), 'ERR');
        perform pg_temp.expect('F2: no se edita una fecha por la API directa', DIR, 'authenticated',
            $q$with u as (update public.case_date set value = '2000-01-01' returning 1) select count(*)::text from u$q$, 'ERR');
        perform pg_temp.expect('F2: no se borra una fecha por la API directa', DIR, 'authenticated',
            $q$with d as (delete from public.case_date returning 1) select count(*)::text from d$q$, 'ERR');
        perform pg_temp.expect('F2 control positivo: dirección ve las fechas de su organización', DIR, 'authenticated', 'select count(*)::text from public.case_date', '>0');
        perform pg_temp.expect('F2 control positivo: quien atiende las ve', CW, 'authenticated', 'select count(*)::text from public.case_date', '>0');
        perform pg_temp.expect('F2: el rol de solo lectura no ve fechas de casos', VW, 'authenticated', 'select count(*)::text from public.case_date', '0');
        perform pg_temp.expect('F2: sin rol no se ven fechas', NR, 'authenticated', 'select count(*)::text from public.case_date', '0');
        perform pg_temp.expect('F2: otra organización no ve las fechas de A', DIRB2, 'authenticated', 'select count(*)::text from public.case_date', '0');
        perform pg_temp.expect('F2: la auditoría deja eventos de las fechas', null, null,
            $q$select count(*)::text from public.audit_event where table_name = 'case_date' and created_at >= transaction_timestamp()$q$, '>0');
        perform pg_temp.expect('F2: la auditoría guarda nombres de campos, no los valores de las fechas', null, null,
            $q$select count(*)::text from public.audit_event where table_name = 'case_date' and created_at >= transaction_timestamp()
               and (coalesce(new_values::text, '') like '%2026-03-1%' or coalesce(new_values::text, '') like '%2026-09-%')$q$, '0');

        -- ----- Alta: las fechas viajan en la misma transacción
        perform pg_temp.expect('F2 control positivo: el alta registra el ingreso a la nación y al albergue', INT, 'authenticated',
            format(nc2, '[{"kind":"nation_entry","value":"2026-03-15","precision":"month"},{"kind":"shelter_entry","value":"2026-10-02","precision":"day"}]'), '1');
        perform pg_temp.expect('F2: las fechas del alta quedaron guardadas con su precisión', null, null,
            $q$select count(*)::text from public.case_date where kind = 'nation_entry' and value = '2026-03-01' and precision = 'month' and created_at >= transaction_timestamp()$q$, '>0');
        perform pg_temp.expect('F2: el alta con un tipo de fecha inválido no se abre → BV325', INT, 'authenticated',
            format(nc2, '[{"kind":"otro","value":"2026-03-15","precision":"day"}]'), 'ERR:BV325');
        perform pg_temp.expect('F2: el alta con una fecha futura no se abre → BV326', INT, 'authenticated',
            format(nc2, format('[{"kind":"shelter_entry","value":"%s","precision":"day"}]', current_date + 5)), 'ERR:BV326');
        perform pg_temp.expect('F2: las fechas del alta deben venir como arreglo → BV325', INT, 'authenticated',
            format(nc2, '{"kind":"nation_entry"}'), 'ERR:BV325');
        perform pg_temp.expect('F2: el alta con un egreso anterior al ingreso no se abre → BV327', INT, 'authenticated',
            format(nc2, '[{"kind":"shelter_entry","value":"2026-10-02","precision":"day"},{"kind":"shelter_exit","value":"2026-09-01","precision":"day"}]'), 'ERR:BV327');

        -- ----- Derecho de acceso y anonimización
        perform pg_temp.expect('F2: el extracto de acceso ARCO incluye las fechas de los casos', DIR, 'authenticated',
            format($q$select (jsonb_array_length(public.fn_generate_arco_access_extract(%L::uuid)->'dates') > 0)::text$q$, pg_temp.id('4000', 32)), 'true');
        perform pg_temp.expect('F2 prep: fecha del caso de la persona que se anonimiza', DIR, 'authenticated',
            format(sd, 'aaaaaaaa-5000-0000-0000-000000000001', 'shelter_entry', '2026-02-10', 'day', null), '1');
    end;

    -- ============================================================================================
    -- ===== E14 fase 2b: el egreso y el ingreso al albergue se capturan con el estatus de alojamiento
    -- ===== (migración 20261016000002). Opción A del Product Owner: el estatus manda y la fecha acompaña.
    -- ===== «Albergada» = ingreso; «Salida del albergue» = egreso. Reubicada, en tránsito y atención externa
    -- ===== son estatus fuera del albergue (la persona puede no haber ingresado nunca): no llevan fecha.
    -- ============================================================================================
    declare
        f1 constant text := pg_temp.id('5000', 40);   -- TST-A-0F1
        f2 constant text := pg_temp.id('5000', 41);   -- TST-A-0F2
        sh text := $q$select count(*)::text from (select public.fn_change_shelter_status(%L::uuid, %L, %L, %L::date, %L)) x$q$;
        cur text := $q$select sv.code from public.case_status cs join public.status_value sv on sv.id = cs.value_id
                       join public.status_axis ax on ax.id = cs.axis_id
                       where cs.case_id = %L::uuid and ax.code = 'shelter_status' and cs.valid_to is null$q$;
    begin
        -- Escenario: el eje de alojamiento y dos expedientes nuevos
        insert into public.status_axis (id, organization_id, code, label_es, is_primary, is_system, sort_order)
        values ('aaaaaaaa-2000-0000-0000-000000000003', ORG_A::uuid, 'shelter_status', 'Alojamiento', false, true, 3);
        insert into public.status_value (id, axis_id, organization_id, code, label_es, sort_order, is_system)
        select ('aaaaaaaa-2100-0000-0000-0000000000' || v.n)::uuid, 'aaaaaaaa-2000-0000-0000-000000000003', ORG_A::uuid, v.code, v.label, v.o, false
        from (values ('41', 'sheltered', 'Albergada', 2), ('42', 'left_shelter', 'Salida del albergue', 5), ('43', 'in_transit', 'En tránsito', 3),
                     ('44', 'relocated', 'Reubicada', 4), ('45', 'external', 'Atención externa', 1)) as v(n, code, label, o);
        insert into public.person (id, organization_id, given_name, paternal_family_name, birth_date) values
            (pg_temp.id('4000', 40)::uuid, ORG_A::uuid, 'Nu', 'Alojada', '1990-01-01'),
            (pg_temp.id('4000', 41)::uuid, ORG_A::uuid, 'Xi', 'EnTransito', '1990-01-01');
        insert into public."case" (id, organization_id, case_number, titular_person_id, opened_by, assigned_user_id, intake_window_type)
        select pg_temp.id('5000', 40 + k)::uuid, ORG_A::uuid, 'TST-A-0F' || (1 + k), pg_temp.id('4000', 40 + k)::uuid,
               'aaaaaaaa-3000-0000-0000-000000000003', 'aaaaaaaa-3000-0000-0000-000000000002', 'fija'
        from generate_series(0, 1) k;

        -- ----- Roles y organización
        perform pg_temp.expect('F2b: el rol de solo lectura no cambia el alojamiento → BV120', VW, 'authenticated',
            format(sh, f1, 'sheltered', 'Ingresó', '2026-10-01', 'day'), 'ERR:BV120');
        perform pg_temp.expect('F2b: el voluntariado no cambia el alojamiento → BV120', VOL, 'authenticated',
            format(sh, f1, 'sheltered', 'Ingresó', '2026-10-01', 'day'), 'ERR:BV120');
        perform pg_temp.expect('F2b: dirección de otra organización no ve el expediente → BV201', DIRB2, 'authenticated',
            format(sh, f1, 'sheltered', 'Ingresó', '2026-10-01', 'day'), 'ERR:BV201');
        perform pg_temp.expect('F2b: anónimo no cambia el alojamiento', null, 'anon',
            format(sh, f1, 'sheltered', 'Ingresó', '2026-10-01', 'day'), 'ERR');

        -- ----- El cambio genérico de estatus ya no sirve para ingreso y egreso: sin fecha no se puede
        perform pg_temp.expect('F2b: pasar a «albergada» sin fecha por el cambio genérico → BV328', DIR, 'authenticated',
            format($q$select count(*)::text from (select public.fn_change_case_status(%L::uuid, 'shelter_status', 'sheltered', 'x')) x$q$, f2), 'ERR:BV328');
        perform pg_temp.expect('F2b: pasar a «salida del albergue» sin fecha por el cambio genérico → BV328', DIR, 'authenticated',
            format($q$select count(*)::text from (select public.fn_change_case_status(%L::uuid, 'shelter_status', 'left_shelter', 'x')) x$q$, f2), 'ERR:BV328');
        perform pg_temp.expect('F2b control positivo: «en tránsito» sigue cambiando por el cambio genérico (no lleva fecha)', DIR, 'authenticated',
            format($q$select count(*)::text from (select public.fn_change_case_status(%L::uuid, 'shelter_status', 'in_transit', 'Pasa por la ciudad')) x$q$, f2), '1');
        perform pg_temp.expect('F2b control positivo: «reubicada» y «atención externa» tampoco llevan fecha', DIR, 'authenticated',
            format($q$select count(*)::text from (select public.fn_change_case_status(%L::uuid, 'shelter_status', 'relocated', 'x'), public.fn_change_case_status(%L::uuid, 'shelter_status', 'external', 'y')) x$q$, f2, f2), '1');
        perform pg_temp.expect('F2b: el cambio con fecha solo es para ingreso y egreso (otro estatus → BV329)', DIR, 'authenticated',
            format(sh, f2, 'in_transit', 'x', '2026-10-01', 'day'), 'ERR:BV329');

        -- ----- La fecha es obligatoria y se valida
        perform pg_temp.expect('F2b: sin fecha no se registra el ingreso al albergue → BV325', DIR, 'authenticated',
            format($q$select count(*)::text from (select public.fn_change_shelter_status(%L::uuid, 'sheltered', 'Ingresó', null, 'day')) x$q$, f1), 'ERR:BV325');
        perform pg_temp.expect('F2b: una fecha futura no se registra → BV326', DIR, 'authenticated',
            format(sh, f1, 'sheltered', 'Ingresó', (current_date + 3)::text, 'day'), 'ERR:BV326');
        perform pg_temp.expect('F2b: sin motivo no se cambia el alojamiento → BV305', DIR, 'authenticated',
            format(sh, f1, 'sheltered', '', '2026-10-01', 'day'), 'ERR:BV305');
        perform pg_temp.expect('F2b: tras los rechazos el alojamiento no cambió', null, null, format(cur, f1), 'NULL|');

        -- ----- Ingreso al albergue: estatus y fecha en una sola operación
        perform pg_temp.expect('F2b control positivo: ingreso al albergue con fecha exacta', INT, 'authenticated',
            format(sh, f1, 'sheltered', 'Ingresó al albergue', '2026-10-01', 'day'), '1');
        perform pg_temp.expect('F2b: el estatus quedó «albergada»', null, null, format(cur, f1), 'sheltered');
        perform pg_temp.expect('F2b: la fecha de ingreso al albergue quedó guardada con su precisión', null, null,
            format($q$select value::text || '/' || precision from public.case_date where case_id = %L::uuid and kind = 'shelter_entry' and valid_to is null$q$, f1), '2026-10-01/day');

        -- ----- Egreso: coherencia con el ingreso; si falla, el estatus no cambia
        perform pg_temp.expect('F2b: un egreso anterior al ingreso → BV327', DIR, 'authenticated',
            format(sh, f1, 'left_shelter', 'Salió', '2026-09-01', 'day'), 'ERR:BV327');
        perform pg_temp.expect('F2b: si la fecha no cuadra, el estatus tampoco cambió (una sola operación)', null, null, format(cur, f1), 'sheltered');
        perform pg_temp.expect('F2b control positivo: egreso con solo el mes', CW, 'authenticated',
            format(sh, f1, 'left_shelter', 'Salió del albergue', '2026-10-20', 'month'), '1');
        perform pg_temp.expect('F2b: el estatus quedó «salida del albergue»', null, null, format(cur, f1), 'left_shelter');
        perform pg_temp.expect('F2b: la fecha de egreso quedó con precisión de mes', null, null,
            format($q$select value::text || '/' || precision from public.case_date where case_id = %L::uuid and kind = 'shelter_exit' and valid_to is null$q$, f1), '2026-10-01/month');
        -- Reingreso en el mismo caso (con fechas exactas): el ingreso no puede ser posterior al egreso; se abre un caso nuevo vinculado
        perform pg_temp.expect('F2b: ingreso con fecha exacta en otro expediente', DIR, 'authenticated',
            format(sh, f2, 'sheltered', 'Ingresó', '2026-10-01', 'day'), '1');
        perform pg_temp.expect('F2b: egreso con fecha exacta en ese expediente', DIR, 'authenticated',
            format(sh, f2, 'left_shelter', 'Salió', '2026-10-05', 'day'), '1');
        perform pg_temp.expect('F2b: volver a ingresar en el mismo caso, después del egreso → BV327 (el reingreso es un caso nuevo vinculado)', DIR, 'authenticated',
            format(sh, f2, 'sheltered', 'Regresó', '2026-10-10', 'day'), 'ERR:BV327');
        perform pg_temp.expect('F2b: el alojamiento sigue en «salida del albergue» tras ese rechazo', null, null, format(cur, f2), 'left_shelter');
    end;

    -- ============================================================================================
    -- ===== E14 fase 3: unidad familiar paralela (migración 20261017000001)
    -- ===== Folio de familia del sistema de seguimiento paralelo (p. ej. REDODEM), tipo de familia (catálogo que editan
    -- ===== dirección y Trabajo Social, solo informativo) y consecutivo de la persona dentro de la familia. No toca el
    -- ===== folio de caso ni `parent_case_id`: el subfolio y la familia son cosas distintas.
    -- ============================================================================================
    declare
        g1 constant text := pg_temp.id('5000', 50);
        g2 constant text := pg_temp.id('5000', 51);
        g3 constant text := pg_temp.id('5000', 52);
        g4 constant text := pg_temp.id('5000', 53);
        mk text := $q$select count(*)::text from (select public.fn_create_family_unit(%L, %L::uuid)) x$q$;
        asg text := $q$select count(*)::text from (select public.fn_set_case_family(%L::uuid, %L::uuid, %s, %L)) x$q$;
        rm text := $q$select count(*)::text from (select public.fn_set_case_family(%L::uuid, null, null, %L)) x$q$;
        t_nuc text;   -- id del tipo «nuclear» de A
        t_b text;     -- id de un tipo de la organización B (dirección de A no lo ve por RLS: se pasa como literal)
        u1 text; u2 text; u_b text;
    begin
        -- Escenario: tipos de familia de A, personas y expedientes nuevos
        begin
            insert into public.family_type (organization_id, key, label_es, legacy_code, sort_order, is_active) values
                (ORG_A::uuid, 'nuclear', 'Familia nuclear', 'FAM-NUCL', 1, true),
                (ORG_A::uuid, 'single_parent', 'Familia monoparental', 'FAM-MNP', 2, true),
                (ORG_A::uuid, 'unaccompanied_minor', 'Niñez y adolescencia no acompañada', 'NNA NO ACOMPAÑADX', 4, true),
                (ORG_A::uuid, 'retired', 'Tipo retirado', null, 9, false);
            insert into public.family_type (organization_id, key, label_es, sort_order) values (ORG_B::uuid, 'nuclear', 'Familia nuclear B', 1);
        exception when others then
            raise notice 'F3 escenario: sin tabla family_type todavía (%).', sqlerrm;
        end;
        insert into public.person (id, organization_id, given_name, paternal_family_name, birth_date)
        select pg_temp.id('4000', 50 + k)::uuid, ORG_A::uuid, 'Familia' || k, 'Paralela', '1990-01-01' from generate_series(0, 3) k;
        insert into public."case" (id, organization_id, case_number, titular_person_id, opened_by, assigned_user_id, intake_window_type)
        select pg_temp.id('5000', 50 + k)::uuid, ORG_A::uuid, 'TST-A-0G' || (1 + k), pg_temp.id('4000', 50 + k)::uuid,
               'aaaaaaaa-3000-0000-0000-000000000003', 'aaaaaaaa-3000-0000-0000-000000000002', 'fija'
        from generate_series(0, 3) k;
        begin
            select id::text into t_nuc from public.family_type where organization_id = ORG_A::uuid and key = 'nuclear';
            select id::text into t_b from public.family_type where organization_id = ORG_B::uuid;
        exception when others then t_nuc := null; t_b := null;
        end;

        -- ----- Catálogo de tipos de familia: lo editan dirección y Trabajo Social
        perform pg_temp.expect('F3 control positivo: Trabajo Social agrega un tipo de familia', CW, 'authenticated',
            format($q$with i as (insert into public.family_type (organization_id, key, label_es, sort_order) values (%L, 'extended', 'Familia extensa', 6) returning 1) select count(*)::text from i$q$, ORG_A), '1');
        perform pg_temp.expect('F3 control positivo: dirección edita la etiqueta de un tipo', DIR, 'authenticated',
            $q$with u as (update public.family_type set label_es = 'Familia nuclear (editada)' where key = 'nuclear' and organization_id = 'aaaaaaaa-0000-0000-0000-00000000000a' returning 1) select count(*)::text from u$q$, '1');
        perform pg_temp.expect('F3: el área jurídica no administra los tipos de familia', 'aaaaaaaa-3000-0000-0000-00000000000a', 'authenticated',
            format($q$with i as (insert into public.family_type (organization_id, key, label_es, sort_order) values (%L, 'otro_tipo', 'Otro', 7) returning 1) select count(*)::text from i$q$, ORG_A), 'ERR');
        perform pg_temp.expect('F3: el rol de solo lectura no administra los tipos de familia', VW, 'authenticated',
            format($q$with i as (insert into public.family_type (organization_id, key, label_es, sort_order) values (%L, 'otro_tipo2', 'Otro', 7) returning 1) select count(*)::text from i$q$, ORG_A), 'ERR');
        perform pg_temp.expect('F3: no se agregan tipos a la organización B desde A', CW, 'authenticated',
            format($q$with i as (insert into public.family_type (organization_id, key, label_es, sort_order) values (%L, 'ajeno', 'Ajeno', 7) returning 1) select count(*)::text from i$q$, ORG_B), 'ERR');
        perform pg_temp.expect('F3: no se borra un tipo de familia (se desactiva)', DIR, 'authenticated',
            $q$with d as (delete from public.family_type returning 1) select count(*)::text from d$q$, 'ERR');
        perform pg_temp.expect('F3: sin rol vigente no se ven los tipos de familia', NR, 'authenticated', 'select count(*)::text from public.family_type', '0');
        perform pg_temp.expect('F3: otra organización no ve los tipos de A', DIRB2, 'authenticated',
            format('select count(*)::text from public.family_type where organization_id = %L', ORG_A), '0');

        -- ----- Crear la unidad familiar (el folio es del sistema paralelo: se captura, no se genera)
        perform pg_temp.expect('F3 control positivo: ingreso crea la familia con su folio y tipo', INT, 'authenticated', format(mk, 'FAM-0001', t_nuc), '1');
        perform pg_temp.expect('F3 control positivo: Trabajo Social crea una familia sin tipo (el tipo es opcional)', CW, 'authenticated', format(mk, 'FAM-0002', null), '1');
        perform pg_temp.expect('F3: el rol de solo lectura no crea familias → BV120', VW, 'authenticated', format(mk, 'FAM-9', null), 'ERR:BV120');
        perform pg_temp.expect('F3: el voluntariado no crea familias → BV120', VOL, 'authenticated', format(mk, 'FAM-9', null), 'ERR:BV120');
        perform pg_temp.expect('F3: sin rol vigente no crea familias → BV120', NR, 'authenticated', format(mk, 'FAM-9', null), 'ERR:BV120');
        perform pg_temp.expect('F3: anónimo no crea familias', null, 'anon', format(mk, 'FAM-9', null), 'ERR');
        perform pg_temp.expect('F3: el folio de familia no se repite en la organización → BV330', DIR, 'authenticated', format(mk, 'FAM-0001', null), 'ERR:BV330');
        perform pg_temp.expect('F3: ni con otra capitalización o espacios → BV330', DIR, 'authenticated', format(mk, '  fam-0001 ', null), 'ERR:BV330');
        perform pg_temp.expect('F3: el folio de familia no puede ir vacío → BV320', DIR, 'authenticated', format(mk, '   ', null), 'ERR:BV320');
        perform pg_temp.expect('F3: el folio de familia no puede ser larguísimo → BV321', DIR, 'authenticated', format(mk, repeat('9', 61), null), 'ERR:BV321');
        perform pg_temp.expect('F3: un tipo de familia inexistente → BV218', DIR, 'authenticated', format(mk, 'FAM-0010', 'aaaaaaaa-f000-0000-0000-0000000000ff'), 'ERR:BV218');
        perform pg_temp.expect('F3: un tipo de familia retirado → BV218', DIR, 'authenticated',
            format($q$select count(*)::text from (select public.fn_create_family_unit('FAM-0011', (select id from public.family_type where key = 'retired' and organization_id = %L))) x$q$, ORG_A), 'ERR:BV218');
        perform pg_temp.expect('F3: un tipo de familia de otra organización → BV218', DIR, 'authenticated', format(mk, 'FAM-0012', t_b), 'ERR:BV218');
        perform pg_temp.expect('F3: el mismo folio sí puede existir en otra organización', DIRB2, 'authenticated', format(mk, 'FAM-0001', null), '1');
        begin
            select id::text into u1 from public.family_unit where organization_id = ORG_A::uuid and family_number = 'FAM-0001';
            select id::text into u2 from public.family_unit where organization_id = ORG_A::uuid and family_number = 'FAM-0002';
            select id::text into u_b from public.family_unit where organization_id = ORG_B::uuid and family_number = 'FAM-0001';
        exception when others then
            raise notice 'F3: sin tabla family_unit todavía (%).', sqlerrm;
        end;

        -- ----- Asignar personas a la familia (cada una con su expediente) y su consecutivo
        perform pg_temp.expect('F3 control positivo: ingreso asigna a la primera persona (consecutivo 1)', INT, 'authenticated', format(asg, g1, u1, '1', null), '1');
        perform pg_temp.expect('F3 control positivo: Trabajo Social asigna a la segunda (consecutivo 2)', CW, 'authenticated', format(asg, g2, u1, '2', null), '1');
        perform pg_temp.expect('F3: el consecutivo es opcional (la tercera persona entra sin él)', DIR, 'authenticated', format(asg, g3, u1, 'null', null), '1');
        perform pg_temp.expect('F3: tres personas vigentes en la familia', null, null,
            format($q$select count(*)::text from public.family_member where family_unit_id = %L::uuid and valid_to is null$q$, u1), '3');
        perform pg_temp.expect('F3: el rol de solo lectura no asigna familias → BV120', VW, 'authenticated', format(asg, g4, u1, '4', null), 'ERR:BV120');
        perform pg_temp.expect('F3: el voluntariado no asigna familias → BV120', VOL, 'authenticated', format(asg, g4, u1, '4', null), 'ERR:BV120');
        perform pg_temp.expect('F3: otra organización no ve el expediente → BV201', DIRB2, 'authenticated', format(asg, g4, u_b, '4', null), 'ERR:BV201');
        perform pg_temp.expect('F3: una familia de otra organización no se usa → BV219', DIR, 'authenticated', format(asg, g4, u_b, '4', null), 'ERR:BV219');
        perform pg_temp.expect('F3: una familia que no existe → BV219', DIR, 'authenticated', format(asg, g4, 'aaaaaaaa-f000-0000-0000-0000000000fe', '4', null), 'ERR:BV219');
        perform pg_temp.expect('F3: el consecutivo debe ser un número positivo → BV331', DIR, 'authenticated', format(asg, g4, u1, '0', null), 'ERR:BV331');
        perform pg_temp.expect('F3: ni negativo → BV331', DIR, 'authenticated', format(asg, g4, u1, '-2', null), 'ERR:BV331');

        -- ----- Lo corregido se cierra con motivo; nada se borra
        perform pg_temp.expect('F3: mover a otra familia exige motivo → BV304', DIR, 'authenticated', format(asg, g1, u2, '1', null), 'ERR:BV304');
        perform pg_temp.expect('F3 control positivo: con motivo se mueve a otra familia', DIR, 'authenticated', format(asg, g1, u2, '1', 'Estaba mal agrupada'), '1');
        perform pg_temp.expect('F3: la pertenencia anterior quedó cerrada con su motivo (no se borró)', null, null,
            format($q$select count(*)::text from public.family_member where case_id = %L::uuid and valid_to is not null and change_reason = 'Estaba mal agrupada'$q$, g1), '1');
        perform pg_temp.expect('F3: solo hay una pertenencia vigente por persona', null, null,
            format($q$select count(*)::text from public.family_member where case_id = %L::uuid and valid_to is null$q$, g1), '1');
        perform pg_temp.expect('F3: repetir la misma familia y consecutivo no crea otro registro', DIR, 'authenticated', format(asg, g1, u2, '1', null), '1');
        perform pg_temp.expect('F3: siguen siendo 2 registros de esa persona (uno cerrado y uno vigente)', null, null,
            format($q$select count(*)::text from public.family_member where case_id = %L::uuid$q$, g1), '2');
        perform pg_temp.expect('F3: cambiar solo el consecutivo también exige motivo → BV304', DIR, 'authenticated', format(asg, g1, u2, '3', null), 'ERR:BV304');
        perform pg_temp.expect('F3 control positivo: con motivo se corrige el consecutivo', DIR, 'authenticated', format(asg, g1, u2, '3', 'El orden era otro'), '1');
        perform pg_temp.expect('F3: quitar a la persona de la familia exige motivo → BV304', DIR, 'authenticated', format(rm, g1, null), 'ERR:BV304');
        perform pg_temp.expect('F3 control positivo: con motivo se quita (se cierra) la pertenencia', DIR, 'authenticated', format(rm, g1, 'Dejó de pertenecer a esa familia'), '1');
        perform pg_temp.expect('F3: quitada la persona ya no tiene familia vigente', null, null,
            format($q$select count(*)::text from public.family_member where case_id = %L::uuid and valid_to is null$q$, g1), '0');
        perform pg_temp.expect('F3: quitar a quien no tiene familia no hace nada', DIR, 'authenticated', format(rm, g1, null), '1');

        -- ----- Crear la familia y asignar en un solo paso
        perform pg_temp.expect('F3 control positivo: crear la familia y asignar a la persona en un solo paso', INT, 'authenticated',
            format($q$select count(*)::text from (select public.fn_set_case_family(%L::uuid, null, 1, null, 'FAM-0003', %L::uuid)) x$q$, g4, t_nuc), '1');
        perform pg_temp.expect('F3: la familia nueva quedó con su folio, su tipo y la persona', null, null,
            format($q$select count(*)::text from public.family_member m join public.family_unit f on f.id = m.family_unit_id
                      where m.case_id = %L::uuid and m.valid_to is null and f.family_number = 'FAM-0003' and f.family_type_id = %L::uuid$q$, g4, t_nuc), '1');
        perform pg_temp.expect('F3: crear una familia con un folio que ya existe → BV330', DIR, 'authenticated',
            format($q$select count(*)::text from (select public.fn_set_case_family(%L::uuid, null, 1, null, 'FAM-0003', null)) x$q$, g1), 'ERR:BV330');
        perform pg_temp.expect('F3: indicar una familia existente y el folio de una nueva a la vez → BV332', DIR, 'authenticated',
            format($q$select count(*)::text from (select public.fn_set_case_family(%L::uuid, %L::uuid, 1, null, 'FAM-0099', null)) x$q$, g1, u1), 'ERR:BV332');
        perform pg_temp.expect('F3: si la asignación falla, la familia nueva tampoco se crea (una sola operación)', null, null,
            $q$select count(*)::text from public.family_unit where family_number = 'FAM-0099'$q$, '0');

        -- ----- El tipo de familia es informativo: no se contradice con el marcador porque ni se compara
        perform pg_temp.expect('F3: poner «niñez no acompañada» a una familia cuyos miembros no tienen ese marcador es válido (solo informa)', INT, 'authenticated',
            format($q$select count(*)::text from (select public.fn_set_family_type(%L::uuid, (select id from public.family_type where key = 'unaccompanied_minor' and organization_id = %L), null)) x$q$, u2, ORG_A), '1');
        perform pg_temp.expect('F3: cambiar el tipo ya puesto exige motivo → BV304', DIR, 'authenticated',
            format($q$select count(*)::text from (select public.fn_set_family_type(%L::uuid, %L::uuid, null)) x$q$, u2, t_nuc), 'ERR:BV304');
        perform pg_temp.expect('F3 control positivo: con motivo se cambia el tipo', DIR, 'authenticated',
            format($q$select count(*)::text from (select public.fn_set_family_type(%L::uuid, %L::uuid, 'Se aclaró la composición')) x$q$, u2, t_nuc), '1');
        perform pg_temp.expect('F3: el rol de solo lectura no cambia el tipo → BV120', VW, 'authenticated',
            format($q$select count(*)::text from (select public.fn_set_family_type(%L::uuid, %L::uuid, 'x')) x$q$, u2, t_nuc), 'ERR:BV120');
        perform pg_temp.expect('F3: un tipo inexistente al cambiar → BV218', DIR, 'authenticated',
            format($q$select count(*)::text from (select public.fn_set_family_type(%L::uuid, 'aaaaaaaa-f000-0000-0000-0000000000ff'::uuid, 'x')) x$q$, u2), 'ERR:BV218');

        -- ----- Sin escritura directa, con visibilidad de roles operativos y auditoría sin valores
        perform pg_temp.expect('F3: no se inserta una familia por la API directa', DIR, 'authenticated',
            format($q$with i as (insert into public.family_unit (organization_id, family_number, created_by) values (%L, 'DIRECTA-1', %L) returning 1) select count(*)::text from i$q$, ORG_A, DIR), 'ERR');
        perform pg_temp.expect('F3: no se edita una familia por la API directa', DIR, 'authenticated',
            $q$with u as (update public.family_unit set family_number = 'EDITADA' returning 1) select count(*)::text from u$q$, 'ERR');
        perform pg_temp.expect('F3: no se inserta una pertenencia por la API directa', DIR, 'authenticated',
            format($q$with i as (insert into public.family_member (organization_id, family_unit_id, case_id, created_by) values (%L, %L::uuid, %L::uuid, %L) returning 1) select count(*)::text from i$q$, ORG_A, u1, g4, DIR), 'ERR');
        perform pg_temp.expect('F3: no se borra una pertenencia por la API directa', DIR, 'authenticated',
            $q$with d as (delete from public.family_member returning 1) select count(*)::text from d$q$, 'ERR');
        perform pg_temp.expect('F3 control positivo: dirección ve las familias de su organización', DIR, 'authenticated', 'select count(*)::text from public.family_unit', '>0');
        perform pg_temp.expect('F3 control positivo: quien atiende ve las pertenencias', CW, 'authenticated', 'select count(*)::text from public.family_member', '>0');
        perform pg_temp.expect('F3: el rol de solo lectura no ve familias', VW, 'authenticated', 'select count(*)::text from public.family_unit', '0');
        perform pg_temp.expect('F3: sin rol no se ven pertenencias', NR, 'authenticated', 'select count(*)::text from public.family_member', '0');
        perform pg_temp.expect('F3: otra organización no ve las familias de A', DIRB2, 'authenticated',
            format('select count(*)::text from public.family_unit where organization_id = %L', ORG_A), '0');
        perform pg_temp.expect('F3: la auditoría deja eventos de las familias y las pertenencias', null, null,
            $q$select count(*)::text from public.audit_event where table_name in ('family_unit', 'family_member') and created_at >= transaction_timestamp()$q$, '>0');
        perform pg_temp.expect('F3: la auditoría guarda nombres de campos, no el folio de la familia', null, null,
            $q$select count(*)::text from public.audit_event where table_name in ('family_unit', 'family_member') and created_at >= transaction_timestamp()
               and (coalesce(new_values::text, '') like '%FAM-000%')$q$, '0');

        -- ----- Derecho de acceso y anonimización
        perform pg_temp.expect('F3: el extracto de acceso ARCO incluye la familia de la persona', DIR, 'authenticated',
            format($q$select (jsonb_array_length(public.fn_generate_arco_access_extract(%L::uuid)->'family') > 0)::text$q$, pg_temp.id('4000', 51)), 'true');
        perform pg_temp.expect('F3 prep: la persona que se anonimiza pertenece a una familia', DIR, 'authenticated',
            format(asg, 'aaaaaaaa-5000-0000-0000-000000000001', u1, '5', null), '1');
    end;

    -- ============================================================================================
    -- ===== E14 fase 4b: necesidades específicas (casillas) y plan al ingreso (migración 20261019000001)
    -- ===== Las necesidades son una lista de casillas de un diccionario editable por dirección y Trabajo Social; son datos
    -- ===== sensibles (D-14) salvo «La persona no quiso responder». El plan al ingreso usa los valores del eje jurídico.
    -- ============================================================================================
    declare
        c_ok constant text := pg_temp.id('5000', 32);   -- con consentimiento sensible vigente
        c_no constant text := pg_temp.id('5000', 33);   -- sin consentimiento sensible
        c_rv constant text := pg_temp.id('5000', 34);   -- consentimiento sensible revocado
        n_dis constant text := 'aaaaaaaa-c000-0000-0000-000000000021';
        n_pre constant text := 'aaaaaaaa-c000-0000-0000-000000000022';
        n_nr  constant text := 'aaaaaaaa-c000-0000-0000-000000000023';
        n_old constant text := 'aaaaaaaa-c000-0000-0000-000000000024';
        n_b   constant text := 'bbbbbbbb-c000-0000-0000-000000000002';
        setn text := $q$select count(*)::text from (select public.fn_set_case_needs(%L::uuid, %L::uuid[], %L)) x$q$;
        setp text := $q$select count(*)::text from (select public.fn_set_case_intake_plan(%L::uuid, %L::uuid, %L)) x$q$;
        cur text := $q$select count(*)::text from public.case_need where case_id = %L::uuid and valid_to is null$q$;
    begin
        begin
            insert into public.catalog_item (id, organization_id, catalog, key, label_es, is_active, is_system, sort_order) values
                (n_dis::uuid, ORG_A::uuid, 'specific_need', 'disability', 'Discapacidad (prueba)', true, false, 1),
                (n_pre::uuid, ORG_A::uuid, 'specific_need', 'pregnancy', 'Embarazo (prueba)', true, false, 2),
                (n_nr::uuid, ORG_A::uuid, 'specific_need', 'no_response', 'La persona no quiso responder', true, true, 99),
                (n_old::uuid, ORG_A::uuid, 'specific_need', 'retired', 'Valor retirado', false, false, 5),
                (n_b::uuid, ORG_B::uuid, 'specific_need', 'disability', 'Discapacidad B', true, false, 1);
        exception when others then
            raise notice 'F4b escenario: sin el diccionario de necesidades todavía (%).', sqlerrm;
        end;
        -- Un segundo valor del eje jurídico de A (el escenario trae «sin determinar» y «solicitante de asilo»)
        insert into public.status_value (id, axis_id, organization_id, code, label_es, sort_order, is_system)
        values ('aaaaaaaa-2100-0000-0000-000000000033', 'aaaaaaaa-2000-0000-0000-000000000001', ORG_A::uuid, 'permanent_resident', 'Residente permanente', 3, false);

        -- ----- Necesidades específicas: casillas del diccionario
        perform pg_temp.expect('F4b control positivo: quien atiende marca dos necesidades (con consentimiento sensible)', CW, 'authenticated',
            format(setn, c_ok, format('{%s,%s}', n_dis, n_pre), null), '1');
        perform pg_temp.expect('F4b: quedaron dos necesidades vigentes', null, null, format(cur, c_ok), '2');
        perform pg_temp.expect('F4b: el rol de solo lectura no marca necesidades → BV120', VW, 'authenticated',
            format(setn, c_ok, format('{%s}', n_dis), null), 'ERR:BV120');
        perform pg_temp.expect('F4b: el voluntariado no marca necesidades → BV120', VOL, 'authenticated',
            format(setn, c_ok, format('{%s}', n_dis), null), 'ERR:BV120');
        perform pg_temp.expect('F4b: otra organización no ve el expediente → BV201', DIRB2, 'authenticated',
            format(setn, c_ok, format('{%s}', n_b), null), 'ERR:BV201');
        perform pg_temp.expect('F4b: sin consentimiento sensible no se marca una necesidad → BV408', CW, 'authenticated',
            format(setn, c_no, format('{%s}', n_dis), null), 'ERR:BV408');
        perform pg_temp.expect('F4b control positivo: «la persona no quiso responder» sin consentimiento sensible (no es un dato)', CW, 'authenticated',
            format(setn, c_no, format('{%s}', n_nr), null), '1');
        perform pg_temp.expect('F4b: con el consentimiento sensible revocado tampoco → BV408', CW, 'authenticated',
            format(setn, c_rv, format('{%s}', n_pre), null), 'ERR:BV408');
        perform pg_temp.expect('F4b: un valor de otra organización no se usa → BV220', DIR, 'authenticated',
            format(setn, c_ok, format('{%s}', n_b), 'x'), 'ERR:BV220');
        perform pg_temp.expect('F4b: un valor retirado del diccionario no se usa → BV220', DIR, 'authenticated',
            format(setn, c_ok, format('{%s}', n_old), 'x'), 'ERR:BV220');
        perform pg_temp.expect('F4b: un valor de otro diccionario (religión) no vale como necesidad → BV220', DIR, 'authenticated',
            format(setn, c_ok, '{aaaaaaaa-c000-0000-0000-000000000001}', 'x'), 'ERR:BV220');
        perform pg_temp.expect('F4b: «no quiso responder» no se combina con otras necesidades → BV334', DIR, 'authenticated',
            format(setn, c_ok, format('{%s,%s}', n_dis, n_nr), 'x'), 'ERR:BV334');
        perform pg_temp.expect('F4b: quitar una necesidad ya marcada exige motivo → BV304', CW, 'authenticated',
            format(setn, c_ok, format('{%s}', n_dis), null), 'ERR:BV304');
        perform pg_temp.expect('F4b control positivo: con motivo se quita (se cierra) una necesidad', CW, 'authenticated',
            format(setn, c_ok, format('{%s}', n_dis), 'Ya no aplica'), '1');
        perform pg_temp.expect('F4b: queda una necesidad vigente', null, null, format(cur, c_ok), '1');
        perform pg_temp.expect('F4b: la que se quitó no se borró: quedó cerrada con su motivo', null, null,
            format($q$select count(*)::text from public.case_need where case_id = %L::uuid and valid_to is not null and change_reason = 'Ya no aplica'$q$, c_ok), '1');
        perform pg_temp.expect('F4b: repetir las mismas necesidades no crea registros nuevos', CW, 'authenticated',
            format(setn, c_ok, format('{%s}', n_dis), null), '1');
        perform pg_temp.expect('F4b: siguen siendo dos registros en total (uno vigente y uno cerrado) más el de la primera marca', null, null,
            format($q$select count(*)::text from public.case_need where case_id = %L::uuid$q$, c_ok), '2');
        perform pg_temp.expect('F4b: agregar necesidades no exige motivo (solo quitarlas)', CW, 'authenticated',
            format(setn, c_ok, format('{%s,%s}', n_dis, n_pre), null), '1');
        perform pg_temp.expect('F4b: quitar todas exige motivo → BV304', DIR, 'authenticated',
            format(setn, c_ok, '{}', null), 'ERR:BV304');
        perform pg_temp.expect('F4b control positivo: con motivo se quitan todas', DIR, 'authenticated',
            format(setn, c_ok, '{}', 'Se registraron por error'), '1');
        perform pg_temp.expect('F4b: no queda ninguna vigente', null, null, format(cur, c_ok), '0');
        perform pg_temp.expect('F4b: no se inserta una necesidad por la API directa', DIR, 'authenticated',
            format($q$with i as (insert into public.case_need (organization_id, case_id, catalog_item_id, created_by) values (%L, %L::uuid, %L::uuid, %L) returning 1) select count(*)::text from i$q$, ORG_A, c_ok, n_dis, DIR), 'ERR');
        perform pg_temp.expect('F4b: no se edita una necesidad por la API directa', DIR, 'authenticated',
            $q$with u as (update public.case_need set valid_to = null returning 1) select count(*)::text from u$q$, 'ERR');
        perform pg_temp.expect('F4b: no se borra una necesidad por la API directa', DIR, 'authenticated',
            $q$with d as (delete from public.case_need returning 1) select count(*)::text from d$q$, 'ERR');
        perform pg_temp.expect('F4b control positivo: quien atiende ve las necesidades', CW, 'authenticated', 'select (count(*) > 0)::text from public.case_need', 'true');
        perform pg_temp.expect('F4b: el rol de solo lectura no ve necesidades de los casos', VW, 'authenticated', 'select count(*)::text from public.case_need', '0');
        perform pg_temp.expect('F4b: sin rol no se ven necesidades', NR, 'authenticated', 'select count(*)::text from public.case_need', '0');
        perform pg_temp.expect('F4b: otra organización no ve las necesidades de A', DIRB2, 'authenticated', 'select count(*)::text from public.case_need', '0');
        perform pg_temp.expect('F4b: la auditoría de las necesidades guarda nombres de campos, no el texto de lo marcado', null, null,
            $q$select count(*)::text from public.audit_event where table_name = 'case_need' and created_at >= transaction_timestamp()
               and (coalesce(new_values::text, '') ilike '%Discapacidad%' or coalesce(new_values::text, '') ilike '%Embarazo%')$q$, '0');
        perform pg_temp.expect('F4b: la auditoría deja eventos de las necesidades', null, null,
            $q$select (count(*) > 0)::text from public.audit_event where table_name = 'case_need' and created_at >= transaction_timestamp()$q$, 'true');
        perform pg_temp.expect('F4b prep: necesidades de la persona que se anonimiza y del extracto', DIR, 'authenticated',
            format(setn, c_ok, format('{%s}', n_pre), null), '1');
        perform pg_temp.expect('F4b: el extracto de acceso ARCO incluye las necesidades específicas', DIR, 'authenticated',
            format($q$select (jsonb_array_length(public.fn_generate_arco_access_extract(%L::uuid)->'specific_needs') > 0)::text$q$, pg_temp.id('4000', 32)), 'true');
        perform pg_temp.expect('F4b prep: una necesidad en el expediente de la persona que se anonimiza', DIR, 'authenticated',
            format(setn, 'aaaaaaaa-5000-0000-0000-000000000001', format('{%s}', n_dis), null), '1');

        -- ----- Plan al ingreso: un valor del eje jurídico
        perform pg_temp.expect('F4b control positivo: ingreso registra el plan al ingreso', INT, 'authenticated',
            format(setp, c_ok, 'aaaaaaaa-2100-0000-0000-000000000032', null), '1');
        perform pg_temp.expect('F4b: el plan al ingreso quedó guardado', null, null,
            format('select intake_plan_value_id::text from public."case" where id = %L::uuid', c_ok), 'aaaaaaaa-2100-0000-0000-000000000032');
        perform pg_temp.expect('F4b: el rol de solo lectura no registra el plan al ingreso → BV120', VW, 'authenticated',
            format(setp, c_ok, 'aaaaaaaa-2100-0000-0000-000000000033', 'x'), 'ERR:BV120');
        perform pg_temp.expect('F4b: otra organización no ve el expediente → BV201', DIRB2, 'authenticated',
            format(setp, c_ok, 'bbbbbbbb-2100-0000-0000-000000000001', 'x'), 'ERR:BV201');
        perform pg_temp.expect('F4b: un valor de otro eje no vale como plan al ingreso → BV220', DIR, 'authenticated',
            format(setp, c_ok, 'aaaaaaaa-2100-0000-0000-000000000011', 'x'), 'ERR:BV220');
        perform pg_temp.expect('F4b: un valor de otra organización no vale como plan al ingreso → BV220', DIR, 'authenticated',
            format(setp, c_ok, 'bbbbbbbb-2100-0000-0000-000000000001', 'x'), 'ERR:BV220');
        perform pg_temp.expect('F4b: cambiar el plan ya registrado exige motivo → BV304', INT, 'authenticated',
            format(setp, c_ok, 'aaaaaaaa-2100-0000-0000-000000000033', null), 'ERR:BV304');
        perform pg_temp.expect('F4b control positivo: con motivo se cambia el plan al ingreso', INT, 'authenticated',
            format(setp, c_ok, 'aaaaaaaa-2100-0000-0000-000000000033', 'La persona precisó su plan'), '1');
        perform pg_temp.expect('F4b: repetir el mismo plan no hace nada ni pide motivo', INT, 'authenticated',
            format(setp, c_ok, 'aaaaaaaa-2100-0000-0000-000000000033', null), '1');
        perform pg_temp.expect('F4b: quitar el plan ya registrado exige motivo → BV304', INT, 'authenticated',
            format($q$select count(*)::text from (select public.fn_set_case_intake_plan(%L::uuid, null, null)) x$q$, c_ok), 'ERR:BV304');
        perform pg_temp.expect('F4b control positivo: con motivo se quita el plan', INT, 'authenticated',
            format($q$select count(*)::text from (select public.fn_set_case_intake_plan(%L::uuid, null, 'Se capturó por error')) x$q$, c_ok), '1');
        perform pg_temp.expect('F4b: el plan no se escribe por la API directa', INT, 'authenticated',
            format($q$with u as (update public."case" set intake_plan_value_id = 'aaaaaaaa-2100-0000-0000-000000000032' where id = %L::uuid returning 1) select count(*)::text from u$q$, c_ok), 'ERR');
        perform pg_temp.expect('F4b: el cambio del plan deja su motivo en la auditoría', null, null,
            $q$select (count(*) > 0)::text from public.audit_event where action = 'RECTIFICATION' and table_name = 'case' and new_values ? 'reason'
               and new_values->>'reason' = 'La persona precisó su plan' and created_at >= transaction_timestamp()$q$, 'true');
    end;

    -- ============================================================================================
    -- ===== E14 fase 4: bitácora por área (migración 20261020000001)
    -- ===== Tipos de entrada nuevos (diagnóstico, ruta integral, reunión de casos, llamada de atención), línea de servicio
    -- ===== (diccionario editable) y procedencia de lo importado. La bitácora sigue siendo inmutable.
    -- ============================================================================================
    declare
        c_a constant text := 'aaaaaaaa-5000-0000-0000-000000000001';
        ar_ts constant text := 'aaaaaaaa-1000-0000-0000-000000000001';
        ar_lg constant text := 'aaaaaaaa-1000-0000-0000-000000000002';
        s_hosp constant text := 'aaaaaaaa-c000-0000-0000-000000000041';
        s_psy  constant text := 'aaaaaaaa-c000-0000-0000-000000000042';
        s_old  constant text := 'aaaaaaaa-c000-0000-0000-000000000043';
        s_b    constant text := 'bbbbbbbb-c000-0000-0000-000000000004';
        mk text := $q$select count(*)::text from (select public.fn_create_journal_entry(%L::uuid, %L, 'texto de prueba', now(), false, %L::uuid, %L::uuid)) x$q$;
    begin
        begin
            insert into public.catalog_item (id, organization_id, catalog, key, label_es, is_active, is_system, sort_order) values
                (s_hosp::uuid, ORG_A::uuid, 'service_line', 'hospitality', 'Hospitalidad (prueba)', true, false, 1),
                (s_psy::uuid, ORG_A::uuid, 'service_line', 'psychology', 'Psicología (prueba)', true, false, 2),
                (s_old::uuid, ORG_A::uuid, 'service_line', 'retired', 'Línea retirada', false, false, 3),
                (s_b::uuid, ORG_B::uuid, 'service_line', 'hospitality', 'Hospitalidad B', true, false, 1);
        exception when others then
            raise notice 'F4 escenario: sin el diccionario de líneas de servicio todavía (%).', sqlerrm;
        end;

        -- ----- Tipos nuevos
        perform pg_temp.expect('F4 control positivo: quien atiende asienta un diagnóstico de Trabajo Social', CW, 'authenticated',
            format(mk, c_a, 'diagnosis', ar_ts, null), '1');
        perform pg_temp.expect('F4: ruta integral de atención es un tipo válido', CW, 'authenticated',
            format(mk, c_a, 'integral_route', ar_ts, null), '1');
        perform pg_temp.expect('F4: reunión de casos es un tipo válido', CW, 'authenticated',
            format(mk, c_a, 'case_meeting', ar_ts, null), '1');
        perform pg_temp.expect('F4: llamada de atención es un tipo válido', CW, 'authenticated',
            format(mk, c_a, 'warning', ar_ts, null), '1');
        perform pg_temp.expect('F4: un tipo que no existe se rechaza', CW, 'authenticated',
            format(mk, c_a, 'inventado', ar_ts, null), 'ERR');
        perform pg_temp.expect('F4: el rol de solo lectura no asienta → BV101', VW, 'authenticated',
            format(mk, c_a, 'diagnosis', ar_ts, null), 'ERR:BV101');
        perform pg_temp.expect('F4: escribir a nombre de otra área sigue vedado → BV117', CW, 'authenticated',
            format(mk, c_a, 'diagnosis', ar_lg, null), 'ERR:BV117');

        -- ----- Línea de servicio (la «columna» de la hoja)
        perform pg_temp.expect('F4 control positivo: se asienta con su línea de servicio', CW, 'authenticated',
            format(mk, c_a, 'follow_up', ar_ts, s_hosp), '1');
        perform pg_temp.expect('F4: la línea queda en la entrada', null, null,
            format($q$select count(*)::text from public.journal_entry where case_id = %L::uuid and service_line_item_id = %L::uuid$q$, c_a, s_hosp), '1');
        perform pg_temp.expect('F4: sin línea la entrada nace sin línea (no se supone una)', null, null,
            format($q$select (count(*) > 0)::text from public.journal_entry where case_id = %L::uuid and entry_type_key = 'diagnosis' and service_line_item_id is null$q$, c_a), 'true');
        perform pg_temp.expect('F4: una línea de otra organización no se usa → BV220', CW, 'authenticated',
            format(mk, c_a, 'follow_up', ar_ts, s_b), 'ERR:BV220');
        perform pg_temp.expect('F4: una línea retirada no se usa → BV220', CW, 'authenticated',
            format(mk, c_a, 'follow_up', ar_ts, s_old), 'ERR:BV220');
        perform pg_temp.expect('F4: un valor de otro diccionario no vale como línea → BV220', CW, 'authenticated',
            format(mk, c_a, 'follow_up', ar_ts, 'aaaaaaaa-c000-0000-0000-000000000001'), 'ERR:BV220');
        perform pg_temp.expect('F4: la línea de servicio queda en la auditoría', null, null,
            format($q$select (count(*) > 0)::text from public.audit_event where table_name = 'journal_entry' and action = 'INSERT'
               and new_values->>'service_line_item_id' = %L and created_at >= transaction_timestamp()$q$, s_hosp), 'true');

        -- ----- Procedencia: lo que se escribe aquí es «app»; lo importado queda marcado y con su autoría original
        perform pg_temp.expect('F4: lo asentado desde el sistema nace con procedencia «app»', null, null,
            format($q$select count(*)::text from public.journal_entry where case_id = %L::uuid and source <> 'app'$q$, c_a), '0');
        perform pg_temp.expect('F4: una entrada importada exige la autoría original', null, null,
            format($q$insert into public.journal_entry (organization_id, case_id, area_id, author_user_id, entry_type_key, body, source)
               values (%L::uuid, %L::uuid, %L::uuid, %L::uuid, 'note', 'importada', 'import')$q$, ORG_A, c_a, ar_ts, CW), 'ERR');
        perform pg_temp.expect('F4 control positivo: una entrada importada con su autoría original', null, null,
            format($q$with i as (insert into public.journal_entry (id, organization_id, case_id, area_id, author_user_id, entry_type_key, body, source, source_author_label)
               values ('aaaaaaaa-6000-0000-0000-0000000000f4', %L::uuid, %L::uuid, %L::uuid, %L::uuid, 'note', 'importada', 'import', 'T.S. Lucía (hoja de casos)') returning 1) select count(*)::text from i$q$,
               ORG_A, c_a, ar_ts, CW), '1');
        perform pg_temp.expect('F4: una entrada «app» no lleva autoría ajena', null, null,
            format($q$insert into public.journal_entry (organization_id, case_id, area_id, author_user_id, entry_type_key, body, source_author_label)
               values (%L::uuid, %L::uuid, %L::uuid, %L::uuid, 'note', 'x', 'alguien')$q$, ORG_A, c_a, ar_ts, CW), 'ERR');
        perform pg_temp.expect('F4: la procedencia no se edita → BV611', null, null,
            $q$update public.journal_entry set source = 'app', source_author_label = null where id = 'aaaaaaaa-6000-0000-0000-0000000000f4'$q$, 'ERR:BV611');
        perform pg_temp.expect('F4: la línea de servicio no se edita → BV611', null, null,
            format($q$update public.journal_entry set service_line_item_id = %L::uuid where case_id = %L::uuid and service_line_item_id is not null$q$, s_psy, c_a), 'ERR:BV611');
        perform pg_temp.expect('F4: la procedencia tampoco se cambia por la API directa', CW, 'authenticated',
            $q$with u as (update public.journal_entry set source = 'app' where id = 'aaaaaaaa-6000-0000-0000-0000000000f4' returning 1) select count(*)::text from u$q$, 'ERR|0');
        perform pg_temp.expect('F4: la entrada importada se lee como cualquiera de su área', CW, 'authenticated',
            $q$select count(*)::text from public.journal_entry where id = 'aaaaaaaa-6000-0000-0000-0000000000f4'$q$, '1');
        perform pg_temp.expect('F4: la entrada importada de otra organización no se ve', DIRB2, 'authenticated',
            $q$select count(*)::text from public.journal_entry where id = 'aaaaaaaa-6000-0000-0000-0000000000f4'$q$, '0');
    end;

    -- ============================================================================================
    -- ===== E14 fase 5: grupos por edad configurables (migración 20261021000001)
    -- ===== El grupo por edad se calcula SOLO por edad (sin sexo, D-14). Las bandas las editan dirección y Trabajo Social
    -- ===== (`can_manage_catalogs()`); cambiarlas cierra las anteriores con motivo, nada se borra. Los indicadores las usan.
    -- ============================================================================================
    declare
        CW_LG constant text := 'aaaaaaaa-3000-0000-0000-00000000000a';  -- caseworker del área jurídica (no administra diccionarios)
        three text := '[{"label":"Niñez","min_age":0},{"label":"Adolescencia","min_age":12},{"label":"Adultez","min_age":18}]';
        setb text := $q$select count(*)::text from (select public.fn_set_age_bands(%L::jsonb, %L)) x$q$;
        cur text := $q$select count(*)::text from public.age_band where organization_id = %L::uuid and valid_to is null$q$;
    begin
        perform pg_temp.expect('F5 control positivo: dirección define los grupos por edad', DIR, 'authenticated',
            format(setb, three, null), '1');
        perform pg_temp.expect('F5: quedaron tres grupos vigentes', null, null, format(cur, ORG_A), '3');
        perform pg_temp.expect('F5: Trabajo Social también los edita (con motivo, porque ya hay)', CW, 'authenticated',
            format(setb, '[{"label":"Niñez","min_age":0},{"label":"Personas adultas","min_age":18}]', 'Se simplifican los grupos'), '1');
        perform pg_temp.expect('F5: el reemplazo deja solo los dos grupos nuevos vigentes', null, null, format(cur, ORG_A), '2');
        perform pg_temp.expect('F5: lo anterior se cerró, no se borró (3 grupos cerrados con motivo)', null, null,
            format($q$select count(*)::text from public.age_band where organization_id = %L::uuid and valid_to is not null and change_reason = 'Se simplifican los grupos'$q$, ORG_A), '3');
        perform pg_temp.expect('F5: cambiar sin motivo no se puede → BV304', DIR, 'authenticated',
            format(setb, three, null), 'ERR:BV304');
        perform pg_temp.expect('F5: el área jurídica no administra los grupos → BV335', CW_LG, 'authenticated',
            format(setb, three, 'x'), 'ERR:BV335');
        perform pg_temp.expect('F5: el rol de solo lectura no los edita → BV335', VW, 'authenticated',
            format(setb, three, 'x'), 'ERR:BV335');
        perform pg_temp.expect('F5: el voluntariado no los edita → BV335', VOL, 'authenticated',
            format(setb, three, 'x'), 'ERR:BV335');
        perform pg_temp.expect('F5: el primer grupo debe empezar en 0 años → BV336', DIR, 'authenticated',
            format(setb, '[{"label":"Niñez","min_age":3}]', 'x'), 'ERR:BV336');
        perform pg_temp.expect('F5: las edades deben ir de menor a mayor, sin repetirse → BV336', DIR, 'authenticated',
            format(setb, '[{"label":"A","min_age":0},{"label":"B","min_age":18},{"label":"C","min_age":12}]', 'x'), 'ERR:BV336');
        perform pg_temp.expect('F5: dos grupos no empiezan en la misma edad → BV336', DIR, 'authenticated',
            format(setb, '[{"label":"A","min_age":0},{"label":"B","min_age":0}]', 'x'), 'ERR:BV336');
        perform pg_temp.expect('F5: el nombre del grupo es obligatorio → BV336', DIR, 'authenticated',
            format(setb, '[{"label":"  ","min_age":0}]', 'x'), 'ERR:BV336');
        perform pg_temp.expect('F5: los nombres no se repiten → BV336', DIR, 'authenticated',
            format(setb, '[{"label":"A","min_age":0},{"label":"a","min_age":18}]', 'x'), 'ERR:BV336');
        perform pg_temp.expect('F5: sin ningún grupo no se puede → BV336', DIR, 'authenticated',
            format(setb, '[]', 'x'), 'ERR:BV336');
        perform pg_temp.expect('F5: lo que no es una lista no se acepta → BV336', DIR, 'authenticated',
            format(setb, '{"label":"A"}', 'x'), 'ERR:BV336');
        perform pg_temp.expect('F5: los intentos rechazados no cambiaron nada (siguen los dos grupos)', null, null, format(cur, ORG_A), '2');
        perform pg_temp.expect('F5: los grupos no se escriben por la API directa', CW, 'authenticated',
            format($q$with i as (insert into public.age_band (organization_id, label_es, min_age, sort_order, created_by) values (%L::uuid, 'Directo', 99, 9, %L::uuid) returning 1) select count(*)::text from i$q$, ORG_A, CW), 'ERR');
        perform pg_temp.expect('F5: ni se borran por la API directa', DIR, 'authenticated',
            $q$with d as (delete from public.age_band returning 1) select count(*)::text from d$q$, 'ERR');
        perform pg_temp.expect('F5: otra organización no ve los grupos de A', DIRB2, 'authenticated', 'select count(*)::text from public.age_band', '0');
        perform pg_temp.expect('F5: el personal de A los lee (lo necesita la pantalla del caso)', VW, 'authenticated',
            'select (count(*) > 0)::text from public.age_band', 'true');
        perform pg_temp.expect('F5: el cambio de grupos queda en la auditoría', null, null,
            $q$select (count(*) > 0)::text from public.audit_event where table_name = 'age_band' and created_at >= transaction_timestamp()$q$, 'true');

        -- Indicadores: usan los grupos configurados, no rangos fijos
        perform pg_temp.expect('F5: los indicadores agrupan por los grupos configurados', null, null,
            format($q$select (count(*) > 0)::text from public.fn_metric_rows(%L::uuid, null, null) where metric = 'age_band' and bucket in ('Niñez', 'Personas adultas')$q$, ORG_A), 'true');
        perform pg_temp.expect('F5: ya no salen los rangos fijos de antes', null, null,
            format($q$select count(*)::text from public.fn_metric_rows(%L::uuid, null, null) where metric = 'age_band' and bucket in ('0-11', '12-17', '18-29', '30-44', '45+')$q$, ORG_A), '0');
        perform pg_temp.expect('F5 (preparación): se quitan los grupos de A solo dentro de la transacción de prueba', null, null,
            format($q$with d as (delete from public.age_band where organization_id = %L::uuid returning 1) select (count(*) > 0)::text from d$q$, ORG_A), 'true');
        perform pg_temp.expect('F5: sin grupos configurados el indicador dice «sin dato» (no se supone ninguno)', null, null,
            format($q$select (count(*) > 0)::text from public.fn_metric_rows(%L::uuid, null, null) where metric = 'age_band' and bucket = 'sin_dato'$q$, ORG_A), 'true');
    end;

    -- ============================================================================================
    -- ===== E15 fase 1: ficha de la persona completa (migración 20261022000001)
    -- ===== Nivel de estudios, estado civil, ocupación en su lugar de origen y departamento de origen ya no son solo una
    -- ===== columna: son valores de diccionarios editables, se capturan en el alta y se corrigen con motivo. El departamento
    -- ===== depende de la nacionalidad (que es dato sensible) y se trata como sensible. Más el número de referencia (folio manual).
    -- ============================================================================================
    declare
        P_OK constant text := pg_temp.id('4000', 32);   -- con consentimiento sensible vigente
        P_NO constant text := pg_temp.id('4000', 33);   -- sin consentimiento sensible
        C_OK constant text := pg_temp.id('5000', 32);
        C_NO constant text := pg_temp.id('5000', 33);
        AR_TS constant text := 'aaaaaaaa-1000-0000-0000-000000000001';
        e_pri constant text := 'aaaaaaaa-c000-0000-0000-000000000051';
        e_uni constant text := 'aaaaaaaa-c000-0000-0000-000000000052';
        e_old constant text := 'aaaaaaaa-c000-0000-0000-000000000053';
        m_sol constant text := 'aaaaaaaa-c000-0000-0000-000000000054';
        o_com constant text := 'aaaaaaaa-c000-0000-0000-000000000055';
        o_est constant text := 'aaaaaaaa-c000-0000-0000-000000000056';
        o_hog constant text := 'aaaaaaaa-c000-0000-0000-000000000057';
        o_ser constant text := 'aaaaaaaa-c000-0000-0000-000000000058';
        o_nr  constant text := 'aaaaaaaa-c000-0000-0000-000000000059';
        d_hn  constant text := 'aaaaaaaa-c000-0000-0000-00000000005a';
        d_gt  constant text := 'aaaaaaaa-c000-0000-0000-00000000005b';
        d_nr  constant text := 'aaaaaaaa-c000-0000-0000-00000000005c';
        e_b   constant text := 'bbbbbbbb-c000-0000-0000-000000000005';
        setp text := $q$select count(*)::text from (select public.fn_set_person_profile_item(%L::uuid, %L, %L::uuid, %L)) x$q$;
        seto text := $q$select count(*)::text from (select public.fn_set_person_occupations(%L::uuid, %L::uuid[], %L)) x$q$;
        setr text := $q$select count(*)::text from (select public.fn_set_case_reference_number(%L::uuid, %L, %L)) x$q$;
        alta text := $q$select count(*)::text from (select public.fn_create_case_with_person(
            'Nueva','Ficha',null,null,date '2000-01-01',false,%s,%s,%L,null,null,null,'fija',false,null,null,null,null,null,
            'aaaaaaaa-1000-0000-0000-000000000001'::uuid, array[]::text[], %L::jsonb, %s)) x$q$;
        cons_gen text := '[{"consent_type":"general_care","status":"granted"}]';
        cons_sens text := '[{"consent_type":"general_care","status":"granted"},{"consent_type":"sensitive_data","status":"granted"}]';
    begin
        begin
            insert into public.catalog_item (id, organization_id, catalog, key, label_es, is_active, is_system, sort_order, country_id) values
                (e_pri::uuid, ORG_A::uuid, 'education_level', 'primary', 'Primaria (prueba)', true, false, 2, null),
                (e_uni::uuid, ORG_A::uuid, 'education_level', 'university', 'Universidad (prueba)', true, false, 5, null),
                (e_old::uuid, ORG_A::uuid, 'education_level', 'retired', 'Nivel retirado', false, false, 9, null),
                (m_sol::uuid, ORG_A::uuid, 'marital_status', 'single', 'Soltero (prueba)', true, false, 4, null),
                (o_com::uuid, ORG_A::uuid, 'occupation', 'commerce', 'Comercio (prueba)', true, false, 1, null),
                (o_est::uuid, ORG_A::uuid, 'occupation', 'student', 'Estudiante (prueba)', true, false, 3, null),
                (o_hog::uuid, ORG_A::uuid, 'occupation', 'household', 'Trabajo del hogar (prueba)', true, false, 7, null),
                (o_ser::uuid, ORG_A::uuid, 'occupation', 'services', 'Servicios (prueba)', true, false, 6, null),
                (o_nr::uuid, ORG_A::uuid, 'occupation', 'no_response', 'La persona no quiso responder', true, true, 99, null),
                (d_hn::uuid, ORG_A::uuid, 'department', 'hn_cortes', 'Cortés (prueba)', true, false, 1, 93),
                (d_gt::uuid, ORG_A::uuid, 'department', 'gt_peten', 'Petén (prueba)', true, false, 1, 86),
                (d_nr::uuid, ORG_A::uuid, 'department', 'no_response', 'La persona no quiso responder', true, true, 99, null),
                (e_b::uuid, ORG_B::uuid, 'education_level', 'primary', 'Primaria B', true, false, 2, null);
        exception when others then
            raise notice 'E15 escenario: sin los diccionarios de la ficha todavía (%).', sqlerrm;
        end;
        update public.person set nationality_country_id = 93 where id = P_OK::uuid;

        -- ----- Nivel de estudios y estado civil (diccionario; no son datos sensibles)
        perform pg_temp.expect('E15 control positivo: quien atiende registra el nivel de estudios', CW, 'authenticated',
            format(setp, P_NO, 'education_level', e_pri, null), '1');
        perform pg_temp.expect('E15: quedó guardado', null, null,
            format($q$select count(*)::text from public.person where id = %L::uuid and education_level_item_id = %L::uuid$q$, P_NO, e_pri), '1');
        perform pg_temp.expect('E15: cambiarlo sin motivo no se puede → BV304', CW, 'authenticated',
            format(setp, P_NO, 'education_level', e_uni, null), 'ERR:BV304');
        perform pg_temp.expect('E15 control positivo: con motivo se cambia', CW, 'authenticated',
            format(setp, P_NO, 'education_level', e_uni, 'La persona lo precisó'), '1');
        perform pg_temp.expect('E15: el cambio deja su motivo en la auditoría', null, null,
            $q$select (count(*) > 0)::text from public.audit_event where action = 'RECTIFICATION' and table_name = 'person'
               and new_values->>'reason' = 'La persona lo precisó' and created_at >= transaction_timestamp()$q$, 'true');
        perform pg_temp.expect('E15 control positivo: estado civil', CW, 'authenticated',
            format(setp, P_NO, 'marital_status', m_sol, null), '1');
        perform pg_temp.expect('E15: el rol de solo lectura no escribe → BV120', VW, 'authenticated',
            format(setp, P_NO, 'education_level', e_pri, 'x'), 'ERR:BV120');
        perform pg_temp.expect('E15: el voluntariado no escribe → BV120', VOL, 'authenticated',
            format(setp, P_NO, 'education_level', e_pri, 'x'), 'ERR:BV120');
        perform pg_temp.expect('E15: otra organización no ve a la persona → BV201', DIRB2, 'authenticated',
            format(setp, P_NO, 'education_level', e_b, 'x'), 'ERR:BV201');
        perform pg_temp.expect('E15: un valor de otra organización no se usa → BV220', DIR, 'authenticated',
            format(setp, P_NO, 'education_level', e_b, 'x'), 'ERR:BV220');
        perform pg_temp.expect('E15: un valor retirado no se usa → BV220', DIR, 'authenticated',
            format(setp, P_NO, 'education_level', e_old, 'x'), 'ERR:BV220');
        perform pg_temp.expect('E15: un valor de otro diccionario no vale → BV220', DIR, 'authenticated',
            format(setp, P_NO, 'education_level', m_sol, 'x'), 'ERR:BV220');
        perform pg_temp.expect('E15: un campo que no existe se rechaza → BV220', DIR, 'authenticated',
            format(setp, P_NO, 'religion', e_pri, 'x'), 'ERR:BV220');
        perform pg_temp.expect('E15: se puede quitar con motivo', DIR, 'authenticated',
            format(setp, P_NO, 'marital_status', null, 'Se capturó por error'), '1');

        -- ----- Departamento de origen: depende de la nacionalidad, que es dato sensible
        perform pg_temp.expect('E15 control positivo: departamento del país de la persona, con consentimiento sensible', CW, 'authenticated',
            format(setp, P_OK, 'origin_department', d_hn, null), '1');
        perform pg_temp.expect('E15: un departamento de otro país no corresponde → BV337', CW, 'authenticated',
            format(setp, P_OK, 'origin_department', d_gt, 'x'), 'ERR:BV337');
        perform pg_temp.expect('E15: sin nacionalidad registrada no hay departamento → BV337', CW, 'authenticated',
            format(setp, P_NO, 'origin_department', d_hn, null), 'ERR:BV337');
        perform pg_temp.expect('E15: «no quiso responder» vale sin nacionalidad ni consentimiento sensible', CW, 'authenticated',
            format(setp, P_NO, 'origin_department', d_nr, null), '1');
        perform pg_temp.expect('E15 prep: la persona sin consentimiento sensible ya tiene nacionalidad', null, null,
            format($q$with u as (update public.person set nationality_country_id = 93 where id = %L::uuid returning 1) select count(*)::text from u$q$, P_NO), '1');
        perform pg_temp.expect('E15: sin consentimiento sensible vigente no se registra un departamento → BV408', CW, 'authenticated',
            format(setp, P_NO, 'origin_department', d_hn, null), 'ERR:BV408');

        -- ----- Ocupación en su lugar de origen: hasta 3 opciones, o «no quiso responder» solo
        perform pg_temp.expect('E15 control positivo: dos ocupaciones', CW, 'authenticated',
            format(seto, P_NO, format('{%s,%s}', o_com, o_est), null), '1');
        perform pg_temp.expect('E15: quedaron dos vigentes', null, null,
            format($q$select count(*)::text from public.person_occupation where person_id = %L::uuid and valid_to is null$q$, P_NO), '2');
        perform pg_temp.expect('E15: más de tres no se admiten → BV338', CW, 'authenticated',
            format(seto, P_NO, format('{%s,%s,%s,%s}', o_com, o_est, o_hog, o_ser), 'x'), 'ERR:BV338');
        perform pg_temp.expect('E15: «no quiso responder» no se combina → BV338', CW, 'authenticated',
            format(seto, P_NO, format('{%s,%s}', o_com, o_nr), 'x'), 'ERR:BV338');
        perform pg_temp.expect('E15: quitar una ocupación sin motivo no se puede → BV304', CW, 'authenticated',
            format(seto, P_NO, format('{%s}', o_com), null), 'ERR:BV304');
        perform pg_temp.expect('E15: con motivo se quita; lo quitado se cierra, no se borra', CW, 'authenticated',
            format(seto, P_NO, format('{%s}', o_com), 'Corrección de la persona'), '1');
        perform pg_temp.expect('E15: una vigente y una cerrada con su motivo', null, null,
            format($q$select count(*) filter (where valid_to is null)::text || '/' || count(*) filter (where valid_to is not null and change_reason = 'Corrección de la persona')::text
               from public.person_occupation where person_id = %L::uuid$q$, P_NO), '1/1');
        perform pg_temp.expect('E15: una ocupación de otro diccionario no vale → BV220', CW, 'authenticated',
            format(seto, P_NO, format('{%s}', e_pri), 'x'), 'ERR:BV220');
        perform pg_temp.expect('E15: el rol de solo lectura no marca ocupaciones → BV120', VW, 'authenticated',
            format(seto, P_NO, format('{%s}', o_com), 'x'), 'ERR:BV120');
        perform pg_temp.expect('E15: las ocupaciones no se escriben por la API directa', CW, 'authenticated',
            format($q$with i as (insert into public.person_occupation (organization_id, person_id, catalog_item_id, created_by) values (%L::uuid, %L::uuid, %L::uuid, %L::uuid) returning 1) select count(*)::text from i$q$, ORG_A, P_NO, o_hog, CW), 'ERR');
        perform pg_temp.expect('E15: ni se borran por la API directa', DIR, 'authenticated',
            $q$with d as (delete from public.person_occupation returning 1) select count(*)::text from d$q$, 'ERR');
        perform pg_temp.expect('E15: otra organización no ve las ocupaciones de A', DIRB2, 'authenticated', 'select count(*)::text from public.person_occupation', '0');
        perform pg_temp.expect('E15: la auditoría de las ocupaciones deja eventos sin el texto del valor', null, null,
            $q$select ((count(*) > 0) and not bool_or(coalesce(new_values::text, '') ilike '%Comercio%'))::text from public.audit_event
               where table_name = 'person_occupation' and created_at >= transaction_timestamp()$q$, 'true');

        -- ----- Número de referencia (folio manual, texto corto)
        perform pg_temp.expect('E15 control positivo: se registra el número de referencia', CW, 'authenticated',
            format(setr, C_NO, 'REF-0001', null), '1');
        perform pg_temp.expect('E15: cambiarlo sin motivo no se puede → BV304', CW, 'authenticated',
            format(setr, C_NO, 'REF-0002', null), 'ERR:BV304');
        perform pg_temp.expect('E15: con motivo se cambia', CW, 'authenticated',
            format(setr, C_NO, 'REF-0002', 'Se corrigió el folio'), '1');
        perform pg_temp.expect('E15: un texto demasiado largo → BV321', CW, 'authenticated',
            format(setr, C_NO, repeat('x', 121), 'x'), 'ERR:BV321');
        perform pg_temp.expect('E15: el rol de solo lectura no lo escribe → BV120', VW, 'authenticated',
            format(setr, C_NO, 'REF-9', null), 'ERR:BV120');
        perform pg_temp.expect('E15: no se escribe por la API directa', CW, 'authenticated',
            format($q$with u as (update public."case" set reference_number = 'DIRECTO' where id = %L::uuid returning 1) select count(*)::text from u$q$, C_NO), 'ERR');

        -- ----- Diccionarios nuevos: dirección y Trabajo Social los editan; el departamento lleva su país
        perform pg_temp.expect('E15 control positivo: Trabajo Social agrega un nivel de estudios', CW, 'authenticated',
            format($q$with i as (insert into public.catalog_item (organization_id, catalog, key, label_es, sort_order) values (%L::uuid, 'education_level', 'tecnico', 'Técnico', 3) returning 1) select count(*)::text from i$q$, ORG_A), '1');
        perform pg_temp.expect('E15 control positivo: agrega un departamento con su país', CW, 'authenticated',
            format($q$with i as (insert into public.catalog_item (organization_id, catalog, key, label_es, sort_order, country_id) values (%L::uuid, 'department', 'hn_olancho', 'Olancho', 2, 93) returning 1) select count(*)::text from i$q$, ORG_A), '1');
        perform pg_temp.expect('E15: un departamento sin país no se acepta', CW, 'authenticated',
            format($q$with i as (insert into public.catalog_item (organization_id, catalog, key, label_es, sort_order) values (%L::uuid, 'department', 'sin_pais', 'Sin país', 3) returning 1) select count(*)::text from i$q$, ORG_A), 'ERR');
        perform pg_temp.expect('E15: un valor que no es departamento no lleva país', CW, 'authenticated',
            format($q$with i as (insert into public.catalog_item (organization_id, catalog, key, label_es, sort_order, country_id) values (%L::uuid, 'occupation', 'con_pais', 'Con país', 3, 93) returning 1) select count(*)::text from i$q$, ORG_A), 'ERR');
        perform pg_temp.expect('E15: el área jurídica no edita estos diccionarios', 'aaaaaaaa-3000-0000-0000-00000000000a', 'authenticated',
            format($q$with i as (insert into public.catalog_item (organization_id, catalog, key, label_es, sort_order) values (%L::uuid, 'marital_status', 'otro_estado', 'Otro estado', 7) returning 1) select count(*)::text from i$q$, ORG_A), 'ERR');

        -- ----- Alta: la ocupación es obligatoria (con «no quiso responder» como salida) cuando el diccionario tiene opciones
        perform pg_temp.expect('E15 control positivo: el alta con una ocupación y su nivel de estudios', INT, 'authenticated',
            format(alta, 'null', 'null', null::text, cons_gen,
                   format('p_education_level_item_id => %L::uuid, p_marital_status_item_id => %L::uuid, p_occupation_item_ids => array[%L]::uuid[]', e_pri, m_sol, o_com)), '1');
        perform pg_temp.expect('E15: el alta sin ocupación no se hace → BV339', INT, 'authenticated',
            format(alta, 'null', 'null', null::text, cons_gen, 'p_education_level_item_id => null'), 'ERR:BV339');
        perform pg_temp.expect('E15: el alta con «no quiso responder» como ocupación sí se hace', INT, 'authenticated',
            format(alta, 'null', 'null', null::text, cons_gen, format('p_occupation_item_ids => array[%L]::uuid[]', o_nr)), '1');
        perform pg_temp.expect('E15: el alta con más de tres ocupaciones → BV338', INT, 'authenticated',
            format(alta, 'null', 'null', null::text, cons_gen, format('p_occupation_item_ids => array[%L,%L,%L,%L]::uuid[]', o_com, o_est, o_hog, o_ser)), 'ERR:BV338');
        perform pg_temp.expect('E15: el alta con un nivel de estudios de otra organización → BV220', INT, 'authenticated',
            format(alta, 'null', 'null', null::text, cons_gen, format('p_education_level_item_id => %L::uuid, p_occupation_item_ids => array[%L]::uuid[]', e_b, o_nr)), 'ERR:BV220');
        perform pg_temp.expect('E15: el alta con departamento y sin consentimiento sensible → BV402', INT, 'authenticated',
            format(alta, 'null', 'null', null::text, cons_gen, format('p_origin_department_item_id => %L::uuid, p_occupation_item_ids => array[%L]::uuid[]', d_hn, o_nr)), 'ERR:BV402');
        perform pg_temp.expect('E15: el alta con «no quiso responder» como departamento no exige consentimiento sensible', INT, 'authenticated',
            format(alta, 'null', 'null', null::text, cons_gen, format('p_origin_department_item_id => %L::uuid, p_occupation_item_ids => array[%L]::uuid[]', d_nr, o_nr)), '1');
        perform pg_temp.expect('E15: el alta con departamento de otro país → BV337', INT, 'authenticated',
            format(alta, '1', '93', 'Honduras', cons_sens, format('p_origin_department_item_id => %L::uuid, p_occupation_item_ids => array[%L]::uuid[]', d_gt, o_nr)), 'ERR:BV337');
        perform pg_temp.expect('E15 control positivo: el alta con el departamento de su país', INT, 'authenticated',
            format(alta, '1', '93', 'Honduras', cons_sens, format('p_origin_department_item_id => %L::uuid, p_occupation_item_ids => array[%L]::uuid[]', d_hn, o_com)), '1');
        perform pg_temp.expect('E15: la ocupación del alta quedó guardada', null, null,
            $q$select (count(*) > 0)::text from public.person_occupation po join public.person p on p.id = po.person_id
               where p.given_name = 'Nueva' and p.paternal_family_name = 'Ficha' and po.valid_to is null$q$, 'true');

        -- ----- Extracto ARCO y anonimización (prep: la persona que se anonimiza al final)
        perform pg_temp.expect('E15 prep: estudios y ocupación de la persona que se anonimiza', DIR, 'authenticated',
            format(setp, 'aaaaaaaa-4000-0000-0000-000000000001', 'education_level', e_pri, null), '1');
        perform pg_temp.expect('E15 prep: una ocupación vigente de la persona que se anonimiza', DIR, 'authenticated',
            format(seto, 'aaaaaaaa-4000-0000-0000-000000000001', format('{%s}', o_hog), null), '1');
        perform pg_temp.expect('E15 prep: departamento de la persona que se anonimiza (escritura de preparación)', null, null,
            format($q$with u as (update public.person set origin_department_item_id = %L::uuid where id = 'aaaaaaaa-4000-0000-0000-000000000001' returning 1) select count(*)::text from u$q$, d_hn), '1');
        perform pg_temp.expect('E15: el extracto de acceso ARCO incluye la ficha completa', DIR, 'authenticated',
            format($q$select ((e->'person' ? 'education_level') and (e->'person' ? 'origin_department') and (e->'person' ? 'marital_status')
                              and jsonb_array_length(e->'person'->'occupations') > 0)::text
                      from (select public.fn_generate_arco_access_extract(%L::uuid) as e) s$q$, 'aaaaaaaa-4000-0000-0000-000000000001'), 'true');
    end;

    -- ============================================================================================
    -- ===== E15 fase 2: ficha social con preguntas configurables (migración 20261023000001)
    -- ===== Las preguntas de la ficha social (contexto migratorio y situaciones sensibles) son datos que editan dirección y
    -- ===== Trabajo Social; cada respuesta es versionada (lo cambiado se cierra con motivo) y las sensibles exigen el
    -- ===== consentimiento sensible (salvo «no quiso responder»). Las respuestas son informativas: el marcador manda.
    -- ============================================================================================
    declare
        C_OK constant text := pg_temp.id('5000', 32);   -- con consentimiento sensible vigente
        C_NO constant text := pg_temp.id('5000', 33);   -- sin consentimiento sensible
        CW_LG constant text := 'aaaaaaaa-3000-0000-0000-00000000000a';  -- área jurídica: no administra preguntas
        q_yn   constant text := 'aaaaaaaa-c100-0000-0000-000000000001';
        q_yns  constant text := 'aaaaaaaa-c100-0000-0000-000000000002';
        q_num  constant text := 'aaaaaaaa-c100-0000-0000-000000000003';
        q_txt  constant text := 'aaaaaaaa-c100-0000-0000-000000000004';
        q_date constant text := 'aaaaaaaa-c100-0000-0000-000000000005';
        q_off  constant text := 'aaaaaaaa-c100-0000-0000-000000000006';
        q_b    constant text := 'bbbbbbbb-c100-0000-0000-000000000001';
        seta text := $q$select count(*)::text from (select public.fn_set_social_answers(%L::uuid, %L::jsonb, %L)) x$q$;
        cur text := $q$select count(*)::text from public.social_answer where case_id = %L::uuid and valid_to is null$q$;
    begin
        begin
            insert into public.social_question (id, organization_id, key, label_es, section, answer_type, has_detail, is_sensitive, is_active, sort_order) values
                (q_yn::uuid, ORG_A::uuid, 'wants_return', '¿Quiere regresar? (prueba)', 'migration', 'yes_no', true, false, true, 1),
                (q_yns::uuid, ORG_A::uuid, 'life_in_danger', '¿Su vida corre peligro? (prueba)', 'sensitive', 'yes_no', false, true, true, 2),
                (q_num::uuid, ORG_A::uuid, 'times_in_mexico', '¿Cuántas veces en México? (prueba)', 'migration', 'number', false, false, true, 3),
                (q_txt::uuid, ORG_A::uuid, 'entry_point', '¿Por qué punto ingresó? (prueba)', 'migration', 'text', false, false, true, 4),
                (q_date::uuid, ORG_A::uuid, 'detention_release', 'Salida de la detención (prueba)', 'sensitive', 'date', false, true, true, 5),
                (q_off::uuid, ORG_A::uuid, 'retired_question', 'Pregunta retirada', 'migration', 'text', false, false, false, 6),
                (q_b::uuid, ORG_B::uuid, 'wants_return', '¿Quiere regresar? (B)', 'migration', 'yes_no', false, false, true, 1);
        exception when others then
            raise notice 'E15f2 escenario: sin las preguntas de la ficha social todavía (%).', sqlerrm;
        end;

        -- ----- Respuestas: tipos y reglas
        perform pg_temp.expect('E15f2 control positivo: quien atiende responde un sí con su detalle', CW, 'authenticated',
            format(seta, C_NO, '[{"question_key":"wants_return","choice":"yes","detail":"Quiere volver pronto"}]', null), '1');
        perform pg_temp.expect('E15f2: quedó guardada, vigente', null, null, format(cur, C_NO), '1');
        perform pg_temp.expect('E15f2: un número', CW, 'authenticated',
            format(seta, C_NO, '[{"question_key":"times_in_mexico","number":3}]', null), '1');
        perform pg_temp.expect('E15f2: un texto corto', CW, 'authenticated',
            format(seta, C_NO, '[{"question_key":"entry_point","text":"Tapachula-prueba"}]', null), '1');
        perform pg_temp.expect('E15f2: varias respuestas en una sola operación', CW, 'authenticated',
            format(seta, C_OK, '[{"question_key":"wants_return","choice":"no"},{"question_key":"times_in_mexico","number":1},{"question_key":"detention_release","date":"2026-03-01","precision":"month"}]', null), '1');
        perform pg_temp.expect('E15f2: un número fuera de rango → BV340', CW, 'authenticated',
            format(seta, C_NO, '[{"question_key":"times_in_mexico","number":1000}]', 'x'), 'ERR:BV340');
        perform pg_temp.expect('E15f2: una respuesta de otro tipo → BV340', CW, 'authenticated',
            format(seta, C_NO, '[{"question_key":"times_in_mexico","text":"tres"}]', 'x'), 'ERR:BV340');
        perform pg_temp.expect('E15f2: un sí/no con un valor que no existe → BV340', CW, 'authenticated',
            format(seta, C_NO, '[{"question_key":"wants_return","choice":"quizá"}]', 'x'), 'ERR:BV340');
        perform pg_temp.expect('E15f2: el detalle solo en las preguntas que lo admiten → BV340', CW, 'authenticated',
            format(seta, C_OK, '[{"question_key":"life_in_danger","choice":"no","detail":"x"}]', null), 'ERR:BV340');
        perform pg_temp.expect('E15f2: un texto demasiado largo → BV321', CW, 'authenticated',
            format(seta, C_NO, format('[{"question_key":"entry_point","text":"%s"}]', repeat('x', 121)), 'x'), 'ERR:BV321');
        perform pg_temp.expect('E15f2: una fecha futura → BV326', CW, 'authenticated',
            format(seta, C_OK, '[{"question_key":"detention_release","date":"2999-01-01","precision":"day"}]', 'x'), 'ERR:BV326');
        perform pg_temp.expect('E15f2: una precisión que no existe → BV325', CW, 'authenticated',
            format(seta, C_OK, '[{"question_key":"detention_release","date":"2026-03-01","precision":"semana"}]', 'x'), 'ERR:BV325');
        perform pg_temp.expect('E15f2: una pregunta que no existe → BV340', CW, 'authenticated',
            format(seta, C_NO, '[{"question_key":"no_existe","choice":"yes"}]', 'x'), 'ERR:BV340');
        perform pg_temp.expect('E15f2: una pregunta retirada no se responde → BV340', CW, 'authenticated',
            format(seta, C_NO, '[{"question_key":"retired_question","text":"x"}]', 'x'), 'ERR:BV340');
        perform pg_temp.expect('E15f2: lo que no es una lista → BV340', CW, 'authenticated',
            format(seta, C_NO, '{"question_key":"wants_return"}', 'x'), 'ERR:BV340');

        -- ----- Sensibles: consentimiento sensible vigente, salvo «no quiso responder»
        perform pg_temp.expect('E15f2: sin consentimiento sensible no se responde una pregunta sensible → BV408', CW, 'authenticated',
            format(seta, C_NO, '[{"question_key":"life_in_danger","choice":"yes"}]', null), 'ERR:BV408');
        perform pg_temp.expect('E15f2: «no quiso responder» sí se registra sin consentimiento sensible', CW, 'authenticated',
            format(seta, C_NO, '[{"question_key":"life_in_danger","choice":"no_response"}]', null), '1');
        perform pg_temp.expect('E15f2 control positivo: con consentimiento sensible, la sensible se responde', CW, 'authenticated',
            format(seta, C_OK, '[{"question_key":"life_in_danger","choice":"yes"}]', null), '1');

        -- ----- Versionado: nada se sobrescribe
        perform pg_temp.expect('E15f2: cambiar una respuesta sin motivo no se puede → BV304', CW, 'authenticated',
            format(seta, C_NO, '[{"question_key":"wants_return","choice":"no"}]', null), 'ERR:BV304');
        perform pg_temp.expect('E15f2: con motivo se cambia', CW, 'authenticated',
            format(seta, C_NO, '[{"question_key":"wants_return","choice":"no"}]', 'La persona cambió de opinión'), '1');
        perform pg_temp.expect('E15f2: la anterior se cerró con su motivo, no se borró', null, null,
            format($q$select count(*)::text from public.social_answer sa join public.social_question sq on sq.id = sa.question_id
               where sa.case_id = %L::uuid and sq.key = 'wants_return' and sa.valid_to is not null and sa.change_reason = 'La persona cambió de opinión'$q$, C_NO), '1');
        perform pg_temp.expect('E15f2: repetir la misma respuesta no cambia nada ni pide motivo', CW, 'authenticated',
            format(seta, C_NO, '[{"question_key":"wants_return","choice":"no"}]', null), '1');
        perform pg_temp.expect('E15f2: quitar una respuesta pide motivo → BV304', CW, 'authenticated',
            format(seta, C_NO, '[{"question_key":"entry_point","clear":true}]', null), 'ERR:BV304');
        perform pg_temp.expect('E15f2: con motivo se quita (queda cerrada)', CW, 'authenticated',
            format(seta, C_NO, '[{"question_key":"entry_point","clear":true}]', 'Se capturó por error'), '1');
        perform pg_temp.expect('E15f2: quitar lo que no estaba no hace falta justificarlo', CW, 'authenticated',
            format(seta, C_NO, '[{"question_key":"detention_release","clear":true}]', null), '1');

        -- ----- Quién
        perform pg_temp.expect('E15f2: el rol de solo lectura no responde → BV120', VW, 'authenticated',
            format(seta, C_NO, '[{"question_key":"wants_return","choice":"yes"}]', 'x'), 'ERR:BV120');
        perform pg_temp.expect('E15f2: el voluntariado no responde → BV120', VOL, 'authenticated',
            format(seta, C_NO, '[{"question_key":"wants_return","choice":"yes"}]', 'x'), 'ERR:BV120');
        perform pg_temp.expect('E15f2: otra organización no ve el expediente → BV201', DIRB2, 'authenticated',
            format(seta, C_NO, '[{"question_key":"wants_return","choice":"yes"}]', 'x'), 'ERR:BV201');
        perform pg_temp.expect('E15f2: las respuestas no se escriben por la API directa', CW, 'authenticated',
            format($q$with i as (insert into public.social_answer (organization_id, case_id, question_id, choice, created_by) values (%L::uuid, %L::uuid, %L::uuid, 'yes', %L::uuid) returning 1) select count(*)::text from i$q$, ORG_A, C_NO, q_yn, CW), 'ERR');
        perform pg_temp.expect('E15f2: ni se borran por la API directa', DIR, 'authenticated',
            $q$with d as (delete from public.social_answer returning 1) select count(*)::text from d$q$, 'ERR');
        perform pg_temp.expect('E15f2: otra organización no ve las respuestas de A', DIRB2, 'authenticated', 'select count(*)::text from public.social_answer', '0');
        perform pg_temp.expect('E15f2: sin rol no se ven las respuestas', NR, 'authenticated', 'select count(*)::text from public.social_answer', '0');
        perform pg_temp.expect('E15f2: la auditoría deja eventos sin el texto de lo respondido', null, null,
            $q$select ((count(*) > 0) and not bool_or(coalesce(new_values::text, '') ilike '%Tapachula-prueba%'))::text from public.audit_event
               where table_name = 'social_answer' and created_at >= transaction_timestamp()$q$, 'true');

        -- ----- Las preguntas las administran dirección y Trabajo Social
        perform pg_temp.expect('E15f2 control positivo: Trabajo Social agrega una pregunta', CW, 'authenticated',
            format($q$with i as (insert into public.social_question (organization_id, key, label_es, section, answer_type, sort_order) values (%L::uuid, 'nueva_pregunta', '¿Nueva pregunta?', 'migration', 'yes_no', 9) returning 1) select count(*)::text from i$q$, ORG_A), '1');
        perform pg_temp.expect('E15f2: el área jurídica no administra preguntas', CW_LG, 'authenticated',
            format($q$with i as (insert into public.social_question (organization_id, key, label_es, section, answer_type, sort_order) values (%L::uuid, 'otra_pregunta', '¿Otra?', 'migration', 'yes_no', 9) returning 1) select count(*)::text from i$q$, ORG_A), 'ERR');
        perform pg_temp.expect('E15f2: una sección que no existe se rechaza', CW, 'authenticated',
            format($q$with i as (insert into public.social_question (organization_id, key, label_es, section, answer_type, sort_order) values (%L::uuid, 'sec_mala', 'x', 'inventada', 'yes_no', 9) returning 1) select count(*)::text from i$q$, ORG_A), 'ERR');
        perform pg_temp.expect('E15f2: el detalle solo en preguntas de sí/no', CW, 'authenticated',
            format($q$with i as (insert into public.social_question (organization_id, key, label_es, section, answer_type, has_detail, sort_order) values (%L::uuid, 'num_detalle', 'x', 'migration', 'number', true, 9) returning 1) select count(*)::text from i$q$, ORG_A), 'ERR');
        perform pg_temp.expect('E15f2: el tipo de una pregunta no cambia → BV341', CW, 'authenticated',
            format($q$with u as (update public.social_question set answer_type = 'text' where id = %L::uuid returning 1) select count(*)::text from u$q$, q_num), 'ERR:BV341');
        perform pg_temp.expect('E15f2: la clave no cambia → BV341', CW, 'authenticated',
            format($q$with u as (update public.social_question set key = 'otra_clave' where id = %L::uuid returning 1) select count(*)::text from u$q$, q_num), 'ERR:BV341');
        perform pg_temp.expect('E15f2: una pregunta sensible no deja de serlo → BV341', CW, 'authenticated',
            format($q$with u as (update public.social_question set is_sensitive = false where id = %L::uuid returning 1) select count(*)::text from u$q$, q_yns), 'ERR:BV341');
        perform pg_temp.expect('E15f2 control positivo: una pregunta sí puede pasar a sensible', CW, 'authenticated',
            format($q$with u as (update public.social_question set is_sensitive = true where id = %L::uuid returning 1) select count(*)::text from u$q$, q_txt), '1');
        perform pg_temp.expect('E15f2 control positivo: se renombra y se retira', CW, 'authenticated',
            format($q$with u as (update public.social_question set label_es = 'Texto nuevo', is_active = false where id = %L::uuid returning 1) select count(*)::text from u$q$, q_num), '1');
        perform pg_temp.expect('E15f2: las preguntas no se borran', DIR, 'authenticated',
            $q$with d as (delete from public.social_question returning 1) select count(*)::text from d$q$, 'ERR');
        perform pg_temp.expect('E15f2: otra organización no ve las preguntas de A', DIRB2, 'authenticated',
            format($q$select count(*)::text from public.social_question where organization_id = %L::uuid$q$, ORG_A), '0');
        perform pg_temp.expect('E15f2: el rol de solo lectura no ve las preguntas', VW, 'authenticated', 'select count(*)::text from public.social_question', '0');

        -- ----- Extracto ARCO y anonimización (prep: la persona que se anonimiza al final)
        perform pg_temp.expect('E15f2: el extracto de acceso ARCO incluye las respuestas de la ficha social', DIR, 'authenticated',
            format($q$select (jsonb_array_length(public.fn_generate_arco_access_extract(%L::uuid)->'social_answers') > 0)::text$q$, pg_temp.id('4000', 32)), 'true');
        perform pg_temp.expect('E15f2 prep: respuestas con texto y detalle de la persona que se anonimiza', DIR, 'authenticated',
            format(seta, 'aaaaaaaa-5000-0000-0000-000000000001', '[{"question_key":"wants_return","choice":"yes","detail":"Detalle identificable"},{"question_key":"nueva_pregunta","choice":"no"}]', null), '1');
    end;

    -- ============================================================================================
    -- ===== E15 fase 3: registro de origen (KOBO / REDODEM) y «Servicio social» (migración 20261023000002)
    -- ===== El registro de origen son preguntas de la ficha social en una sección propia, solo informativas; de KOBO solo se
    -- ===== guarda lo que no se repite en la ficha. «Servicio social» es una línea de servicio nueva de la bitácora.
    -- ============================================================================================
    declare
        C_NO3 constant text := pg_temp.id('5000', 33);
        q_org constant text := 'aaaaaaaa-c100-0000-0000-000000000011';
        q_ors constant text := 'aaaaaaaa-c100-0000-0000-000000000012';
        seta3 text := $q$select count(*)::text from (select public.fn_set_social_answers(%L::uuid, %L::jsonb, %L)) x$q$;
        DEMO_ORG constant text := '00000000-0000-0000-0000-000000000001';
    begin
        begin
            insert into public.social_question (id, organization_id, key, label_es, section, answer_type, is_sensitive, sort_order) values
                (q_org::uuid, ORG_A::uuid, 'origin_registered_on', 'Fecha de registro de origen (prueba)', 'origin', 'date', false, 1),
                (q_ors::uuid, ORG_A::uuid, 'origin_population', 'Tipo de población de origen (prueba)', 'origin', 'text', true, 2);
        exception when others then
            raise notice 'E15f3 escenario: sin la sección de origen todavía (%).', sqlerrm;
        end;
        perform pg_temp.expect('E15f3: la sección de registro de origen existe y se responde (fecha de registro)', CW, 'authenticated',
            format(seta3, C_NO3, '[{"question_key":"origin_registered_on","date":"2026-02-01","precision":"day"}]', null), '1');
        perform pg_temp.expect('E15f3: un dato de origen marcado sensible exige consentimiento sensible → BV408', CW, 'authenticated',
            format(seta3, C_NO3, '[{"question_key":"origin_population","text":"Migrante en tránsito"}]', null), 'ERR:BV408');
        perform pg_temp.expect('E15f3: Trabajo Social agrega una pregunta de la sección de origen', CW, 'authenticated',
            format($q$with i as (insert into public.social_question (organization_id, key, label_es, section, answer_type, sort_order) values (%L::uuid, 'origen_extra', '¿Otro dato de origen?', 'origin', 'text', 9) returning 1) select count(*)::text from i$q$, ORG_A), '1');
        perform pg_temp.expect('E15f3: una sección que no existe sigue rechazándose', CW, 'authenticated',
            format($q$with i as (insert into public.social_question (organization_id, key, label_es, section, answer_type, sort_order) values (%L::uuid, 'sec_mala_3', 'x', 'externa', 'text', 9) returning 1) select count(*)::text from i$q$, ORG_A), 'ERR');
        perform pg_temp.expect('E15f3: se siembran las tres preguntas de origen (sin repetir la edad ni la nacionalidad de KOBO)', null, null,
            format($q$select count(*)::text from public.social_question where organization_id = %L::uuid and section = 'origin'$q$, DEMO_ORG), '3');
        perform pg_temp.expect('E15f3: no se siembra la edad ni la nacionalidad de KOBO (ya están en la ficha)', null, null,
            format($q$select count(*)::text from public.social_question where organization_id = %L::uuid and (key ilike '%%kobo_age%%' or key ilike '%%kobo_nationality%%')$q$, DEMO_ORG), '0');
        perform pg_temp.expect('E15f3: «Servicio social» es una línea de servicio de la bitácora', null, null,
            format($q$select count(*)::text from public.catalog_item where organization_id = %L::uuid and catalog = 'service_line' and key = 'social_service'$q$, DEMO_ORG), '1');
    end;

    -- ============================================================================================
    -- ===== E15 fase 4: papel en la familia (migración 20261024000001)
    -- ===== El orden de la matriz (madre, padre o pareja, hijos de mayor a menor, otros) necesita saber el papel de cada
    -- ===== persona en la familia. El papel es un diccionario editable; se registra dentro de una familia y se corrige con motivo.
    -- ===== El orden sugerido se calcula en la interfaz; aquí se prueba el dato y sus reglas.
    -- ============================================================================================
    declare
        C_F1 constant text := pg_temp.id('5000', 32);
        C_F2 constant text := pg_temp.id('5000', 33);
        C_ALONE constant text := pg_temp.id('5000', 34);
        r_mother constant text := 'aaaaaaaa-c200-0000-0000-000000000001';
        r_child  constant text := 'aaaaaaaa-c200-0000-0000-000000000002';
        r_off    constant text := 'aaaaaaaa-c200-0000-0000-000000000003';
        r_other_catalog constant text := 'aaaaaaaa-c000-0000-0000-000000000001';
        r_b      constant text := 'bbbbbbbb-c200-0000-0000-000000000001';
        setrole text := $q$select count(*)::text from (select public.fn_set_family_member_role(%L::uuid, %L::uuid, %L)) x$q$;
    begin
        begin
            insert into public.catalog_item (id, organization_id, catalog, key, label_es, is_active, is_system, sort_order) values
                (r_mother::uuid, ORG_A::uuid, 'family_role', 'mother', 'Madre (prueba)', true, false, 1),
                (r_child::uuid, ORG_A::uuid, 'family_role', 'child', 'Hija o hijo (prueba)', true, false, 3),
                (r_off::uuid, ORG_A::uuid, 'family_role', 'retired', 'Papel retirado', false, false, 9),
                (r_b::uuid, ORG_B::uuid, 'family_role', 'mother', 'Madre B', true, false, 1);
        exception when others then
            raise notice 'E15f4 escenario: sin el diccionario de papeles todavía (%).', sqlerrm;
        end;
        -- La familia de prueba: dos personas en la misma familia nueva
        perform pg_temp.expect('E15f4 prep: se crea una familia con la primera persona', CW, 'authenticated',
            format($q$select count(*)::text from (select public.fn_set_case_family(%L::uuid, null, 1, null, 'FAM-E15F4-1')) x$q$, C_F1), '1');
        perform pg_temp.expect('E15f4 prep: la segunda persona se asigna a esa familia', CW, 'authenticated',
            format($q$select count(*)::text from (select public.fn_set_case_family(%L::uuid, (select family_unit_id from public.family_member where case_id = %L::uuid and valid_to is null), 2, null)) x$q$, C_F2, C_F1), '1');

        perform pg_temp.expect('E15f4 control positivo: se registra el papel dentro de la familia', CW, 'authenticated',
            format(setrole, C_F1, r_mother, null), '1');
        perform pg_temp.expect('E15f4: quedó guardado en la pertenencia vigente', null, null,
            format($q$select count(*)::text from public.family_member where case_id = %L::uuid and valid_to is null and family_role_item_id = %L::uuid$q$, C_F1, r_mother), '1');
        perform pg_temp.expect('E15f4: cambiar el papel sin motivo no se puede → BV304', CW, 'authenticated',
            format(setrole, C_F1, r_child, null), 'ERR:BV304');
        perform pg_temp.expect('E15f4: con motivo se cambia', CW, 'authenticated',
            format(setrole, C_F1, r_child, 'Era su hija, no su madre'), '1');
        perform pg_temp.expect('E15f4: el cambio deja su motivo en la auditoría', null, null,
            $q$select (count(*) > 0)::text from public.audit_event where action = 'RECTIFICATION' and table_name = 'family_member'
               and new_values->>'reason' = 'Era su hija, no su madre' and created_at >= transaction_timestamp()$q$, 'true');
        perform pg_temp.expect('E15f4: se puede quitar con motivo', CW, 'authenticated',
            format(setrole, C_F1, null, 'Se capturó por error'), '1');
        perform pg_temp.expect('E15f4: sin papel registrado el campo queda vacío («No registrado»)', null, null,
            format($q$select count(*)::text from public.family_member where case_id = %L::uuid and valid_to is null and family_role_item_id is null$q$, C_F1), '1');
        perform pg_temp.expect('E15f4: una persona sin familia no tiene papel que registrar → BV342', CW, 'authenticated',
            format(setrole, C_ALONE, r_mother, null), 'ERR:BV342');
        perform pg_temp.expect('E15f4: un papel de otra organización no se usa → BV220', CW, 'authenticated',
            format(setrole, C_F2, r_b, 'x'), 'ERR:BV220');
        perform pg_temp.expect('E15f4: un papel retirado no se usa → BV220', CW, 'authenticated',
            format(setrole, C_F2, r_off, 'x'), 'ERR:BV220');
        perform pg_temp.expect('E15f4: un valor de otro diccionario no vale como papel → BV220', CW, 'authenticated',
            format(setrole, C_F2, r_other_catalog, 'x'), 'ERR:BV220');
        perform pg_temp.expect('E15f4: el rol de solo lectura no registra el papel → BV120', VW, 'authenticated',
            format(setrole, C_F2, r_mother, 'x'), 'ERR:BV120');
        perform pg_temp.expect('E15f4: el voluntariado no registra el papel → BV120', VOL, 'authenticated',
            format(setrole, C_F2, r_mother, 'x'), 'ERR:BV120');
        perform pg_temp.expect('E15f4: otra organización no ve el expediente → BV201', DIRB2, 'authenticated',
            format(setrole, C_F2, r_b, 'x'), 'ERR:BV201');
        perform pg_temp.expect('E15f4: el papel no se escribe por la API directa', CW, 'authenticated',
            format($q$with u as (update public.family_member set family_role_item_id = %L::uuid where case_id = %L::uuid returning 1) select count(*)::text from u$q$, r_mother, C_F2), 'ERR');
        perform pg_temp.expect('E15f4: Trabajo Social agrega un papel al diccionario', CW, 'authenticated',
            format($q$with i as (insert into public.catalog_item (organization_id, catalog, key, label_es, sort_order) values (%L::uuid, 'family_role', 'abuela', 'Abuela', 6) returning 1) select count(*)::text from i$q$, ORG_A), '1');
        perform pg_temp.expect('E15f4: los cuatro papeles de la matriz se siembran (madre, padre o pareja, hija o hijo, otro)', null, null,
            $q$select count(*)::text from public.catalog_item where organization_id = '00000000-0000-0000-0000-000000000001' and catalog = 'family_role' and key in ('mother','father_partner','child','other')$q$, '4');
        perform pg_temp.expect('E15f4: el extracto de acceso ARCO incluye el papel en la familia', DIR, 'authenticated',
            format($q$select (bool_or(f ? 'family_role'))::text from jsonb_array_elements(public.fn_generate_arco_access_extract(%L::uuid)->'family') f$q$, pg_temp.id('4000', 32)), 'true');
    end;

    -- ============================================================================================
    -- ===== E16 fase A: gestionar el equipo (migración 20261025000001)
    -- ===== La dirección otorga, revoca y desactiva por funciones (motivo, auditoría, salvaguardas); ya no escribe directo en
    -- ===== `user_role` y `user_profile` (paga la parte de roles de D-20). Rol y área son independientes: cualquier rol con
    -- ===== cualquier área o sin ella, y una persona puede tener varios (muchas gorras). Nunca sin dirección (TK006).
    -- ============================================================================================
    declare
        TARGET constant text := 'aaaaaaaa-3000-0000-0000-000000000008';   -- VOL2: voluntariado de A
        AR_LG constant text := 'aaaaaaaa-1000-0000-0000-000000000002';
        AR_TS constant text := 'aaaaaaaa-1000-0000-0000-000000000001';
        AR_B  constant text := 'bbbbbbbb-1000-0000-0000-000000000001';
        grant_ text := $q$select count(*)::text from (select public.fn_grant_role(%L::uuid, %L, %s, %L)) x$q$;
        revoke_ text := $q$select count(*)::text from (select public.fn_revoke_role(%L::uuid, %L)) x$q$;
        active_ text := $q$select count(*)::text from (select public.fn_set_user_active(%L::uuid, %s, %L)) x$q$;
        row_cw text;
    begin
        -- ----- Otorgar
        perform pg_temp.expect('E16A control positivo: la dirección otorga un rol con su área', DIR, 'authenticated',
            format(grant_, TARGET, 'caseworker', format('%L::uuid', AR_LG), 'Cubre al área jurídica'), '1');
        perform pg_temp.expect('E16A: quedó vigente, con quién y por qué', null, null,
            format($q$select count(*)::text from public.user_role where user_id = %L::uuid and role_name = 'caseworker' and area_id = %L::uuid
               and revoked_at is null and granted_by = %L::uuid and grant_reason = 'Cubre al área jurídica'$q$, TARGET, AR_LG, DIR), '1');
        perform pg_temp.expect('E16A: el mismo rol en la misma área no se duplica → BV345', DIR, 'authenticated',
            format(grant_, TARGET, 'caseworker', format('%L::uuid', AR_LG), null), 'ERR:BV345');
        perform pg_temp.expect('E16A: el mismo rol en otra área sí (muchas gorras)', DIR, 'authenticated',
            format(grant_, TARGET, 'caseworker', format('%L::uuid', AR_TS), null), '1');
        perform pg_temp.expect('E16A: cualquier rol puede ir con área o sin ella, sin restricciones de combinación', DIR, 'authenticated',
            format(grant_, TARGET, 'viewer', format('%L::uuid', AR_LG), null), '1');
        perform pg_temp.expect('E16A: ni siquiera dirección está limitada a no tener área', DIR, 'authenticated',
            format(grant_, TARGET, 'director', format('%L::uuid', AR_TS), 'Prueba de flexibilidad'), '1');
        perform pg_temp.expect('E16A: un rol que no existe → BV344', DIR, 'authenticated',
            format(grant_, TARGET, 'superadmin', 'null', null), 'ERR:BV344');
        perform pg_temp.expect('E16A: un área de otra organización → BV344', DIR, 'authenticated',
            format(grant_, TARGET, 'caseworker', format('%L::uuid', AR_B), null), 'ERR:BV344');
        perform pg_temp.expect('E16A: sin rol indicado → BV344', DIR, 'authenticated',
            format(grant_, TARGET, null, 'null', null), 'ERR:BV344');
        perform pg_temp.expect('E16A: una cuenta de otra organización no se gestiona → BV347', DIRB2, 'authenticated',
            format(grant_, TARGET, 'viewer', 'null', null), 'ERR:BV347');
        perform pg_temp.expect('E16A: solo la dirección gestiona el equipo: caseworker → BV346', CW, 'authenticated',
            format(grant_, TARGET, 'viewer', 'null', null), 'ERR:BV346');
        perform pg_temp.expect('E16A: el rol de solo lectura no gestiona el equipo → BV346', VW, 'authenticated',
            format(grant_, TARGET, 'viewer', 'null', null), 'ERR:BV346');
        perform pg_temp.expect('E16A: el voluntariado no gestiona el equipo → BV346', VOL, 'authenticated',
            format(grant_, TARGET, 'viewer', 'null', null), 'ERR:BV346');
        perform pg_temp.expect('E16A: sin rol alguno no se gestiona el equipo → BV346', NR, 'authenticated',
            format(grant_, TARGET, 'viewer', 'null', null), 'ERR:BV346');

        -- ----- Revocar (no se borra: fecha, quién y motivo)
        row_cw := (select id::text from public.user_role where user_id = TARGET::uuid and role_name = 'caseworker' and area_id = AR_LG::uuid and revoked_at is null);
        perform pg_temp.expect('E16A: revocar sin motivo no se puede → BV304', DIR, 'authenticated',
            format(revoke_, row_cw, null), 'ERR:BV304');
        perform pg_temp.expect('E16A: quien no gestiona el equipo no revoca → BV346', CW, 'authenticated',
            format(revoke_, row_cw, 'x'), 'ERR:BV346');
        perform pg_temp.expect('E16A control positivo: con motivo se revoca', DIR, 'authenticated',
            format(revoke_, row_cw, 'Ya no cubre al área'), '1');
        perform pg_temp.expect('E16A: la asignación queda cerrada con su motivo, no se borra', null, null,
            format($q$select count(*)::text from public.user_role where id = %L::uuid and revoked_at is not null and revoked_by = %L::uuid and revoke_reason = 'Ya no cubre al área'$q$, row_cw, DIR), '1');
        perform pg_temp.expect('E16A: una asignación que ya no está vigente → BV348', DIR, 'authenticated',
            format(revoke_, row_cw, 'x'), 'ERR:BV348');
        perform pg_temp.expect('E16A: una asignación que no existe → BV348', DIR, 'authenticated',
            format(revoke_, 'aaaaaaaa-ffff-0000-0000-000000000000', 'x'), 'ERR:BV348');
        perform pg_temp.expect('E16A: nadie se revoca a sí mismo → BV343', DIR, 'authenticated',
            format(revoke_, (select id::text from public.user_role where user_id = DIR::uuid and role_name = 'director' and revoked_at is null limit 1), 'x'), 'ERR:BV343');
        perform pg_temp.expect('E16A: una asignación de otra organización no se revoca → BV348', DIRB2, 'authenticated',
            format(revoke_, (select id::text from public.user_role where user_id = TARGET::uuid and role_name = 'viewer' and revoked_at is null limit 1), 'x'), 'ERR:BV348');
        perform pg_temp.expect('E16A: se revoca la dirección de prueba (queda otra dirección vigente)', DIR, 'authenticated',
            format(revoke_, (select id::text from public.user_role where user_id = TARGET::uuid and role_name = 'director' and revoked_at is null limit 1), 'Fin de la prueba'), '1');

        -- ----- Desactivar y reactivar cuentas
        perform pg_temp.expect('E16A: desactivar sin motivo no se puede → BV304', DIR, 'authenticated',
            format(active_, TARGET, 'false', null), 'ERR:BV304');
        perform pg_temp.expect('E16A: nadie se desactiva a sí mismo → BV343', DIR, 'authenticated',
            format(active_, DIR, 'false', 'x'), 'ERR:BV343');
        perform pg_temp.expect('E16A: quien no gestiona el equipo no desactiva → BV346', CW, 'authenticated',
            format(active_, TARGET, 'false', 'x'), 'ERR:BV346');
        perform pg_temp.expect('E16A: una cuenta de otra organización no se desactiva → BV347', DIRB2, 'authenticated',
            format(active_, TARGET, 'false', 'x'), 'ERR:BV347');
        perform pg_temp.expect('E16A control positivo: con motivo se desactiva la cuenta', DIR, 'authenticated',
            format(active_, TARGET, 'false', 'Dejó el albergue'), '1');
        perform pg_temp.expect('E16A: la cuenta desactivada queda inactiva', null, null,
            format($q$select count(*)::text from public.user_profile where id = %L::uuid and not active$q$, TARGET), '1');
        perform pg_temp.expect('E16A: la desactivación deja su motivo en la auditoría', null, null,
            $q$select (count(*) > 0)::text from public.audit_event where table_name = 'user_profile' and new_values->>'reason' = 'Dejó el albergue' and created_at >= transaction_timestamp()$q$, 'true');
        perform pg_temp.expect('E16A control positivo: con motivo se reactiva', DIR, 'authenticated',
            format(active_, TARGET, 'true', 'Regresó al albergue'), '1');
        perform pg_temp.expect('E16A: la cuenta reactivada vuelve a estar activa', null, null,
            format($q$select count(*)::text from public.user_profile where id = %L::uuid and active$q$, TARGET), '1');
        perform pg_temp.expect('E16A: repetir el mismo estado no cambia nada ni pide motivo', DIR, 'authenticated',
            format(active_, TARGET, 'true', null), '1');

        -- ----- Nunca sin dirección: la salvaguarda sigue en la base, también por las funciones
        perform pg_temp.expect('E16A: el último director de una organización no pierde su rol (la base lo impide aunque se pida con permiso)', null, null,
            format($q$with u as (update public.user_role set revoked_at = now() where user_id = %L::uuid and role_name = 'director' and revoked_at is null returning 1) select count(*)::text from u$q$, 'bbbbbbbb-3000-0000-0000-000000000003'), 'ERR:TK006');

        -- ----- Ya no se escribe directo
        perform pg_temp.expect('E16A: la dirección ya no inserta roles por la API directa', DIR, 'authenticated',
            format($q$with i as (insert into public.user_role (user_id, role_name, granted_by) values (%L::uuid, 'viewer', %L::uuid) returning 1) select count(*)::text from i$q$, TARGET, DIR), 'ERR');
        perform pg_temp.expect('E16A: ni los cambia por la API directa', DIR, 'authenticated',
            format($q$with u as (update public.user_role set revoked_at = now() where user_id = %L::uuid returning 1) select count(*)::text from u$q$, TARGET), 'ERR');
        perform pg_temp.expect('E16A: ni los borra por la API directa', DIR, 'authenticated',
            $q$with d as (delete from public.user_role returning 1) select count(*)::text from d$q$, 'ERR');
        perform pg_temp.expect('E16A: ni desactiva cuentas por la API directa', DIR, 'authenticated',
            format($q$with u as (update public.user_profile set active = false where id = %L::uuid returning 1) select count(*)::text from u$q$, TARGET), 'ERR');
        perform pg_temp.expect('E16A: caseworker tampoco escribe roles directo', CW, 'authenticated',
            format($q$with i as (insert into public.user_role (user_id, role_name, granted_by) values (%L::uuid, 'director', %L::uuid) returning 1) select count(*)::text from i$q$, CW, CW), 'ERR');

        -- ----- Lectura para la pantalla «Equipo»
        perform pg_temp.expect('E16A: la dirección ve los roles de su organización (también los revocados, para el historial)', DIR, 'authenticated',
            format($q$select (count(*) filter (where revoked_at is not null) > 0)::text from public.user_role where user_id = %L::uuid$q$, TARGET), 'true');
        perform pg_temp.expect('E16A: otra organización no ve los roles de A', DIRB2, 'authenticated',
            format($q$select count(*)::text from public.user_role where user_id = %L::uuid$q$, TARGET), '0');
        perform pg_temp.expect('E16A: la pantalla sabe si se puede gestionar el equipo (dirección: sí)', DIR, 'authenticated', 'select public.can_manage_team()::text', 'true');
        perform pg_temp.expect('E16A: la pantalla sabe si se puede gestionar el equipo (caseworker: no)', CW, 'authenticated', 'select public.can_manage_team()::text', 'false');
        perform pg_temp.expect('E16A: los cambios de roles quedan en la auditoría', null, null,
            $q$select (count(*) > 0)::text from public.audit_event where table_name = 'user_role' and created_at >= transaction_timestamp()$q$, 'true');
    end;

    -- ============================================================================================
    -- ===== E16 fase B: permisos como datos (migración 20261026000001)
    -- ===== Quién puede qué es un dato que configura la dirección: capacidades concedidas a un ROL o a un ÁREA (para quien
    -- ===== tiene un rol operativo en ella). Se migran cinco capacidades; el resto sigue por nombre de rol (deuda D-24).
    -- ===== Cambiar permisos es solo de la dirección (para que delegar la gestión del equipo no permita escalar privilegios).
    -- ============================================================================================
    declare
        CW_LG constant text := 'aaaaaaaa-3000-0000-0000-00000000000a';   -- área jurídica
        AR_TS constant text := 'aaaaaaaa-1000-0000-0000-000000000001';
        AR_B  constant text := 'bbbbbbbb-1000-0000-0000-000000000001';
        grantc text := $q$select count(*)::text from (select public.fn_grant_capability(%L, %s, %s, %L)) x$q$;
        revokec text := $q$select count(*)::text from (select public.fn_revoke_capability(%L::uuid, %L)) x$q$;
        hasc text := $q$select public.has_capability(%L)::text$q$;
        gid text;
    begin
        -- ----- El catálogo y los valores por omisión (lo que había cableado)
        perform pg_temp.expect('E16B: el catálogo de capacidades tiene las doce (cinco de la fase B, cuatro de D-24 tanda 2 y tres de la tanda 3)', DIR, 'authenticated',
            'select count(*)::text from public.capability', '12');
        perform pg_temp.expect('E16B: se leen sin ser dirección (la interfaz las nombra)', CW, 'authenticated',
            'select count(*)::text from public.capability', '12');
        perform pg_temp.expect('E16B: dirección tiene todas por omisión (gestión del equipo)', DIR, 'authenticated', format(hasc, 'manage_team'), 'true');
        perform pg_temp.expect('E16B: dirección ve la auditoría por omisión', DIR, 'authenticated', format(hasc, 'view_audit'), 'true');
        perform pg_temp.expect('E16B: dirección administra requerimientos de autoridad por omisión', DIR, 'authenticated', format(hasc, 'manage_authority_requests'), 'true');
        perform pg_temp.expect('E16B: dirección configura la organización por omisión', DIR, 'authenticated', format(hasc, 'manage_org_settings'), 'true');
        perform pg_temp.expect('E16B: Trabajo Social administra diccionarios por omisión (como antes)', CW, 'authenticated', format(hasc, 'manage_catalogs'), 'true');
        perform pg_temp.expect('E16B: el área jurídica no administra diccionarios', CW_LG, 'authenticated', format(hasc, 'manage_catalogs'), 'false');
        perform pg_temp.expect('E16B: Trabajo Social no gestiona el equipo por omisión', CW, 'authenticated', format(hasc, 'manage_team'), 'false');
        perform pg_temp.expect('E16B: el rol de solo lectura no tiene ninguna capacidad', VW, 'authenticated', format(hasc, 'manage_catalogs'), 'false');
        perform pg_temp.expect('E16B: una capacidad que no existe no se tiene', DIR, 'authenticated', format(hasc, 'inventada'), 'false');
        perform pg_temp.expect('E16B: las capacidades son por organización (dirección B no tiene las de A, tiene las suyas)', DIRB2, 'authenticated', format(hasc, 'manage_team'), 'true');
        perform pg_temp.expect('E16B: la interfaz conoce las capacidades de la dirección (las doce)', DIR, 'authenticated',
            'select array_length(public.fn_my_capabilities(), 1)::text', '12');
        perform pg_temp.expect('E16B: y las de Trabajo Social (solo diccionarios)', CW, 'authenticated',
            'select array_to_string(public.fn_my_capabilities(), '','')', 'manage_catalogs');
        perform pg_temp.expect('E16B: y las del rol de solo lectura (ninguna)', VW, 'authenticated',
            'select coalesce(array_length(public.fn_my_capabilities(), 1), 0)::text', '0');
        perform pg_temp.expect('E16B: los valores por omisión se sembraron para la organización demo', null, null,
            $q$select count(*)::text from public.capability_grant where organization_id = '00000000-0000-0000-0000-000000000001' and revoked_at is null$q$, '16');

        -- ----- Lectura de las asignaciones
        perform pg_temp.expect('E16B: la dirección ve las asignaciones de permisos de su organización', DIR, 'authenticated',
            'select (count(*) > 0)::text from public.capability_grant', 'true');
        perform pg_temp.expect('E16B: quien no gestiona permisos no ve las asignaciones', CW, 'authenticated', 'select count(*)::text from public.capability_grant', '0');
        perform pg_temp.expect('E16B: otra organización no ve las de A', DIRB2, 'authenticated',
            format($q$select count(*)::text from public.capability_grant where organization_id = %L::uuid$q$, ORG_A), '0');
        perform pg_temp.expect('E16B: las asignaciones no se escriben por la API directa', DIR, 'authenticated',
            format($q$with i as (insert into public.capability_grant (organization_id, capability_code, role_name, granted_by) values (%L::uuid, 'view_audit', 'viewer', %L::uuid) returning 1) select count(*)::text from i$q$, ORG_A, DIR), 'ERR');
        perform pg_temp.expect('E16B: ni se borran por la API directa', DIR, 'authenticated',
            $q$with d as (delete from public.capability_grant returning 1) select count(*)::text from d$q$, 'ERR');

        -- ----- Otorgar a un rol: el observador ve la auditoría (prueba de que view_audit gobierna la lectura)
        perform pg_temp.expect('E16B: antes, el observador no lee la auditoría', VW, 'authenticated', 'select count(*)::text from public.audit_event', '0');
        perform pg_temp.expect('E16B control positivo: la dirección concede la auditoría al rol observador', DIR, 'authenticated',
            format(grantc, 'view_audit', format('%L', 'viewer'), 'null', 'Auditoría externa', null), '1');
        perform pg_temp.expect('E16B: ahora el observador sí lee la auditoría', VW, 'authenticated', 'select (count(*) > 0)::text from public.audit_event', 'true');
        perform pg_temp.expect('E16B: lo concedido a un rol no se concede dos veces → BV351', DIR, 'authenticated',
            format(grantc, 'view_audit', format('%L', 'viewer'), 'null', null, null), 'ERR:BV351');
        gid := (select id::text from public.capability_grant where capability_code = 'view_audit' and role_name = 'viewer' and revoked_at is null and organization_id = ORG_A::uuid);
        perform pg_temp.expect('E16B: revocar sin motivo no se puede → BV304', DIR, 'authenticated', format(revokec, gid, null), 'ERR:BV304');
        perform pg_temp.expect('E16B control positivo: con motivo se revoca', DIR, 'authenticated', format(revokec, gid, 'Terminó la auditoría'), '1');
        perform pg_temp.expect('E16B: la concesión queda cerrada con su motivo, no se borra', null, null,
            format($q$select count(*)::text from public.capability_grant where id = %L::uuid and revoked_at is not null and revoke_reason = 'Terminó la auditoría'$q$, gid), '1');
        perform pg_temp.expect('E16B: el observador vuelve a no leer la auditoría', VW, 'authenticated', 'select count(*)::text from public.audit_event', '0');
        perform pg_temp.expect('E16B: una concesión que ya no está vigente → BV352', DIR, 'authenticated', format(revokec, gid, 'x'), 'ERR:BV352');

        -- ----- Otorgar a un ÁREA: Trabajo Social recibe la gestión del equipo (delegar sin migración)
        perform pg_temp.expect('E16B: antes, Trabajo Social no gestiona el equipo (E16A → BV346)', CW, 'authenticated',
            format($q$select count(*)::text from (select public.fn_grant_role(%L::uuid, 'viewer', null, null)) x$q$, 'aaaaaaaa-3000-0000-0000-000000000008'), 'ERR:BV346');
        perform pg_temp.expect('E16B control positivo: la dirección concede la gestión del equipo al área de Trabajo Social', DIR, 'authenticated',
            format(grantc, 'manage_team', 'null', format('%L::uuid', AR_TS), 'Delegación', null), '1');
        perform pg_temp.expect('E16B: ahora quien tiene rol operativo en Trabajo Social gestiona el equipo', CW, 'authenticated', format(hasc, 'manage_team'), 'true');
        perform pg_temp.expect('E16B: y la función del equipo se lo permite', CW, 'authenticated',
            format($q$select count(*)::text from (select public.fn_grant_role(%L::uuid, 'viewer', null, 'Delegado')) x$q$, 'aaaaaaaa-3000-0000-0000-000000000008'), '1');
        perform pg_temp.expect('E16B: el área jurídica no la recibió', CW_LG, 'authenticated', format(hasc, 'manage_team'), 'false');
        perform pg_temp.expect('E16B: quien recibe la gestión del equipo NO cambia permisos → BV353', CW, 'authenticated',
            format(grantc, 'view_audit', format('%L', 'viewer'), 'null', null, null), 'ERR:BV353');
        gid := (select id::text from public.capability_grant where capability_code = 'manage_team' and area_id = AR_TS::uuid and revoked_at is null);
        perform pg_temp.expect('E16B: quien recibe la gestión del equipo tampoco revoca permisos → BV353', CW, 'authenticated', format(revokec, gid, 'x'), 'ERR:BV353');
        perform pg_temp.expect('E16B control positivo: la dirección retira la delegación', DIR, 'authenticated', format(revokec, gid, 'Se centraliza'), '1');
        perform pg_temp.expect('E16B: Trabajo Social vuelve a no gestionar el equipo', CW, 'authenticated', format(hasc, 'manage_team'), 'false');

        -- ----- Requerimientos de autoridad y configuración de la organización
        perform pg_temp.expect('E16B prep: un requerimiento de autoridad de A (la fixture solo traía el de B)', null, null,
            format($q$with i as (insert into public.authority_request (organization_id, authority_name, request_type, official_letter_ref, received_at, extract_delivered) values (%L::uuid, 'Autoridad A', 'Consulta', 'A/0001', now(), false) returning 1) select count(*)::text from i$q$, ORG_A), '1');
        perform pg_temp.expect('E16B: antes, ingreso no lee requerimientos de autoridad', INT, 'authenticated', 'select count(*)::text from public.authority_request', '0');
        perform pg_temp.expect('E16B: la dirección concede los requerimientos de autoridad al rol de ingreso', DIR, 'authenticated',
            format(grantc, 'manage_authority_requests', format('%L', 'intake_officer'), 'null', null, null), '1');
        perform pg_temp.expect('E16B: ahora ingreso los lee', INT, 'authenticated', 'select (count(*) > 0)::text from public.authority_request', 'true');
        perform pg_temp.expect('E16B: antes, ingreso no configura la organización → BV109', INT, 'authenticated',
            'select count(*)::text from (select public.fn_update_organization_security_settings(true)) x', 'ERR:BV109');
        perform pg_temp.expect('E16B: la dirección concede la configuración al rol de ingreso', DIR, 'authenticated',
            format(grantc, 'manage_org_settings', format('%L', 'intake_officer'), 'null', null, null), '1');
        perform pg_temp.expect('E16B: ahora ingreso configura la organización', INT, 'authenticated',
            'select count(*)::text from (select public.fn_update_organization_security_settings(true)) x', '1');

        -- ----- Validaciones
        perform pg_temp.expect('E16B: una capacidad que no existe → BV349', DIR, 'authenticated',
            format(grantc, 'inventada', format('%L', 'viewer'), 'null', null, null), 'ERR:BV349');
        perform pg_temp.expect('E16B: hay que indicar un rol o un área, no ambos → BV350', DIR, 'authenticated',
            format(grantc, 'view_audit', format('%L', 'viewer'), format('%L::uuid', AR_TS), null, null), 'ERR:BV350');
        perform pg_temp.expect('E16B: ni ninguno → BV350', DIR, 'authenticated',
            format(grantc, 'view_audit', 'null', 'null', null, null), 'ERR:BV350');
        perform pg_temp.expect('E16B: un rol que no existe → BV350', DIR, 'authenticated',
            format(grantc, 'view_audit', format('%L', 'superadmin'), 'null', null, null), 'ERR:BV350');
        perform pg_temp.expect('E16B: un área de otra organización → BV350', DIR, 'authenticated',
            format(grantc, 'view_audit', 'null', format('%L::uuid', AR_B), null, null), 'ERR:BV350');
        perform pg_temp.expect('E16B: el rol de solo lectura no cambia permisos → BV353', VW, 'authenticated',
            format(grantc, 'view_audit', format('%L', 'viewer'), 'null', null, null), 'ERR:BV353');
        perform pg_temp.expect('E16B: otra organización no revoca asignaciones de A → BV352', DIRB2, 'authenticated',
            format(revokec, (select id::text from public.capability_grant where organization_id = ORG_A::uuid and revoked_at is null limit 1), 'x'), 'ERR:BV352');
        perform pg_temp.expect('E16B: los cambios de permisos quedan en la auditoría', null, null,
            $q$select (count(*) > 0)::text from public.audit_event where table_name = 'capability_grant' and created_at >= transaction_timestamp()$q$, 'true');

        -- ----- Salvaguarda: si una organización se queda sin ninguna concesión de una capacidad, aplica la dirección (no hay bloqueo)
        perform pg_temp.expect('E16B prep: se retiran todas las concesiones de la gestión del equipo en A (solo en la transacción de prueba)', null, null,
            format($q$with u as (update public.capability_grant set revoked_at = now() where organization_id = %L::uuid and capability_code = 'manage_team' and revoked_at is null returning 1) select (count(*) > 0)::text from u$q$, ORG_A), 'true');
        perform pg_temp.expect('E16B: sin concesiones, la dirección sigue gestionando el equipo (la organización no se bloquea)', DIR, 'authenticated', format(hasc, 'manage_team'), 'true');
        perform pg_temp.expect('E16B: y nadie más', CW, 'authenticated', format(hasc, 'manage_team'), 'false');
    end;

    -- ===== D-24 tanda 1: las tablas que solo se escriben por funciones no tienen políticas de escritura (eran inertes)
    foreach t in array array['user_role','user_profile','person','case','case_status','case_vulnerability_marker','consent','arco_request','journal_entry','privacy_notice','organization'] loop
        perform pg_temp.expect('D-24: ' || t || ' no tiene políticas de escritura', DIR, 'authenticated',
            format($q$select count(*)::text from pg_policies where schemaname = 'public' and tablename = %L and cmd <> 'SELECT'$q$, t), '0');
        perform pg_temp.expect('D-24: authenticated no puede insertar directo en ' || t, DIR, 'authenticated',
            format($q$select has_table_privilege('authenticated', 'public.%I', 'INSERT')::text$q$, t), case when t = 'organization' then 'true' else 'false' end);
        perform pg_temp.expect('D-24: authenticated no puede actualizar directo ' || t, DIR, 'authenticated',
            format($q$select has_table_privilege('authenticated', 'public.%I', 'UPDATE')::text$q$, t), 'false');
    end loop;
    perform pg_temp.expect('D-24: el director no actualiza personas con UPDATE directo', DIR, 'authenticated',
        $q$with u as (update public.person set id = id returning 1) select count(*)::text from u$q$, 'ERR|0');
    perform pg_temp.expect('D-24: el director no actualiza expedientes con UPDATE directo', DIR, 'authenticated',
        $q$with u as (update public.case set id = id returning 1) select count(*)::text from u$q$, 'ERR|0');
    perform pg_temp.expect('D-24: el director no inserta organizaciones con INSERT directo', DIR, 'authenticated',
        $q$with i as (insert into public.organization (display_name) values ('Directa') returning 1) select count(*)::text from i$q$, 'ERR');

    -- ============================================================================================
    -- ===== D-24 tanda 2: administración como capacidades (migración 20261028000001)
    -- ===== manage_areas (áreas), manage_status_catalog (ejes y valores de estatus), manage_task_catalogs (categorías, áreas de
    -- ===== trabajo y tipos de tarea de expediente) y manage_task_settings (ajustes de operación). Por omisión, solo dirección.
    -- ============================================================================================
    declare
        AR_TS constant text := 'aaaaaaaa-1000-0000-0000-000000000001';
        AR_B  constant text := 'bbbbbbbb-1000-0000-0000-000000000001';
        grantc text := $q$select count(*)::text from (select public.fn_grant_capability(%L, %s, %s, %L)) x$q$;
        revokec text := $q$select count(*)::text from (select public.fn_revoke_capability(%L::uuid, %L)) x$q$;
        hasc text := $q$select public.has_capability(%L)::text$q$;
        c text;
        gid text;
        u_area text := $q$with u as (update public.area set name = name where id = %L::uuid returning 1) select count(*)::text from u$q$;
        u_axis text := $q$with u as (update public.status_axis set sort_order = sort_order where id = 'aaaaaaaa-2000-0000-0000-000000000005' returning 1) select count(*)::text from u$q$;
        u_val text := $q$with u as (update public.status_value set sort_order = sort_order where id = 'aaaaaaaa-2100-0000-0000-000000000001' returning 1) select count(*)::text from u$q$;
        u_cat text := $q$with u as (update public.task_category set label_es = label_es where archived_at is null returning 1) select (count(*) > 0)::text from u$q$;
        u_wa text := $q$with u as (update public.work_area set label_es = label_es where archived_at is null returning 1) select (count(*) > 0)::text from u$q$;
        u_kind text := $q$with u as (update public.case_task_kind set label_es = label_es where archived_at is null returning 1) select (count(*) > 0)::text from u$q$;
        i_cat text := $q$with i as (insert into public.task_category (organization_id, key, label_es) values ('aaaaaaaa-0000-0000-0000-00000000000a', 'cat_d24', 'D24') returning 1) select count(*)::text from i$q$;
        setting text := $q$select count(*)::text from (select public.fn_update_task_setting('all', 30, 0, 1)) x$q$;
    begin
        -- ----- Por omisión, como estaba: solo dirección
        foreach c in array array['manage_areas','manage_status_catalog','manage_task_catalogs','manage_task_settings'] loop
            perform pg_temp.expect('D-24 t2: dirección tiene ' || c || ' por omisión', DIR, 'authenticated', format(hasc, c), 'true');
            perform pg_temp.expect('D-24 t2: la dirección de otra organización también tiene la suya (' || c || ')', DIRB2, 'authenticated', format(hasc, c), 'true');
            perform pg_temp.expect('D-24 t2: Trabajo Social no tiene ' || c || ' por omisión', CW, 'authenticated', format(hasc, c), 'false');
            perform pg_temp.expect('D-24 t2: ingreso no tiene ' || c || ' por omisión', INT, 'authenticated', format(hasc, c), 'false');
        end loop;

        -- ----- Antes de delegar, ingreso no administra nada
        perform pg_temp.expect('D-24 t2: ingreso no cambia áreas', INT, 'authenticated', format(u_area, AR_TS), 'ERR|0');
        perform pg_temp.expect('D-24 t2: ingreso no cambia ejes de estatus', INT, 'authenticated', u_axis, 'ERR|0');
        perform pg_temp.expect('D-24 t2: ingreso no cambia valores de estatus', INT, 'authenticated', u_val, 'ERR|0');
        perform pg_temp.expect('D-24 t2: ingreso no cambia categorías de tareas', INT, 'authenticated', u_cat, 'ERR|false');
        perform pg_temp.expect('D-24 t2: ingreso no cambia áreas de trabajo', INT, 'authenticated', u_wa, 'ERR|false');
        perform pg_temp.expect('D-24 t2: ingreso no cambia tipos de tarea de expediente', INT, 'authenticated', u_kind, 'ERR|false');
        perform pg_temp.expect('D-24 t2: ingreso no inserta categorías de tareas', INT, 'authenticated', i_cat, 'ERR');
        perform pg_temp.expect('D-24 t2: ingreso no cambia los ajustes de operación → TK010', INT, 'authenticated', setting, 'ERR:TK010');
        perform pg_temp.expect('D-24 t2: la dirección sigue administrando (control positivo de áreas)', DIR, 'authenticated', format(u_area, AR_TS), '1');
        perform pg_temp.expect('D-24 t2: la dirección sigue administrando (control positivo de estatus)', DIR, 'authenticated', u_val, '1');
        perform pg_temp.expect('D-24 t2: la dirección sigue administrando (control positivo de tareas)', DIR, 'authenticated', u_cat, 'true');

        -- ----- Delegar a un ROL: ingreso recibe las cuatro
        foreach c in array array['manage_areas','manage_status_catalog','manage_task_catalogs','manage_task_settings'] loop
            perform pg_temp.expect('D-24 t2 control positivo: la dirección concede ' || c || ' al rol de ingreso', DIR, 'authenticated',
                format(grantc, c, format('%L', 'intake_officer'), 'null', 'Delegación de prueba'), '1');
        end loop;
        perform pg_temp.expect('D-24 t2: ahora ingreso cambia áreas', INT, 'authenticated', format(u_area, AR_TS), '1');
        perform pg_temp.expect('D-24 t2: ahora ingreso cambia ejes de estatus', INT, 'authenticated', u_axis, '1');
        perform pg_temp.expect('D-24 t2: ahora ingreso cambia valores de estatus', INT, 'authenticated', u_val, '1');
        perform pg_temp.expect('D-24 t2: ahora ingreso cambia categorías de tareas', INT, 'authenticated', u_cat, 'true');
        perform pg_temp.expect('D-24 t2: ahora ingreso cambia áreas de trabajo', INT, 'authenticated', u_wa, 'true');
        perform pg_temp.expect('D-24 t2: ahora ingreso cambia tipos de tarea de expediente', INT, 'authenticated', u_kind, 'true');
        perform pg_temp.expect('D-24 t2: ahora ingreso crea una categoría de tareas', INT, 'authenticated', i_cat, '1');
        perform pg_temp.expect('D-24 t2: ahora ingreso cambia los ajustes de operación', INT, 'authenticated', setting, '1');
        perform pg_temp.expect('D-24 t2: la delegación no cruza organizaciones (área de B)', INT, 'authenticated', format(u_area, AR_B), '0');
        perform pg_temp.expect('D-24 t2: delegar administración no da gestión del equipo', INT, 'authenticated', format(hasc, 'manage_team'), 'false');
        perform pg_temp.expect('D-24 t2: ni deja cambiar permisos → BV353', INT, 'authenticated',
            format(grantc, 'manage_areas', format('%L', 'viewer'), 'null', null), 'ERR:BV353');

        -- ----- Revocar devuelve la restricción
        gid := (select id::text from public.capability_grant where capability_code = 'manage_areas' and role_name = 'intake_officer' and revoked_at is null and organization_id = 'aaaaaaaa-0000-0000-0000-00000000000a'::uuid);
        perform pg_temp.expect('D-24 t2 control positivo: se revoca con motivo', DIR, 'authenticated', format(revokec, gid, 'Prueba terminada'), '1');
        perform pg_temp.expect('D-24 t2: ingreso vuelve a no cambiar áreas', INT, 'authenticated', format(u_area, AR_TS), 'ERR|0');
        perform pg_temp.expect('D-24 t2: pero conserva lo que no se revocó (estatus)', INT, 'authenticated', u_val, '1');

        -- ----- Delegar a un ÁREA: Trabajo Social recibe los catálogos de tareas
        perform pg_temp.expect('D-24 t2: antes, Trabajo Social no cambia categorías', CW, 'authenticated', u_cat, 'ERR|false');
        perform pg_temp.expect('D-24 t2 control positivo: la dirección concede los catálogos de tareas al área de Trabajo Social', DIR, 'authenticated',
            format(grantc, 'manage_task_catalogs', 'null', format('%L', AR_TS), 'Prueba de área'), '1');
        perform pg_temp.expect('D-24 t2: ahora Trabajo Social cambia categorías', CW, 'authenticated', u_cat, 'true');
        perform pg_temp.expect('D-24 t2: sin recibir los ajustes de operación → TK010', CW, 'authenticated', setting, 'ERR:TK010');

        -- ----- Quien administra los catálogos de tareas ve también lo archivado (para poder desarchivar)
        perform pg_temp.expect('D-24 t2: la dirección archiva las áreas de trabajo', DIR, 'authenticated',
            $q$with u as (update public.work_area set archived_at = now() returning 1) select (count(*) > 0)::text from u$q$, 'true');
        perform pg_temp.expect('D-24 t2: ingreso, con el permiso, ve las áreas de trabajo archivadas', INT, 'authenticated',
            'select (count(*) > 0)::text from public.work_area where archived_at is not null', 'true');
        perform pg_temp.expect('D-24 t2: el rol de solo lectura no las ve', VW, 'authenticated',
            'select count(*)::text from public.work_area where archived_at is not null', '0');

        -- ----- Quien nunca recibió nada sigue sin poder
        perform pg_temp.expect('D-24 t2: el rol de solo lectura no cambia estatus', VW, 'authenticated', u_val, 'ERR|0');
        perform pg_temp.expect('D-24 t2: sin rol no se cambia nada', NR, 'authenticated', format(u_area, AR_TS), 'ERR|0');
        perform pg_temp.expect('D-24 t2: anon no cambia áreas', null, 'anon', format(u_area, AR_TS), 'ERR|0');
    end;

    -- ============================================================================================
    -- ===== D-24 tanda 3: operación como capacidades (migración 20261029000001)
    -- ===== open_cases (abrir expedientes y subfolios), rectify_person_data (rectificar datos y registrar la religión) y
    -- ===== change_legal_status (cambiar el estatus jurídico). Por omisión, como estaba: dirección e ingreso abren y rectifican;
    -- ===== dirección y el área jurídica cambian el estatus jurídico. Cerrar y reabrir el expediente siguen siendo de dirección.
    -- ============================================================================================
    declare
        CW_LG constant text := 'aaaaaaaa-3000-0000-0000-00000000000a';   -- área jurídica
        AR_LG constant text := 'aaaaaaaa-1000-0000-0000-000000000002';
        grantc text := $q$select count(*)::text from (select public.fn_grant_capability(%L, %s, %s, %L)) x$q$;
        revokec text := $q$select count(*)::text from (select public.fn_revoke_capability(%L::uuid, %L)) x$q$;
        hasc text := $q$select public.has_capability(%L)::text$q$;
        rect text := $q$select count(*)::text from (select public.fn_rectify_person(%L::uuid,'Eta','Rectificable',null,null,date '1985-03-04',false,null,null,null,null,'Prueba D-24')) x$q$;
        relig text := $q$select count(*)::text from (select public.fn_set_person_religion(%L::uuid, null, null, null)) x$q$;
        legal text := $q$select count(*)::text from (select public.fn_change_case_status(%L::uuid, 'legal_status', 'asylum_seeker', 'Prueba D-24')) x$q$;
        closing text := $q$select count(*)::text from (select public.fn_change_case_status(%L::uuid, 'record_status', 'closed', 'Prueba D-24')) x$q$;
        gid text;
        P6 text;
        C3 text;
    begin
        P6 := pg_temp.id('4000', 6);
        C3 := pg_temp.id('5000', 3);

        -- ----- Por omisión, como estaba
        perform pg_temp.expect('D-24 t3: dirección abre expedientes por omisión', DIR, 'authenticated', format(hasc, 'open_cases'), 'true');
        perform pg_temp.expect('D-24 t3: ingreso abre expedientes por omisión', INT, 'authenticated', format(hasc, 'open_cases'), 'true');
        perform pg_temp.expect('D-24 t3: atención no abre expedientes por omisión', CW, 'authenticated', format(hasc, 'open_cases'), 'false');
        perform pg_temp.expect('D-24 t3: el rol de solo lectura no abre expedientes', VW, 'authenticated', format(hasc, 'open_cases'), 'false');
        perform pg_temp.expect('D-24 t3: dirección rectifica datos por omisión', DIR, 'authenticated', format(hasc, 'rectify_person_data'), 'true');
        perform pg_temp.expect('D-24 t3: ingreso rectifica datos por omisión', INT, 'authenticated', format(hasc, 'rectify_person_data'), 'true');
        perform pg_temp.expect('D-24 t3: atención no rectifica datos por omisión', CW, 'authenticated', format(hasc, 'rectify_person_data'), 'false');
        perform pg_temp.expect('D-24 t3: dirección cambia el estatus jurídico por omisión', DIR, 'authenticated', format(hasc, 'change_legal_status'), 'true');
        perform pg_temp.expect('D-24 t3: el área jurídica cambia el estatus jurídico por omisión', CW_LG, 'authenticated', format(hasc, 'change_legal_status'), 'true');
        perform pg_temp.expect('D-24 t3: Trabajo Social no cambia el estatus jurídico por omisión', CW, 'authenticated', format(hasc, 'change_legal_status'), 'false');
        perform pg_temp.expect('D-24 t3: ingreso no cambia el estatus jurídico por omisión', INT, 'authenticated', format(hasc, 'change_legal_status'), 'false');
        perform pg_temp.expect('D-24 t3: la dirección de otra organización también las tiene', DIRB2, 'authenticated', format(hasc, 'open_cases'), 'true');

        -- ----- Lo que ya se rechazaba se sigue rechazando con el mismo código
        perform pg_temp.expect('D-24 t3: atención no abre expedientes → BV113', CW, 'authenticated', new_case, 'ERR:BV113');
        perform pg_temp.expect('D-24 t3: atención no rectifica → BV119', CW, 'authenticated', format(rect, P6), 'ERR:BV119');
        perform pg_temp.expect('D-24 t3: atención no registra la religión → BV121', CW, 'authenticated', format(relig, P6), 'ERR:BV121');
        perform pg_temp.expect('D-24 t3: Trabajo Social no cambia el estatus jurídico → BV110', CW, 'authenticated', format(legal, C3), 'ERR:BV110');
        perform pg_temp.expect('D-24 t3: ingreso no cambia el estatus jurídico → BV110', INT, 'authenticated', format(legal, C3), 'ERR:BV110');
        perform pg_temp.expect('D-24 t3: control positivo: ingreso rectifica', INT, 'authenticated', format(rect, P6), '1');

        -- ----- Delegar a un ROL: atención recibe las tres
        perform pg_temp.expect('D-24 t3 control positivo: la dirección concede abrir expedientes a atención', DIR, 'authenticated',
            format(grantc, 'open_cases', format('%L', 'caseworker'), 'null', 'Delegación de prueba'), '1');
        perform pg_temp.expect('D-24 t3 control positivo: la dirección concede rectificar a atención', DIR, 'authenticated',
            format(grantc, 'rectify_person_data', format('%L', 'caseworker'), 'null', 'Delegación de prueba'), '1');
        perform pg_temp.expect('D-24 t3 control positivo: la dirección concede el estatus jurídico a atención', DIR, 'authenticated',
            format(grantc, 'change_legal_status', format('%L', 'caseworker'), 'null', 'Delegación de prueba'), '1');
        -- Con el permiso, la función ya no responde BV113: llega a las demás reglas del alta (aquí, la ocupación obligatoria de la ficha)
        perform pg_temp.expect('D-24 t3: ahora atención abre expedientes (ya no BV113)', CW, 'authenticated', new_case, '1|ERR:BV339');
        perform pg_temp.expect('D-24 t3: ahora atención rectifica', CW, 'authenticated', format(rect, P6), '1');
        perform pg_temp.expect('D-24 t3: ahora atención registra la religión', CW, 'authenticated', format(relig, P6), '1');
        perform pg_temp.expect('D-24 t3: ahora atención cambia el estatus jurídico', CW, 'authenticated', format(legal, C3), '1');
        perform pg_temp.expect('D-24 t3: delegar el estatus jurídico no deja cerrar el expediente → BV111', CW, 'authenticated', format(closing, C3), 'ERR:BV111');
        perform pg_temp.expect('D-24 t3: el rol de solo lectura sigue sin poder abrir → BV113', VW, 'authenticated', new_case, 'ERR:BV113');
        perform pg_temp.expect('D-24 t3: delegar no da gestión del equipo', CW, 'authenticated', format(hasc, 'manage_team'), 'false');

        -- ----- Revocar devuelve la restricción
        gid := (select id::text from public.capability_grant where capability_code = 'open_cases' and role_name = 'caseworker' and revoked_at is null and organization_id = 'aaaaaaaa-0000-0000-0000-00000000000a'::uuid);
        perform pg_temp.expect('D-24 t3 control positivo: se revoca con motivo', DIR, 'authenticated', format(revokec, gid, 'Prueba terminada'), '1');
        perform pg_temp.expect('D-24 t3: atención vuelve a no abrir expedientes → BV113', CW, 'authenticated', new_case, 'ERR:BV113');
        perform pg_temp.expect('D-24 t3: y conserva lo que no se revocó (rectificar)', CW, 'authenticated', format(rect, P6), '1');

        -- ----- El estatus jurídico: quitarlo al rol lo devuelve al área jurídica, que lo tiene por omisión
        gid := (select id::text from public.capability_grant where capability_code = 'change_legal_status' and role_name = 'caseworker' and revoked_at is null and organization_id = 'aaaaaaaa-0000-0000-0000-00000000000a'::uuid);
        perform pg_temp.expect('D-24 t3 control positivo: se retira el estatus jurídico al rol de atención', DIR, 'authenticated', format(revokec, gid, 'Prueba terminada'), '1');
        perform pg_temp.expect('D-24 t3: Trabajo Social vuelve a no poder → BV110', CW, 'authenticated', format(legal, C3), 'ERR:BV110');
        perform pg_temp.expect('D-24 t3: el área jurídica sigue pudiendo', CW_LG, 'authenticated', format(hasc, 'change_legal_status'), 'true');
    end;

    -- ============================================================================================
    -- ===== E16 fase C: invitar personas (ADR-0010; migración 20261030000001)
    -- ===== La regla vive en la base: `fn_prepare_invitation` con la sesión de quien invita (capacidad manage_team) y
    -- ===== `fn_complete_invitation` solo para la llave de servicio. Invitar no concede ningún rol.
    -- ============================================================================================
    declare
        prep text := $q$select (public.fn_prepare_invitation(%L, %L))::text$q$;
        prep_resend text := $q$select (public.fn_prepare_invitation(%L, %L)->>'resend')$q$;
        comp text := $q$select count(*)::text from (select public.fn_complete_invitation(%L::uuid, %L::uuid)) x$q$;
        grantc text := $q$select count(*)::text from (select public.fn_grant_capability(%L, %s, %s, %L)) x$q$;
        revokec text := $q$select count(*)::text from (select public.fn_revoke_capability(%L::uuid, %L)) x$q$;
        NEWU constant text := 'aaaaaaaa-3000-0000-0000-0000000000f1';
        NEWU2 constant text := 'aaaaaaaa-3000-0000-0000-0000000000f2';
        inv text;
        inv2 text;
        gid text;
        i int;
    begin
        -- ----- Quién puede invitar
        perform pg_temp.expect('E16C: atención no invita → BV346', CW, 'authenticated', format(prep, 'nueva@tst-a.invalid', 'Nueva Persona'), 'ERR:BV346');
        perform pg_temp.expect('E16C: el rol de solo lectura no invita → BV346', VW, 'authenticated', format(prep, 'nueva@tst-a.invalid', 'Nueva Persona'), 'ERR:BV346');
        perform pg_temp.expect('E16C: una cuenta sin rol no invita → BV346', NR, 'authenticated', format(prep, 'nueva@tst-a.invalid', 'Nueva Persona'), 'ERR:BV346');
        perform pg_temp.expect('E16C: anon no invita', null, 'anon', format(prep, 'nueva@tst-a.invalid', 'Nueva Persona'), 'ERR');

        -- ----- Datos válidos
        perform pg_temp.expect('E16C: un correo sin forma de correo → BV354', DIR, 'authenticated', format(prep, 'sin-arroba', 'Nueva Persona'), 'ERR:BV354');
        perform pg_temp.expect('E16C: un correo vacío → BV354', DIR, 'authenticated', format(prep, '   ', 'Nueva Persona'), 'ERR:BV354');
        perform pg_temp.expect('E16C: sin nombre → BV355', DIR, 'authenticated', format(prep, 'nueva@tst-a.invalid', '  '), 'ERR:BV355');
        perform pg_temp.expect('E16C: un nombre de más de 120 caracteres → BV355', DIR, 'authenticated', format(prep, 'nueva@tst-a.invalid', repeat('x', 121)), 'ERR:BV355');
        perform pg_temp.expect('E16C: un correo que ya tiene cuenta en la organización → BV356', DIR, 'authenticated', format(prep, 'cw@tst-a.invalid', 'Otra'), 'ERR:BV356');
        perform pg_temp.expect('E16C: ni con otras mayúsculas → BV356', DIR, 'authenticated', format(prep, 'CW@Tst-A.invalid', 'Otra'), 'ERR:BV356');
        perform pg_temp.expect('E16C: un correo de otra organización responde igual (no revela de quién es) → BV356', DIR, 'authenticated', format(prep, 'dir@tst-b.invalid', 'Otra'), 'ERR:BV356');
        perform pg_temp.expect('E16C: nada de lo rechazado dejó invitaciones', null, null, 'select count(*)::text from public.user_invitation', '0');

        -- ----- Invitar (control positivo); el correo se guarda en minúsculas y la organización sale de la sesión
        perform pg_temp.expect('E16C control positivo: la dirección prepara una invitación', DIR, 'authenticated',
            format(prep_resend, 'Nueva.Persona@TST-A.invalid', 'Nueva Persona'), 'false');
        inv := (select id::text from public.user_invitation where email = 'nueva.persona@tst-a.invalid');
        perform pg_temp.expect('E16C: queda registrada, con el correo en minúsculas', null, null,
            format($q$select count(*)::text from public.user_invitation where id = %L::uuid and email = 'nueva.persona@tst-a.invalid' and full_name = 'Nueva Persona' and completed_at is null$q$, inv), '1');
        perform pg_temp.expect('E16C: queda en la organización y a nombre de quien invita', null, null,
            format($q$select count(*)::text from public.user_invitation where id = %L::uuid and organization_id = %L::uuid and invited_by = %L::uuid$q$, inv, ORG_A, DIR), '1');
        perform pg_temp.expect('E16C: la dirección de otra organización invita y queda en la suya (la petición no trae organización)', DIRB2, 'authenticated',
            format(prep_resend, 'nueva.b@tst-b.invalid', 'Nueva B'), 'false');
        perform pg_temp.expect('E16C: la invitación de B no cae en A', null, null,
            $q$select organization_id::text from public.user_invitation where email = 'nueva.b@tst-b.invalid'$q$, 'bbbbbbbb-0000-0000-0000-00000000000b');
        perform pg_temp.expect('E16C: invitar no concede ningún rol', null, null,
            $q$select count(*)::text from public.user_role ur join public.user_profile up on up.id = ur.user_id where up.email = 'nueva.persona@tst-a.invalid'$q$, '0');
        perform pg_temp.expect('E16C: la invitación deja huella en la auditoría', null, null,
            $q$select (count(*) > 0)::text from public.audit_event where table_name = 'user_invitation'$q$, 'true');

        -- ----- Lectura y escritura directa
        perform pg_temp.expect('E16C: la dirección ve las invitaciones de su organización', DIR, 'authenticated', 'select (count(*) > 0)::text from public.user_invitation', 'true');
        perform pg_temp.expect('E16C: quien no gestiona el equipo no las ve', CW, 'authenticated', 'select count(*)::text from public.user_invitation', '0');
        perform pg_temp.expect('E16C: otra organización no ve las de A', DIRB2, 'authenticated',
            format($q$select count(*)::text from public.user_invitation where organization_id = %L::uuid$q$, ORG_A), '0');
        perform pg_temp.expect('E16C: no se escriben por la API directa (INSERT)', DIR, 'authenticated',
            format($q$with i as (insert into public.user_invitation (organization_id, email, full_name, invited_by) values (%L::uuid, 'directa@tst-a.invalid', 'Directa', %L::uuid) returning 1) select count(*)::text from i$q$, ORG_A, DIR), 'ERR');
        perform pg_temp.expect('E16C: ni por la API directa (UPDATE)', DIR, 'authenticated',
            $q$with u as (update public.user_invitation set full_name = 'Cambiada' returning 1) select count(*)::text from u$q$, 'ERR|0');
        perform pg_temp.expect('E16C: ni se borran', DIR, 'authenticated',
            $q$with d as (delete from public.user_invitation returning 1) select count(*)::text from d$q$, 'ERR');

        -- ----- Completar: solo la llave de servicio
        insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at) values
            (NEWU::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'nueva.persona@tst-a.invalid', now(), now());
        perform pg_temp.expect('E16C: la dirección no completa invitaciones (solo la llave de servicio)', DIR, 'authenticated', format(comp, inv, NEWU), 'ERR');
        perform pg_temp.expect('E16C: anon tampoco', null, 'anon', format(comp, inv, NEWU), 'ERR');
        perform pg_temp.expect('E16C: una invitación que no existe → BV358', null, 'service_role', format(comp, '00000000-0000-0000-0000-0000000000aa', NEWU), 'ERR:BV358');
        perform pg_temp.expect('E16C control positivo: la llave de servicio completa la invitación', null, 'service_role', format(comp, inv, NEWU), '1');
        perform pg_temp.expect('E16C: crea el perfil en la organización de la invitación, activo, con el correo y el nombre', null, null,
            format($q$select count(*)::text from public.user_profile where id = %L::uuid and organization_id = %L::uuid and active and email = 'nueva.persona@tst-a.invalid' and full_name = 'Nueva Persona'$q$, NEWU, ORG_A), '1');
        perform pg_temp.expect('E16C: la invitación queda completada y ligada a la cuenta', null, null,
            format($q$select count(*)::text from public.user_invitation where id = %L::uuid and completed_at is not null and user_id = %L::uuid$q$, inv, NEWU), '1');
        perform pg_temp.expect('E16C: completarla otra vez → BV358', null, 'service_role', format(comp, inv, NEWU), 'ERR:BV358');
        perform pg_temp.expect('E16C: la persona invitada entra sin ningún rol', null, null,
            format($q$select count(*)::text from public.user_role where user_id = %L::uuid$q$, NEWU), '0');
        perform pg_temp.expect('E16C: y sin ninguna capacidad', NEWU, 'authenticated', 'select public.has_capability(''manage_team'')::text', 'false');
        perform pg_temp.expect('E16C: ni ve expedientes', NEWU, 'authenticated', 'select count(*)::text from public."case"', '0');
        perform pg_temp.expect('E16C: ni las invitaciones', NEWU, 'authenticated', 'select count(*)::text from public.user_invitation', '0');
        perform pg_temp.expect('E16C: la dirección ya ve a la persona nueva en su equipo', DIR, 'authenticated',
            format($q$select count(*)::text from public.user_profile where id = %L::uuid$q$, NEWU), '1');
        perform pg_temp.expect('E16C: y le puede otorgar un rol con lo que ya existe', DIR, 'authenticated',
            format($q$select count(*)::text from (select public.fn_grant_role(%L::uuid, 'viewer', null, 'Alta')) x$q$, NEWU), '1');

        -- ----- Reenviar: solo mientras la persona no haya aceptado la invitación
        perform pg_temp.expect('E16C: reenviar a quien aún no aceptó (la cuenta no está confirmada)', DIR, 'authenticated',
            format(prep_resend, 'nueva.persona@tst-a.invalid', 'Nueva Persona'), 'true');
        update auth.users set email_confirmed_at = now() where id = NEWU::uuid;
        perform pg_temp.expect('E16C: ya aceptó: no se reenvía → BV356', DIR, 'authenticated', format(prep, 'nueva.persona@tst-a.invalid', 'Nueva Persona'), 'ERR:BV356');

        -- ----- Delegar el permiso
        perform pg_temp.expect('E16C: antes, atención no invita → BV346', CW, 'authenticated', format(prep, 'delegada@tst-a.invalid', 'Delegada'), 'ERR:BV346');
        perform pg_temp.expect('E16C control positivo: la dirección delega la gestión del equipo a atención', DIR, 'authenticated',
            format(grantc, 'manage_team', format('%L', 'caseworker'), 'null', 'Prueba'), '1');
        perform pg_temp.expect('E16C: ahora atención invita', CW, 'authenticated', format(prep_resend, 'delegada@tst-a.invalid', 'Delegada'), 'false');
        perform pg_temp.expect('E16C: queda a nombre de quien invitó', null, null,
            format($q$select count(*)::text from public.user_invitation where email = 'delegada@tst-a.invalid' and invited_by = %L::uuid$q$, CW), '1');
        gid := (select id::text from public.capability_grant where capability_code = 'manage_team' and role_name = 'caseworker' and revoked_at is null and organization_id = ORG_A::uuid);
        perform pg_temp.expect('E16C control positivo: se revoca', DIR, 'authenticated', format(revokec, gid, 'Prueba terminada'), '1');
        perform pg_temp.expect('E16C: atención vuelve a no invitar → BV346', CW, 'authenticated', format(prep, 'otra.delegada@tst-a.invalid', 'Otra'), 'ERR:BV346');

        -- ----- Tope por hora y por persona
        for i in 1..20 loop
            perform pg_temp.run_as(DIRA2, 'authenticated', format(prep, 'tope' || i || '@tst-a.invalid', 'Persona ' || i));
        end loop;
        perform pg_temp.expect('E16C: la invitación 21 en una hora → BV357', DIRA2, 'authenticated', format(prep, 'tope21@tst-a.invalid', 'Persona 21'), 'ERR:BV357');
        perform pg_temp.expect('E16C: el tope es por persona: otra dirección sigue pudiendo', DIR, 'authenticated', format(prep_resend, 'otra.persona@tst-a.invalid', 'Otra Persona'), 'false');
        update public.user_invitation set invited_at = now() - interval '2 hours' where invited_by = DIRA2::uuid;
        perform pg_temp.expect('E16C: con las invitaciones de hace dos horas, vuelve a poder', DIRA2, 'authenticated', format(prep_resend, 'tope22@tst-a.invalid', 'Persona 22'), 'false');
    end;

    -- ============================================================================================
    -- ===== D-24 tanda 4 (cierre): lo único que sigue por nombre de rol son las garantías del producto
    -- ===== Cualquier comprobación nueva por nombre de rol hace fallar esta prueba: hay que decidir si es una garantía (y
    -- ===== añadirla aquí, con su razón en la propuesta de E16 §9) o un permiso (y entonces es una capacidad).
    -- ============================================================================================
    perform pg_temp.expect('D-24: las funciones que comprueban roles por nombre son solo las garantías conocidas', DIR, 'authenticated',
        $q$select string_agg(p.proname, ',' order by p.proname) from pg_proc p join pg_namespace s on s.oid = p.pronamespace
           where s.nspname = 'public' and p.prosrc ~ 'has_role(_in_area)?\('$q$,
        'fn_acknowledge_sharing,fn_anonymize_person,fn_apply_opposition,fn_can_act_on_entry,fn_change_case_status,fn_create_journal_entry,fn_generate_arco_access_extract,fn_grant_capability,fn_prevent_update_journal_entry,fn_read_case_detail,fn_revoke_capability,has_capability');
    perform pg_temp.expect('D-24: las políticas que comprueban roles por nombre son solo las de lectura compartimentada', DIR, 'authenticated',
        $q$select string_agg(tablename || '.' || policyname, ',' order by tablename, policyname) from pg_policies
           where schemaname in ('public', 'storage') and (coalesce(qual, '') || coalesce(with_check, '')) ~ 'has_role(_in_area)?\('$q$,
        'arco_request.arco_request_select_policy,attachment.attachment_select_policy,capability_grant.capability_grant_select,journal_entry.journal_entry_select_policy,sharing_event.sharing_event_select_policy');

    -- ===== Ultima: la anonimización es exclusiva de dirección y funciona (irreversible, en transacción de prueba)
    perform pg_temp.expect('control positivo: director anonimiza', DIR, 'authenticated',
        'select count(*)::text from (select public.fn_anonymize_person(''aaaaaaaa-4000-0000-0000-000000000001''::uuid, ''Prueba'')) x', '1');

    perform pg_temp.expect('el folio sigue en la tarea tras anonimizar a la persona', null, null,
        pg_temp.q('select case_number from public.task where case_id = {CASEA} and assigned_to = {VOL}'), 'TST-A-0001');
    perform pg_temp.expect('el voluntariado sigue viendo el folio tras anonimizar a la persona', VOL, 'authenticated',
        pg_temp.q('select case_number from public.task where case_id = {CASEA}'), 'TST-A-0001');
    perform pg_temp.expect('el esqueleto del caso permanece tras anonimizar (el folio sigue siendo válido)', null, null,
        pg_temp.q('select case_number from public."case" where id = {CASEA}'), 'TST-A-0001');

    -- ===== C-2 / C7: tras anonimizar, nada identificable sobrevive en la persona ni en el log
    perform pg_temp.expect('C-2: tras anonimizar, ningún evento de esta prueba conserva el apellido de la persona', null, null,
        $q$select count(*)::text from public.audit_event where created_at >= transaction_timestamp()
           and (coalesce(old_values::text, '') ilike '%pruebaa%' or coalesce(new_values::text, '') ilike '%pruebaa%')$q$, '0');
    perform pg_temp.expect('C-2: tras anonimizar, la fecha de nacimiento queda en el año (rango de edad, ADR-0001)', null, null,
        $q$select birth_date::text from public.person where id = 'aaaaaaaa-4000-0000-0000-000000000001'$q$, '1990-01-01');
    perform pg_temp.expect('C-2 control positivo: el evento de anonimización permanece y conserva el esqueleto', null, null,
        $q$select count(*)::text from public.audit_event where action = 'ANONYMIZATION' and record_id = 'aaaaaaaa-4000-0000-0000-000000000001'
           and created_at >= transaction_timestamp() and new_values ? 'retained_skeleton'$q$, '1');
    perform pg_temp.expect('A-3 control positivo: la anonimización por su función sí deja el estatus terminal', null, null,
        $q$select count(*)::text from public.case_status cs join public.status_value sv on sv.id = cs.value_id
           where cs.case_id = 'aaaaaaaa-5000-0000-0000-000000000001' and cs.valid_to is null and sv.code = 'anonymized'$q$, '2');

    -- ===== L-1: al anonimizar, los terceros de consentimientos y solicitudes ARCO quedan pseudonimizados
    perform pg_temp.expect('L-1: ningún nombre ni referencia de terceros sobrevive en los consentimientos', null, null,
        $q$select count(*)::text from public.consent where person_id = 'aaaaaaaa-4000-0000-0000-000000000001'
           and (legal_guardian_name ilike '%secreta%' or authority_letter_ref ilike '%secreto%' or notes ilike '%privada%')$q$, '0');
    perform pg_temp.expect('L-1: ningún dato de quien solicitó sobrevive en las solicitudes ARCO', null, null,
        $q$select count(*)::text from public.arco_request where person_id = 'aaaaaaaa-4000-0000-0000-000000000001'
           and (requested_by_name ilike '%secreto%' or details ilike '%secreto%' or reason ilike '%secreto%')$q$, '0');
    perform pg_temp.expect('L-1 control positivo: el consentimiento sigue como evidencia, con seudónimo en lugar del nombre', null, null,
        $q$select count(*)::text from public.consent where id = 'aaaaaaaa-8000-0000-0000-000000000001' and status = 'granted'
           and legal_guardian_name like 'REPRESENTANTE-%' and authority_letter_ref like 'REFERENCIA-%'$q$, '1');
    perform pg_temp.expect('L-1 control positivo: la solicitud ARCO sigue registrada, con seudónimo', null, null,
        $q$select count(*)::text from public.arco_request where person_id = 'aaaaaaaa-4000-0000-0000-000000000001' and requested_by_name like 'SOLICITANTE-%'$q$, '1');
    perform pg_temp.expect('L-1: ningún evento de auditoría de esta prueba conserva datos de terceros', null, null,
        $q$select count(*)::text from public.audit_event where created_at >= transaction_timestamp()
           and (coalesce(old_values::text, '') ilike '%secret%' or coalesce(new_values::text, '') ilike '%secret%')$q$, '0');

    -- ===== Endurecimiento Cybersec (Opción B, 14 oct 2026): D-05, D-12, RNF-04
    -- D-12: Auditoría de lectura de expediente individual
    perform pg_temp.expect('D-12: lectura de expediente anónimo → BV101', null, null,
        $q$select count(*)::text from (select public.fn_read_case_detail('aaaaaaaa-5000-0000-0000-000000000001'::uuid)) x$q$, 'ERR:BV101');
    perform pg_temp.expect('D-12: lectura de expediente con voluntariado → BV101', VOL, 'authenticated',
        $q$select count(*)::text from (select public.fn_read_case_detail('aaaaaaaa-5000-0000-0000-000000000001'::uuid)) x$q$, 'ERR:BV101');
    perform pg_temp.expect('D-12: lectura de expediente con coordinación de tareas → BV101', TM, 'authenticated',
        $q$select count(*)::text from (select public.fn_read_case_detail('aaaaaaaa-5000-0000-0000-000000000001'::uuid)) x$q$, 'ERR:BV101');
    perform pg_temp.expect('D-12: lectura de expediente de otra organización → BV203', DIRB2, 'authenticated',
        $q$select count(*)::text from (select public.fn_read_case_detail('aaaaaaaa-5000-0000-0000-000000000001'::uuid)) x$q$, 'ERR:BV203');
    perform pg_temp.expect('D-12 control positivo: trabajo social lee expediente de su organización', CW, 'authenticated',
        $q$select public.fn_read_case_detail('aaaaaaaa-5000-0000-0000-000000000001'::uuid)::text$q$, 'true');
    perform pg_temp.expect('D-12: la lectura de expediente dejó evento READ_CASE en auditoría', null, null,
        $q$select count(*)::text from public.audit_event where action = 'READ_CASE' and record_id = 'aaaaaaaa-5000-0000-0000-000000000001'$q$, '1');

    -- RNF-04: Configuración de seguridad de la organización (sesión absoluta configurable)
    perform pg_temp.expect('RNF-04: configurar seguridad de organización anónimo → BV109', null, null,
        $q$select count(*)::text from (select public.fn_update_organization_security_settings(false)) x$q$, 'ERR:BV109');
    perform pg_temp.expect('RNF-04: configurar seguridad de organización con caseworker → BV109', CW, 'authenticated',
        $q$select count(*)::text from (select public.fn_update_organization_security_settings(false)) x$q$, 'ERR:BV109');
    perform pg_temp.expect('RNF-04 control positivo: dirección actualiza timeout absoluto a false', DIR, 'authenticated',
        $q$select (public.fn_update_organization_security_settings(false) is not null)::text$q$, 'true');
    perform pg_temp.expect('RNF-04: la bandera quedó en false tras la actualización', null, null,
        $q$select enforce_absolute_session_timeout::text from public.organization where id = 'aaaaaaaa-0000-0000-0000-00000000000a'$q$, 'false');
    perform pg_temp.expect('RNF-04 control positivo: dirección restaura timeout absoluto a true', DIR, 'authenticated',
        $q$select (public.fn_update_organization_security_settings(true) is not null)::text$q$, 'true');

    -- D-05: Encadenamiento criptográfico e integridad del log
    perform pg_temp.expect('D-05: verificar cadena de auditoría anónimo → BV109', null, null,
        $q$select count(*)::text from (select * from public.fn_verify_audit_chain()) x$q$, 'ERR:BV109');
    perform pg_temp.expect('D-05: verificar cadena de auditoría con caseworker → BV109', CW, 'authenticated',
        $q$select count(*)::text from (select * from public.fn_verify_audit_chain()) x$q$, 'ERR:BV109');
    perform pg_temp.expect('D-05 control positivo: dirección verifica cadena íntegra de su organización', DIR, 'authenticated',
        $q$select is_valid::text from public.fn_verify_audit_chain()$q$, 'true');
    perform pg_temp.expect('D-05 control positivo: los eventos tienen hashes válidos', null, null,
        $q$select count(*)::text from public.audit_event where prev_hash is null or event_hash is null$q$, '0');

    -- ===== E14 fase 1: tras anonimizar, ni el documento, ni la religión, ni el detalle del marcador sobreviven
    perform pg_temp.expect('E14: tras anonimizar, ningún número de documento sobrevive', null, null,
        $q$select count(*)::text from public.person_document where person_id = 'aaaaaaaa-4000-0000-0000-000000000001'
           and (document_number ilike '%BORRAR%' or valid_to is null)$q$, '0');
    perform pg_temp.expect('E14 control positivo: el documento sigue como registro cerrado, sin número', null, null,
        $q$select count(*)::text from public.person_document where person_id = 'aaaaaaaa-4000-0000-0000-000000000001' and valid_to is not null$q$, '>0');
    perform pg_temp.expect('E14: tras anonimizar, la religión desaparece', null, null,
        $q$select coalesce(religion_item_id::text, 'NULO') || '/' || coalesce(religion_detail, 'NULO') || '/' || coalesce(primary_language_item_id::text, 'NULO') || '/' || coalesce(other_language, 'NULO')
           from public.person where id = 'aaaaaaaa-4000-0000-0000-000000000001'$q$, 'NULO/NULO/NULO/NULO');
    perform pg_temp.expect('E14: tras anonimizar, el detalle del marcador desaparece', null, null,
        $q$select count(*)::text from public.case_vulnerability_marker where case_id = 'aaaaaaaa-5000-0000-0000-000000000001' and notes is not null$q$, '0');
    perform pg_temp.expect('E14: el esqueleto sigue: el marcador permanece, sin detalle', null, null,
        $q$select count(*)::text from public.case_vulnerability_marker where case_id = 'aaaaaaaa-5000-0000-0000-000000000001' and marker_code = 'disability'$q$, '1');

    -- ===== E14 fase 2: las fechas del caso son parte del esqueleto del folio y sobreviven a la anonimización
    perform pg_temp.expect('F2: tras anonimizar, las fechas del caso permanecen (esqueleto estadístico)', null, null,
        $q$select count(*)::text from public.case_date where case_id = 'aaaaaaaa-5000-0000-0000-000000000001' and valid_to is null$q$, '1');

    -- ===== E14 fase 3: al anonimizar, la persona deja la familia (el folio de familia puede identificar a sus parientes)
    perform pg_temp.expect('F3: tras anonimizar, la persona ya no tiene familia vigente', null, null,
        $q$select count(*)::text from public.family_member where case_id = 'aaaaaaaa-5000-0000-0000-000000000001' and valid_to is null$q$, '0');
    perform pg_temp.expect('F3: la pertenencia sigue como registro cerrado, con el motivo suprimido', null, null,
        $q$select count(*)::text from public.family_member where case_id = 'aaaaaaaa-5000-0000-0000-000000000001' and valid_to is not null$q$, '1');

    -- ===== E14 fase 4b: al anonimizar se cierran las necesidades específicas (datos sensibles)
    perform pg_temp.expect('F4b: tras anonimizar, no queda ninguna necesidad vigente', null, null,
        $q$select count(*)::text from public.case_need where case_id = 'aaaaaaaa-5000-0000-0000-000000000001' and valid_to is null$q$, '0');
    perform pg_temp.expect('F4b: la necesidad queda como registro cerrado, con el motivo suprimido', null, null,
        $q$select count(*)::text from public.case_need where case_id = 'aaaaaaaa-5000-0000-0000-000000000001' and valid_to is not null and change_reason = '[SUPRIMIDO - ADR-0001]'$q$, '1');

    -- ===== E15 fase 1: al anonimizar, la ficha de la persona queda sin estudios, estado civil, departamento ni ocupación vigente
    perform pg_temp.expect('E15: tras anonimizar, la persona no conserva estudios, estado civil ni departamento', null, null,
        $q$select count(*)::text from public.person where id = 'aaaaaaaa-4000-0000-0000-000000000001'
           and (education_level_item_id is not null or marital_status_item_id is not null or origin_department_item_id is not null)$q$, '0');
    perform pg_temp.expect('E15: tras anonimizar, no queda ninguna ocupación vigente', null, null,
        $q$select count(*)::text from public.person_occupation where person_id = 'aaaaaaaa-4000-0000-0000-000000000001' and valid_to is null$q$, '0');
    perform pg_temp.expect('E15: la ocupación queda como registro cerrado, con el motivo suprimido', null, null,
        $q$select count(*)::text from public.person_occupation where person_id = 'aaaaaaaa-4000-0000-0000-000000000001' and valid_to is not null and change_reason = '[SUPRIMIDO - ADR-0001]'$q$, '1');

    -- ===== E15 fase 2: al anonimizar, las respuestas de la ficha social se cierran y su texto y detalle se suprimen
    perform pg_temp.expect('E15f2: tras anonimizar, no queda ninguna respuesta vigente de la ficha social', null, null,
        $q$select count(*)::text from public.social_answer where case_id = 'aaaaaaaa-5000-0000-0000-000000000001' and valid_to is null$q$, '0');
    perform pg_temp.expect('E15f2: las respuestas quedan como registro cerrado, sin texto ni detalle', null, null,
        $q$select (count(*) > 0 and bool_and(change_reason = '[SUPRIMIDO - ADR-0001]' and text_value is null and detail is null))::text
           from public.social_answer where case_id = 'aaaaaaaa-5000-0000-0000-000000000001' and valid_to is not null$q$, 'true');

    select string_agg(verdict || '^' || name || '^' || expected || '^' || actual, E'\n' order by verdict desc, name)
      into report from test_res;
    raise exception E'RLS_RESULTS\n%', report;
end
$do$;
