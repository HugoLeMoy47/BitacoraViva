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
        'Nuevo','Caso',null,null,date '2000-01-01',false,1,93,'Honduras',1,null,null,'fija',false,9,1,1,3,null,
        'aaaaaaaa-1000-0000-0000-000000000001'::uuid, array[]::text[], '[{"consent_type":"general_care"}]'::jsonb)) x$nc$;
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
        -- Los roles de tareas no reciben ninguna función del expediente (ADR-0007)
        perform pg_temp.expect('voluntariado no ejecuta ' || split_part(split_part(t, 'public.', 2), '(', 1), VOL, 'authenticated', t, 'ERR');
        perform pg_temp.expect('coordinación de tareas no ejecuta ' || split_part(split_part(t, 'public.', 2), '(', 1), TM, 'authenticated', t, 'ERR');
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
        w_int text := 'select count(*)::text from (select public.fn_register_consent(''aaaaaaaa-4000-0000-0000-000000000001''::uuid, ''internal_sharing'')) x';
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
        perform pg_temp.expect('TK006: el único director activo de A no puede desactivar su cuenta', DIRA2, 'authenticated',
            pg_temp.q('with u as (update public.user_profile set active = false where id = {DIRA2} returning 1) select count(*)::text from u'), 'ERR:TK006');

        -- Reactivar devuelve el acceso (las cuentas no quedan marcadas de forma permanente)
        foreach u in array array[DIR, CW, INT, VW] loop
            perform pg_temp.expect('se reactiva la cuenta ' || right(u, 1), null, null,
                format('with u as (update public.user_profile set active = true where id = %L returning 1) select count(*)::text from u', u), '1');
        end loop;
        perform pg_temp.expect('reactivada: el director vuelve a leer personas', DIR, 'authenticated', 'select count(*)::text from public.person', '>0');
        perform pg_temp.expect('reactivada: el caseworker vuelve a escribir en la bitácora', CW, 'authenticated', w_cw, '1');
    end;

    -- ===== Anónimo: nada
    perform pg_temp.expect('anon no lee personas', null, 'anon', 'select count(*)::text from public.person', 'ERR|0');
    perform pg_temp.expect('anon no abre casos', null, 'anon', new_case, 'ERR');
    perform pg_temp.expect('anon no lee app_config', null, 'anon', 'select count(*)::text from public.app_config', 'ERR');
    perform pg_temp.expect('authenticated no lee app_config', DIR, 'authenticated', 'select count(*)::text from public.app_config', 'ERR');
    perform pg_temp.expect('control positivo: anon consulta el entorno por función', null, 'anon', 'select public.fn_app_environment()', 'demo|production');

    -- ===== TK006: la organización no se queda sin dirección (se prueba aquí porque cambia a B)
    perform pg_temp.expect('el último director no puede revocar su propio rol', DIRB, 'authenticated',
        pg_temp.q('with u as (update public.user_role set revoked_at = now(), revoked_by = {DIRB} where user_id = {DIRB} and role_name = ''director'' returning 1) select count(*)::text from u'), 'ERR:TK006');
    perform pg_temp.expect('el último director no puede desactivar su cuenta', DIRB, 'authenticated',
        pg_temp.q('with u as (update public.user_profile set active = false where id = {DIRB} returning 1) select count(*)::text from u'), 'ERR:TK006');
    perform pg_temp.expect('se agrega un segundo director a B', null, null,
        pg_temp.q($q$with a as (insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
                               values ({DIRB2}, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'dir2@tst-b.invalid', now(), now()) returning id),
                          p as (insert into public.user_profile (id, organization_id, email, full_name, active)
                                select id, {ORGB}, 'dir2@tst-b.invalid', 'Dir B2', true from a returning id),
                          r as (insert into public.user_role (user_id, role_name, granted_by, granted_at)
                                select id, 'director', {DIRB}, now() from p returning 1)
                     select count(*)::text from r$q$), '1');
    perform pg_temp.expect('control positivo: con otro director vigente sí puede dejar su rol', DIRB, 'authenticated',
        pg_temp.q('with u as (update public.user_role set revoked_at = now(), revoked_by = {DIRB} where user_id = {DIRB} and role_name = ''director'' returning 1) select count(*)::text from u'), '1');
    perform pg_temp.expect('el director que queda ya no puede dejar su rol', DIRB2, 'authenticated',
        pg_temp.q('with u as (update public.user_role set revoked_at = now(), revoked_by = {DIRB2} where user_id = {DIRB2} and role_name = ''director'' returning 1) select count(*)::text from u'), 'ERR:TK006');

    -- ===== Ultima: la anonimización es exclusiva de dirección y funciona (irreversible, en transacción de prueba)
    perform pg_temp.expect('control positivo: director anonimiza', DIR, 'authenticated',
        'select count(*)::text from (select public.fn_anonymize_person(''aaaaaaaa-4000-0000-0000-000000000001''::uuid, ''Prueba'')) x', '1');

    perform pg_temp.expect('el folio sigue en la tarea tras anonimizar a la persona', null, null,
        pg_temp.q('select case_number from public.task where case_id = {CASEA} and assigned_to = {VOL}'), 'TST-A-0001');
    perform pg_temp.expect('el voluntariado sigue viendo el folio tras anonimizar a la persona', VOL, 'authenticated',
        pg_temp.q('select case_number from public.task where case_id = {CASEA}'), 'TST-A-0001');
    perform pg_temp.expect('el esqueleto del caso permanece tras anonimizar (el folio sigue siendo válido)', null, null,
        pg_temp.q('select case_number from public."case" where id = {CASEA}'), 'TST-A-0001');

    select string_agg(verdict || '^' || name || '^' || expected || '^' || actual, E'\n' order by verdict desc, name)
      into report from test_res;
    raise exception E'RLS_RESULTS\n%', report;
end
$do$;
