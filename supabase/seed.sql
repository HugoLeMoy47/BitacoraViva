-- ==============================================================================
-- Bitácora Viva — Seed Data para Entorno de Desarrollo y Pruebas
-- Albergue Demo: Albergue Santa Fe (Tenancy inicial)
-- ==============================================================================

-- 0. Etiqueta de entorno: este seed es exclusivo de DEMO y nunca se ejecuta en produccion.
-- La interfaz muestra el aviso de demo y el reinicio (npm run demo:reset) solo opera con este valor.
insert into public.app_config (key, value) values ('environment', 'demo')
on conflict (key) do update set value = excluded.value, updated_at = now();

-- 1. Organización de demostración
insert into public.organization (
    id, slug, legal_name, display_name, active, folio_prefix,
    responsible_name, responsible_address, responsible_contact, arco_contact
)
values (
    '00000000-0000-0000-0000-000000000001',
    'albergue-santa-fe',
    'Albergue Santa Fe A.C.',
    'Albergue Santa Fe',
    true,
    'ASF',
    'Dirección de Albergue Santa Fe A.C. (datos ficticios)',
    'Av. Independencia 450, Tuxtla Gutiérrez, Chiapas',
    'contacto@albergue-demo.invalid',
    'arco@albergue-demo.invalid'
) on conflict (id) do nothing;

-- 2. Áreas operativas del albergue
insert into public.area (id, organization_id, code, name, active)
values
    ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'trabajo_social', 'Trabajo Social', true),
    ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'legal', 'Atención Jurídica', true),
    ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'psicologia', 'Atención Psicosocial', true),
    ('10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001', 'medica', 'Salud y Primeros Auxilios', true),
    ('10000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000001', 'coordinacion', 'Coordinación General', true)
on conflict (id) do nothing;

-- 3. Cuentas de demostración en auth.users, user_profile y user_role
-- Passwords con hash bcrypt de 'albergue2026!'
do $$
declare
    v_org_id uuid := '00000000-0000-0000-0000-000000000001';
    v_user_dir uuid := 'a0000000-0000-0000-0000-000000000001';
    v_user_case uuid := 'a0000000-0000-0000-0000-000000000002';
    v_user_intk uuid := 'a0000000-0000-0000-0000-000000000003';
    v_user_view uuid := 'a0000000-0000-0000-0000-000000000004';
begin
    -- Crear usuarios auth si existen extensiones auth en local
    if exists (select 1 from information_schema.tables where table_schema = 'auth' and table_name = 'users') then
        insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change, email_change_token_new)
        values
            (v_user_dir, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'director@alberguesantafe.org', extensions.crypt('albergue2026!', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Elena Morales (Directora)"}', now(), now(), '', '', '', ''),
            (v_user_case, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'caseworker@alberguesantafe.org', extensions.crypt('albergue2026!', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Carlos Méndez (Trabajo Social)"}', now(), now(), '', '', '', ''),
            (v_user_intk, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'intake@alberguesantafe.org', extensions.crypt('albergue2026!', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Mariana Ríos (Oficial de Ingreso)"}', now(), now(), '', '', '', ''),
            (v_user_view, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'viewer@alberguesantafe.org', extensions.crypt('albergue2026!', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Dr. Roberto Soto (Observador/Auditor)"}', now(), now(), '', '', '', '')
        on conflict (id) do nothing;

        -- Identidades email (requeridas por GoTrue para login con password)
        insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
        select u.id, u.id, u.id::text, 'email', jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true), now(), now(), now()
        from auth.users u where u.id in (v_user_dir, v_user_case, v_user_intk, v_user_view)
        on conflict do nothing;

        -- Perfiles vinculados a la organización
        insert into public.user_profile (id, organization_id, email, full_name, active)
        values
            (v_user_dir, v_org_id, 'director@alberguesantafe.org', 'Elena Morales', true),
            (v_user_case, v_org_id, 'caseworker@alberguesantafe.org', 'Carlos Méndez', true),
            (v_user_intk, v_org_id, 'intake@alberguesantafe.org', 'Mariana Ríos', true),
            (v_user_view, v_org_id, 'viewer@alberguesantafe.org', 'Dr. Roberto Soto', true)
        on conflict (id) do nothing;

        -- Asignación de roles con área y trazabilidad
        insert into public.user_role (user_id, role_name, area_id, granted_by, granted_at)
        values
            (v_user_dir, 'director', null, v_user_dir, now()),
            (v_user_case, 'caseworker', '10000000-0000-0000-0000-000000000001', v_user_dir, now()),
            (v_user_intk, 'intake_officer', null, v_user_dir, now()),
            (v_user_view, 'viewer', null, v_user_dir, now())
        on conflict do nothing;

        -- Requerimiento de autoridad inicial de prueba (Ethos E-03)
        insert into public.authority_request (
            id,
            organization_id,
            authority_name,
            request_type,
            official_letter_ref,
            received_at,
            handled_by_user_id,
            response_summary,
            extract_delivered
        ) values (
            'd0000000-0000-0000-0000-000000000001',
            v_org_id,
            'Comisión Nacional de los Derechos Humanos (CNDH)',
            'Solicitud de información sobre medidas cautelares',
            'CNDH/2026/V4/7821',
            now() - interval '2 days',
            v_user_dir,
            'Requerimiento atendido institucionalmente fuera del sistema conforme a protocolo.',
            false
        ) on conflict (id) do nothing;
    end if;
end $$;

-- 4. Evento de auditoría inicial (Génesis del albergue)
insert into public.audit_event (
    id,
    organization_id,
    action,
    table_name,
    record_id,
    new_values
) values (
    'e0000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000001',
    'INSERT',
    'organization',
    '00000000-0000-0000-0000-000000000001',
    '{"event": "genesis_albergue_santa_fe", "commitments": "Ethos C1-C8 activados", "version": "v1.2"}'::jsonb
) on conflict (id) do nothing;

-- ==============================================================================
-- 5. Catálogos de Estatus Multidimensional (Épica E2)
-- ==============================================================================
do $$
declare
    v_org uuid := '00000000-0000-0000-0000-000000000001';
    v_ax_leg uuid := '20000000-0000-0000-0000-000000000001';
    v_ax_eng uuid := '20000000-0000-0000-0000-000000000002';
    v_ax_she uuid := '20000000-0000-0000-0000-000000000003';
    v_ax_rec uuid := '20000000-0000-0000-0000-000000000004';
    v_ax_stg uuid := '20000000-0000-0000-0000-000000000005';
begin
    -- Ejes normativos
    insert into public.status_axis (id, organization_id, code, label_es, is_primary, is_system, sort_order)
    values
        (v_ax_leg, v_org, 'legal_status', 'Situación Jurídico-Migratoria', false, true, 1),
        (v_ax_eng, v_org, 'engagement_status', 'Situación ante la Organización', true, true, 2),
        (v_ax_she, v_org, 'shelter_status', 'Situación de Alojamiento', false, true, 3),
        (v_ax_rec, v_org, 'record_status', 'Estado Administrativo', false, true, 4),
        (v_ax_stg, v_org, 'case_stage', 'Etapa de Gestión de Caso', false, true, 5)
    on conflict (id) do nothing;

    -- Valores: legal_status
    insert into public.status_value (axis_id, organization_id, code, label_es, sort_order, is_system)
    values
        (v_ax_leg, v_org, 'undetermined', 'Sin determinar', 1, true),
        (v_ax_leg, v_org, 'asylum_seeker', 'Solicitante de asilo / refugio', 2, false),
        (v_ax_leg, v_org, 'recognized_refugee', 'Persona refugiada reconocida', 3, false),
        (v_ax_leg, v_org, 'humanitarian_visa', 'Visitante por razones humanitarias (TVRH)', 4, false),
        (v_ax_leg, v_org, 'irregular_situation', 'Situación migratoria irregular', 5, false),
        (v_ax_leg, v_org, 'returnee', 'Persona retornada / repatriada', 6, false)
    on conflict do nothing;

    -- Valores: engagement_status (Prioritario)
    insert into public.status_value (axis_id, organization_id, code, label_es, sort_order, is_active_care, is_system, is_terminal)
    values
        (v_ax_eng, v_org, 'first_contact', 'Primer contacto', 1, false, true, false),
        (v_ax_eng, v_org, 'under_assessment', 'En valoración diagnóstica', 2, true, false, false),
        (v_ax_eng, v_org, 'active', 'En acompañamiento activo', 3, true, false, false),
        (v_ax_eng, v_org, 'paused', 'En pausa', 4, false, false, false),
        (v_ax_eng, v_org, 'referred_out', 'Referida a otra institución', 5, false, false, false),
        (v_ax_eng, v_org, 'lost_contact', 'Pérdida de contacto', 6, false, false, false),
        (v_ax_eng, v_org, 'discharged', 'Egresada / Proceso concluido', 7, false, false, false),
        (v_ax_eng, v_org, 'closed', 'Cerrada', 8, false, true, false),
        (v_ax_eng, v_org, 'anonymized', 'Anonimizada', 9, false, true, true)
    on conflict do nothing;

    -- Valores: shelter_status
    insert into public.status_value (axis_id, organization_id, code, label_es, sort_order, is_system)
    values
        (v_ax_she, v_org, 'not_applicable', 'No aplica', 1, true),
        (v_ax_she, v_org, 'sheltered', 'Albergada en el centro', 2, false),
        (v_ax_she, v_org, 'external', 'Atención externa (no pernocta)', 3, false),
        (v_ax_she, v_org, 'in_transit', 'En tránsito temporal', 4, false),
        (v_ax_she, v_org, 'left_shelter', 'Salida del albergue', 5, false)
    on conflict do nothing;

    -- Valores: record_status
    insert into public.status_value (axis_id, organization_id, code, label_es, sort_order, is_system, is_terminal)
    values
        (v_ax_rec, v_org, 'open', 'Abierto', 1, true, false),
        (v_ax_rec, v_org, 'under_review', 'En revisión para cierre', 2, true, false),
        (v_ax_rec, v_org, 'closed', 'Cerrado', 3, true, false),
        (v_ax_rec, v_org, 'anonymized', 'Anonimizado', 4, true, true)
    on conflict do nothing;

    -- Valores: case_stage
    insert into public.status_value (axis_id, organization_id, code, label_es, sort_order, is_system)
    values
        (v_ax_stg, v_org, 'intake', 'Recepción e Ingreso', 1, true),
        (v_ax_stg, v_org, 'assessment', 'Valoración Integral', 2, false),
        (v_ax_stg, v_org, 'case_plan', 'Plan de Acompañamiento', 3, false),
        (v_ax_stg, v_org, 'implementation', 'Implementación y Gestiones', 4, false),
        (v_ax_stg, v_org, 'monitoring', 'Seguimiento y Monitoreo', 5, false),
        (v_ax_stg, v_org, 'closure', 'Cierre y Egreso', 6, false)
    on conflict do nothing;
end $$;

-- ==============================================================================
-- 6. Personas y Expedientes de Demostración (Épica E3: MAP-OIM v3)
-- ==============================================================================
do $$
declare
    v_org uuid := '00000000-0000-0000-0000-000000000001';
    v_user_intk uuid := 'a0000000-0000-0000-0000-000000000003';
    v_user_case uuid := 'a0000000-0000-0000-0000-000000000002';
    v_p_wendy uuid := '30000000-0000-0000-0000-000000000001';
    v_p_dylan uuid := '30000000-0000-0000-0000-000000000002';
    v_p_mateo uuid := '30000000-0000-0000-0000-000000000003';
    v_c_wendy uuid := 'c0000000-0000-0000-0000-000000000001';
    v_c_dylan uuid := 'c0000000-0000-0000-0000-000000000002';
    v_c_mateo uuid := 'c0000000-0000-0000-0000-000000000003';
begin
    -- 1. Persona: Wendy Carolina Ramos (Madre de familia hondureña)
    insert into public.person (
        id, organization_id, given_name, paternal_family_name, maternal_family_name, preferred_name,
        birth_date, birth_date_is_estimated, sex_id, nationality_country_id, other_nationality, is_self_identified_migrant,
        primary_language_id, phone_number
    ) values (
        v_p_wendy, v_org, 'Wendy Carolina', 'Ramos', 'García', 'Caro',
        '1996-05-14', false, 2, 93, 'Honduras', true, 1, '+504 9876 5432'
    ) on conflict (id) do nothing;

    -- 2. Persona: Dylan Ramos (Hijo acompañado, 6 años)
    insert into public.person (
        id, organization_id, given_name, paternal_family_name, preferred_name,
        birth_date, birth_date_is_estimated, sex_id, nationality_country_id, other_nationality, is_self_identified_migrant,
        primary_language_id
    ) values (
        v_p_dylan, v_org, 'Dylan Josué', 'Ramos', 'Dylancito',
        '2020-02-10', false, 1, 93, 'Honduras', true, 1
    ) on conflict (id) do nothing;

    -- 3. Persona: Mateo Chen (Adolescente guatemalteco no acompañado, 16 años)
    insert into public.person (
        id, organization_id, given_name, paternal_family_name, preferred_name,
        birth_date, birth_date_is_estimated, sex_id, nationality_country_id, other_nationality, is_self_identified_migrant,
        primary_language_id, other_language
    ) values (
        v_p_mateo, v_org, 'Mateo', 'Chen', 'Mateo',
        '2010-09-02', true, 1, 86, 'Guatemala', true, 1, 'Maya Qʼeqchiʼ'
    ) on conflict (id) do nothing;

    -- 4. Expediente principal: Wendy (ASF-2026-0001)
    insert into public.case (
        id, organization_id, case_number, titular_person_id, travels_with_family,
        opened_by, assigned_user_id
    ) values (
        v_c_wendy, v_org, 'ASF-2026-0001', v_p_wendy, true,
        v_user_intk, v_user_case
    ) on conflict (id) do nothing;

    -- 5. Subfolio: Dylan (ASF-2026-0001-S1, colgado del caso de la madre)
    insert into public.case (
        id, organization_id, case_number, parent_case_id, titular_person_id, travels_with_family,
        opened_by, assigned_user_id
    ) values (
        v_c_dylan, v_org, 'ASF-2026-0001-S1', v_c_wendy, v_p_dylan, true,
        v_user_intk, v_user_case
    ) on conflict (id) do nothing;

    -- 6. Expediente principal: Mateo (ASF-2026-0002, NNA No Acompañado con caso propio)
    insert into public.case (
        id, organization_id, case_number, titular_person_id, travels_with_family,
        opened_by, assigned_user_id
    ) values (
        v_c_mateo, v_org, 'ASF-2026-0002', v_p_mateo, false,
        v_user_intk, v_user_case
    ) on conflict (id) do nothing;

    -- Marcadores de vulnerabilidad afirmados profesionalmente
    insert into public.case_vulnerability_marker (case_id, organization_id, marker_code, notes, affirmed_by)
    values
        (v_c_wendy, v_org, 'victim_of_violence', 'Sobreviviente de violencia y extorsión en país de origen.', v_user_intk),
        (v_c_mateo, v_org, 'unaccompanied_child', 'Adolescente no acompañado. Requiere notificación formal a Procuraduría de Protección.', v_user_intk),
        (v_c_mateo, v_org, 'indigenous_language_speaker', 'Hablante nativo de Qʼeqchiʼ; se requiere apoyo de interpretación.', v_user_intk)
    on conflict do nothing;
end $$;

-- ==============================================================================
-- 7. Bitácora de Área y Eventos de Compartición (Épica E4)
-- ==============================================================================
do $$
declare
    v_org uuid := '00000000-0000-0000-0000-000000000001';
    v_c_wendy uuid := 'c0000000-0000-0000-0000-000000000001';
    v_c_mateo uuid := 'c0000000-0000-0000-0000-000000000003';
    v_area_ts uuid := '10000000-0000-0000-0000-000000000001';   -- Trabajo Social
    v_area_leg uuid := '10000000-0000-0000-0000-000000000002';  -- Legal
    v_area_psi uuid := '10000000-0000-0000-0000-000000000003';  -- Psicología
    v_user_dir uuid := 'a0000000-0000-0000-0000-000000000001';  -- Elena Morales
    v_user_case uuid := 'a0000000-0000-0000-0000-000000000002'; -- Carlos Méndez
    v_user_intk uuid := 'a0000000-0000-0000-0000-000000000003'; -- Mariana Ríos
    v_entry_1 uuid := '40000000-0000-0000-0000-000000000001';
    v_entry_2 uuid := '40000000-0000-0000-0000-000000000002';
    v_entry_3 uuid := '40000000-0000-0000-0000-000000000003';
    v_entry_4 uuid := '40000000-0000-0000-0000-000000000004';
    v_entry_5 uuid := '40000000-0000-0000-0000-000000000005';
    v_share_1 uuid := '50000000-0000-0000-0000-000000000001';
begin
    -- 1. Entrevista de ingreso de Trabajo Social (Wendy) - Compartida con Legal
    insert into public.journal_entry (
        id, organization_id, case_id, area_id, author_user_id, entry_type_key,
        body, is_work_note, occurred_at, created_at, visibility
    ) values (
        v_entry_1, v_org, v_c_wendy, v_area_ts, v_user_case, 'intake_interview',
        'Entrevista cualitativa inicial de ingreso (MAP-OIM v3). La persona titular acude acompañada de su hijo menor Dylan (6 años). Refiere haber salido de San Pedro Sula por extorsión y amenazas directas a su comercio familiar. Manifiesta necesidad de alojamiento seguro y regularización migratoria.',
        false, '2026-09-20T10:00:00Z', '2026-09-20T10:30:00Z', 'shared'
    ) on conflict (id) do nothing;

    -- 2. Evento de compartición formal de la entrevista hacia Legal (notifica al digest de dirección)
    insert into public.sharing_event (
        id, organization_id, journal_entry_id, case_id, from_area_id, to_area_id,
        from_visibility, to_visibility, reason, shared_by_user_id, shared_at
    ) values (
        v_share_1, v_org, v_entry_1, v_c_wendy, v_area_ts, v_area_leg,
        'area_private', 'shared',
        'Se comparte narrativa de entrevista de ingreso para iniciar de inmediato el acompañamiento jurídico ante COMAR.',
        v_user_case, '2026-09-21T09:00:00Z'
    ) on conflict (id) do nothing;

    -- 3. Nota de deliberación profesional protegida (Legal) - is_work_note = true
    insert into public.journal_entry (
        id, organization_id, case_id, area_id, author_user_id, entry_type_key,
        body, is_work_note, occurred_at, created_at, visibility
    ) values (
        v_entry_2, v_org, v_c_wendy, v_area_leg, v_user_dir, 'follow_up',
        'Hipótesis legal preliminar sobre elegibilidad COMAR: Se identifica relato sólido conforme a la Declaración de Cartagena (violencia generalizada y amenazas de maras). Se redacta borrador de solicitud de la condición de refugiado.',
        true, '2026-09-22T11:00:00Z', '2026-09-22T11:45:00Z', 'area_private'
    ) on conflict (id) do nothing;

    -- 4. Nota aclaratoria / Fe de erratas (BV-4.2)
    -- NOTA: Se inserta antes de v_entry_3 para satisfacer la clave foránea superseded_by_id
    insert into public.journal_entry (
        id, organization_id, case_id, area_id, author_user_id, entry_type_key,
        body, is_work_note, occurred_at, created_at, visibility
    ) values (
        v_entry_4, v_org, v_c_wendy, v_area_ts, v_user_case, 'note',
        'Fe de erratas: Se aclara que la entrega del kit de aseo y muda de ropa para Dylan fue en el Módulo Familiar B (habitación 12), no en el módulo 4.',
        false, '2026-09-23T15:00:00Z', '2026-09-23T16:00:00Z', 'area_private'
    ) on conflict (id) do nothing;

    -- 5. Entrada original de Trabajo Social con error tipográfico superada por la fe de erratas
    insert into public.journal_entry (
        id, organization_id, case_id, area_id, author_user_id, entry_type_key,
        body, is_work_note, occurred_at, created_at, visibility, superseded_by_id
    ) values (
        v_entry_3, v_org, v_c_wendy, v_area_ts, v_user_case, 'note',
        'Se entregó kit de aseo y ropa para Dylan en módulo 4.',
        false, '2026-09-23T15:00:00Z', '2026-09-23T15:10:00Z', 'area_private', v_entry_4
    ) on conflict (id) do nothing;

    -- 6. Entrada inicial en caso de Mateo (NNA no acompañado)
    insert into public.journal_entry (
        id, organization_id, case_id, area_id, author_user_id, entry_type_key,
        body, is_work_note, occurred_at, created_at, visibility
    ) values (
        v_entry_5, v_org, v_c_mateo, v_area_ts, v_user_intk, 'intake_interview',
        'Entrevista de primer contacto para adolescente en movilidad no acompañado. Se verifica buen estado general de salud pero agotamiento físico. Se solicita de inmediato intérprete de lengua Qʼeqchiʼ y se activa canal directo con Procuraduría de Protección.',
        false, '2026-09-26T16:30:00Z', '2026-09-26T17:00:00Z', 'area_private'
    ) on conflict (id) do nothing;
end $$;

-- ==============================================================================
-- 8. Aviso de Privacidad, Consentimientos y Solicitudes ARCO (Épica E5)
-- ==============================================================================
do $$
declare
    v_org uuid := '00000000-0000-0000-0000-000000000001';
    v_p_wendy uuid := '30000000-0000-0000-0000-000000000001';
    v_p_mateo uuid := '30000000-0000-0000-0000-000000000003';
    v_c_wendy uuid := 'c0000000-0000-0000-0000-000000000001';
    v_c_mateo uuid := 'c0000000-0000-0000-0000-000000000003';
    v_user_dir uuid := 'a0000000-0000-0000-0000-000000000001';
    v_user_intk uuid := 'a0000000-0000-0000-0000-000000000003';
    v_notice_1 uuid := '60000000-0000-0000-0000-000000000001';
    v_cons_1 uuid := '70000000-0000-0000-0000-000000000001';
    v_cons_2 uuid := '70000000-0000-0000-0000-000000000002';
    v_cons_3 uuid := '70000000-0000-0000-0000-000000000003';
    v_cons_4 uuid := '70000000-0000-0000-0000-000000000004';
    v_arco_1 uuid := '80000000-0000-0000-0000-000000000001';
begin
    -- 1. Aviso de Privacidad Institucional v1.0
    insert into public.privacy_notice (
        id, organization_id, version, title, summary, full_text, effective_date, active
    ) values (
        v_notice_1, v_org, '1.0',
        'Aviso de Privacidad Integral para Personas en Movilidad y Solicitantes de Alojamiento',
        'Albergue Santa Fe A.C. es custodio, no dueño de sus datos personales. Se recaban datos generales y sensibles exclusivamente para auxilio humanitario, alojamiento y asesoría legal.',
        'El presente Aviso de Privacidad rige el tratamiento de datos personales por Albergue Santa Fe A.C. con domicilio en Av. Independencia 450, Tuxtla Gutiérrez, Chiapas. Con fundamento en la Ley Federal de Protección de Datos Personales en Posesión de los Particulares (vigente 2025) y los Principios Humanitarios de ACNUR y OIM, sus datos sensibles (salud, condición migratoria, violencia y etnicidad) se tratan bajo estricta confidencialidad y consentimiento expreso. Usted o su tutor pueden ejercer en todo momento sus derechos ARCO de Acceso, Rectificación, Cancelación (anonimización) u Oposición.',
        '2026-01-01', true
    ) on conflict (id) do nothing;

    -- 2. Consentimientos de Wendy Carolina Ramos
    insert into public.consent (
        id, organization_id, person_id, case_id, privacy_notice_id, consent_type,
        status, is_minor_assent, granted_at, granted_by_user_id, notes
    ) values 
        (v_cons_1, v_org, v_p_wendy, v_c_wendy, v_notice_1, 'general_care', 'granted', false, '2026-09-20T10:05:00Z', v_user_intk, 'Consentimiento general de alojamiento y atención social otorgado formalmente.'),
        (v_cons_2, v_org, v_p_wendy, v_c_wendy, v_notice_1, 'sensitive_data', 'granted', false, '2026-09-20T10:06:00Z', v_user_intk, 'Consentimiento expreso informado firmado para datos de persecución, salud y situación migratoria.')
    on conflict (id) do nothing;

    -- 3. Consentimientos de Mateo Chen (NNA No Acompañado: Asentimiento + Tutor Legal)
    insert into public.consent (
        id, organization_id, person_id, case_id, privacy_notice_id, consent_type,
        status, is_minor_assent, legal_guardian_name, legal_guardian_role, authority_letter_ref,
        granted_at, granted_by_user_id, notes
    ) values 
        (v_cons_3, v_org, v_p_mateo, v_c_mateo, v_notice_1, 'general_care', 'granted', true, 'Lic. Sofía Calderón', 'Procuraduría de Protección de NNA', 'DIF/PPNNA/2026/0491', '2026-09-26T16:40:00Z', v_user_intk, 'Asentimiento informado del adolescente con anuencia formal de la Procuraduría de Protección de NNA.'),
        (v_cons_4, v_org, v_p_mateo, v_c_mateo, v_notice_1, 'sensitive_data', 'granted', true, 'Lic. Sofía Calderón', 'Procuraduría de Protección de NNA', 'DIF/PPNNA/2026/0491', '2026-09-26T16:42:00Z', v_user_intk, 'Consentimiento institucional para valoración médica y datos de origen étnico Qʼeqchiʼ.')
    on conflict (id) do nothing;

    -- 4. Solicitud ARCO de prueba atendida (Rectificación de teléfono de Wendy)
    insert into public.arco_request (
        id, organization_id, person_id, case_id, request_type, status,
        details, reason, requested_by_name, is_legal_representative,
        received_at, handled_by_user_id, resolved_at, resolution_notes
    ) values (
        v_arco_1, v_org, v_p_wendy, v_c_wendy, 'rectification', 'approved_executed',
        'Actualización de número telefónico de contacto en México para seguimiento de cita COMAR.',
        'La titular adquirió chip SIM mexicano para recibir notificaciones institucionales.',
        'Wendy Carolina Ramos', false,
        '2026-09-24T12:00:00Z', v_user_dir, '2026-09-24T12:30:00Z',
        'Se verificó identidad y se actualizó el teléfono en la ficha sociodemográfica person.'
    ) on conflict (id) do nothing;
end $$;

-- ==============================================================================
-- 9. Datos sintéticos de demostración (57 expedientes adicionales → 60 en total)
--
-- Todo es FICTICIO. Es determinista: la misma semilla produce los mismos datos en cada
-- reinicio de la demo (el azar sale de hashtext sobre una clave estable). Las fechas se
-- calculan hacia atrás desde el día del reinicio, de modo que la demo siempre luce
-- "reciente" (ingresos distribuidos en ~6 meses, con más peso en los últimos).
--
-- Volumen elegido contra el umbral de agregación E-05 (n >= 5): categorías grandes
-- con cifras visibles y categorías raras (p. ej. Cuba, Colombia, apatridia, tortura)
-- que quedan suprimidas a propósito para mostrar la protección en el tablero.
--
-- Mezcla: 52 expedientes principales + 5 subfolios de familia. Los disparadores de
-- auditoría permanecen activos (la auditoría se genera como en producción); solo se
-- desactiva el disparador de estatus inicial para poder asentar historiales con fecha.
-- ==============================================================================

create or replace function pg_temp.bv_rnd(p_seed text)
returns double precision language sql immutable as $$
    select (abs(hashtext(p_seed)::bigint) % 1000000) / 1000000.0
$$;

create or replace function pg_temp.bv_pick(p_seed text, p_items text[], p_weights int[])
returns text language plpgsql immutable as $$
declare
    v_total int;
    v_target double precision;
    v_acc int := 0;
    i int;
begin
    select sum(w) into v_total from unnest(p_weights) w;
    v_target := pg_temp.bv_rnd(p_seed) * v_total;
    for i in 1 .. array_length(p_items, 1) loop
        v_acc := v_acc + p_weights[i];
        if v_target < v_acc then return p_items[i]; end if;
    end loop;
    return p_items[array_length(p_items, 1)];
end $$;

create or replace function pg_temp.bv_status_chain(
    p_case uuid, p_axis uuid, p_codes text[], p_t0 timestamptz, p_t1 timestamptz, p_who uuid, p_org uuid
) returns void language plpgsql as $$
declare
    n int := array_length(p_codes, 1);
    k int;
    v_from timestamptz;
    v_to timestamptz;
begin
    for k in 1 .. n loop
        v_from := p_t0 + (p_t1 - p_t0) * ((k - 1)::double precision / n);
        v_to := case when k < n then p_t0 + (p_t1 - p_t0) * (k::double precision / n) else null end;
        insert into public.case_status (organization_id, case_id, axis_id, value_id, valid_from, valid_to, reason, created_by)
        select p_org, p_case, p_axis, sv.id, v_from, v_to,
               case when k = 1 then 'Apertura de expediente (dato sintético de demostración)'
                    else 'Transición registrada durante el acompañamiento (dato sintético de demostración)' end,
               p_who
        from public.status_value sv
        where sv.axis_id = p_axis and sv.code = p_codes[k];
    end loop;
end $$;

create or replace function pg_temp.bv_seed_case(
    p_i int, p_child boolean, p_parent_case uuid, p_parent_folio text,
    p_parent_days int, p_parent_nat text, p_parent_surname text
) returns uuid language plpgsql as $$
declare
    v_org uuid := '00000000-0000-0000-0000-000000000001';
    v_dir uuid := 'a0000000-0000-0000-0000-000000000001';
    v_cw  uuid := 'a0000000-0000-0000-0000-000000000002';
    v_in  uuid := 'a0000000-0000-0000-0000-000000000003';
    v_notice uuid := '60000000-0000-0000-0000-000000000001';
    ax_leg uuid := '20000000-0000-0000-0000-000000000001';
    ax_eng uuid := '20000000-0000-0000-0000-000000000002';
    ax_she uuid := '20000000-0000-0000-0000-000000000003';
    ax_rec uuid := '20000000-0000-0000-0000-000000000004';
    ax_stg uuid := '20000000-0000-0000-0000-000000000005';
    areas_ids text[] := array['10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002',
                              '10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004',
                              '10000000-0000-0000-0000-000000000005'];
    s text := 's' || p_i || case when p_child then 'k' else 'p' end;
    v_person uuid := md5('person:' || s)::uuid;
    v_case uuid := md5('case:' || s)::uuid;
    v_days int;
    v_nat text;
    v_nat_id int;
    v_sex int;
    v_age int;
    v_birth date;
    v_given text;
    v_pat text;
    v_mat text;
    v_folio text;
    v_intake date;
    v_opened timestamptz;
    v_now timestamptz := now();
    v_window text;
    v_stage int;
    v_stage_codes text[] := array['intake','assessment','case_plan','implementation','monitoring','closure'];
    v_eng text; v_she text; v_leg text; v_rec text;
    v_eng_chain text[]; v_she_chain text[]; v_leg_chain text[]; v_rec_chain text[];
    v_t1 timestamptz;
    v_markers text[] := array['pregnant_or_lactating','unaccompanied_child','separated_child','victim_of_violence',
        'medical_condition','disability','lgbtiq','indigenous_language_speaker','stateless_or_at_risk',
        'survivor_torture_trauma','international_protection_need','older_person_at_risk','other_vulnerability'];
    v_probs double precision[] := array[0.0, 0.0, 0.0, 0.36, 0.20, 0.07, 0.08, 0.0, 0.03, 0.09, 0.26, 0.0, 0.05];
    v_prob double precision;
    m int;
    v_unaccompanied boolean := false;
    j int; v_n int;
    v_area uuid; v_area_code int; v_type text; v_author uuid; v_work boolean;
    v_entry uuid; v_occ timestamptz; v_vis text; v_to_area uuid; v_share uuid;
    v_male text[] := array['Carlos','José','Luis','Miguel','Jorge','Kevin','Brayan','Wilson','Edwin','Marvin','Oscar','Daniel','Pedro','Andrés','Jean','Wilner','Elvin','Josué'];
    v_female text[] := array['María','Ana','Karla','Dilcia','Rosa','Sandra','Lucía','Gabriela','Yeni','Marlene','Ingrid','Mirlande','Carmen','Daniela','Yolanda','Esperanza','Dayana','Nubia'];
    v_other text[] := array['Alex','Sam','Noa'];
    v_surn text[] := array['Hernández','López','Martínez','Rodríguez','Pérez','Gómez','Flores','Castillo','Reyes','Morales','Ramírez','Cruz','Mejía','Ortiz','Vásquez','Chávez','Alvarado','Aguilar','Pineda','Rivera','Interiano','Paz','Servellón','Pierre','Louis','Jean-Baptiste','Colindres','Maldonado'];
    v_cons_status text;
    -- 3 expedientes sin consentimiento expreso para datos sensibles: muestran el control P-06
    -- (alerta en el expediente y en el tablero) y, por regla, no tienen marcadores de vulnerabilidad.
    v_no_sens boolean := not p_child and p_i in (7, 23, 44);
begin
    -- ---- Persona
    v_days := case when p_child then p_parent_days
                   else floor(180 * power(pg_temp.bv_rnd(s || 'days'), 1.12))::int end;
    v_nat := case when p_child then p_parent_nat
                  else pg_temp.bv_pick(s || 'nat',
                       array['Honduras','Guatemala','El Salvador','Venezuela','Haití','Cuba','Colombia'],
                       array[36, 20, 14, 14, 9, 4, 3]) end;
    v_nat_id := case v_nat when 'Honduras' then 93 when 'Guatemala' then 86 else 1 end;
    v_sex := pg_temp.bv_pick(s || 'sex', array['1','2','3'], array[50, 47, 3])::int;
    if p_child then
        v_age := floor(pg_temp.bv_rnd(s || 'age') * 11)::int;      -- 0 a 10 años
    else
        v_age := case pg_temp.bv_pick(s || 'band', array['teen','young','adult','mid','senior'], array[11, 15, 42, 26, 6])
                    when 'teen'   then 12 + floor(pg_temp.bv_rnd(s || 'a') * 6)::int     -- 12 a 17
                    when 'young'  then 18 + floor(pg_temp.bv_rnd(s || 'a') * 7)::int     -- 18 a 24
                    when 'adult'  then 25 + floor(pg_temp.bv_rnd(s || 'a') * 15)::int    -- 25 a 39
                    when 'mid'    then 40 + floor(pg_temp.bv_rnd(s || 'a') * 15)::int    -- 40 a 54
                    else               55 + floor(pg_temp.bv_rnd(s || 'a') * 16)::int    -- 55 a 70
                 end;
    end if;
    v_intake := current_date - v_days;
    v_birth := v_intake - (v_age * 365 + floor(pg_temp.bv_rnd(s || 'bd') * 364)::int);
    v_given := case v_sex
        when 1 then v_male[1 + floor(pg_temp.bv_rnd(s || 'gn') * array_length(v_male, 1))::int]
        when 2 then v_female[1 + floor(pg_temp.bv_rnd(s || 'gn') * array_length(v_female, 1))::int]
        else v_other[1 + floor(pg_temp.bv_rnd(s || 'gn') * array_length(v_other, 1))::int] end;
    v_pat := case when p_child then p_parent_surname
                  else v_surn[1 + floor(pg_temp.bv_rnd(s || 'p1') * array_length(v_surn, 1))::int] end;
    v_mat := v_surn[1 + floor(pg_temp.bv_rnd(s || 'p2') * array_length(v_surn, 1))::int];

    v_opened := (v_intake + time '08:00') + make_interval(mins => floor(pg_temp.bv_rnd(s || 'op') * 540)::int);
    if v_opened > v_now then v_opened := v_now - interval '1 hour'; end if;

    insert into public.person (
        id, organization_id, given_name, paternal_family_name, maternal_family_name,
        birth_date, birth_date_is_estimated, sex_id, nationality_country_id, other_nationality,
        is_self_identified_migrant, primary_language_id, other_language, created_at, updated_at
    ) values (
        v_person, v_org, v_given, v_pat, v_mat,
        v_birth, pg_temp.bv_rnd(s || 'est') < 0.15, v_sex, v_nat_id, v_nat,
        true, 1,
        case when v_nat = 'Haití' then 'Criollo haitiano' else null end,
        v_opened, v_opened
    );

    -- ---- Caso
    v_window := pg_temp.bv_pick(s || 'win', array['fija','movil','transaccional'], array[55, 28, 17]);
    v_folio := case when p_child then p_parent_folio || '-S1'
                    else 'ASF-2026-' || lpad((p_i + 2)::text, 4, '0') end;
    v_area_code := 1 + floor(pg_temp.bv_rnd(s || 'ar') * 5)::int;

    insert into public.case (
        id, organization_id, case_number, parent_case_id, titular_person_id,
        intake_window_type, intake_date, travels_with_family, opened_at, opened_by,
        assigned_area_id, assigned_user_id, created_at, updated_at
    ) values (
        v_case, v_org, v_folio, p_parent_case, v_person,
        v_window, v_intake,
        p_child or p_i in (3, 11, 19, 27, 41) or pg_temp.bv_rnd(s || 'fam') < 0.15,
        v_opened, v_in,
        areas_ids[case when v_area_code in (4, 5) then 1 else v_area_code end]::uuid, v_cw,
        v_opened, v_opened
    );

    -- ---- Estatus (5 ejes con historial); el disparador inicial está desactivado en este bloque
    v_stage := least(6, 1 + floor((v_days / 26.0) * (0.6 + 0.9 * pg_temp.bv_rnd(s || 'stg')))::int);

    v_eng := case v_stage
        when 1 then pg_temp.bv_pick(s || 'eng', array['first_contact','under_assessment'], array[70, 30])
        when 2 then pg_temp.bv_pick(s || 'eng', array['under_assessment','active'], array[80, 20])
        when 3 then pg_temp.bv_pick(s || 'eng', array['active','paused','lost_contact','referred_out'], array[75, 10, 10, 5])
        when 4 then pg_temp.bv_pick(s || 'eng', array['active','paused','lost_contact','referred_out'], array[72, 10, 10, 8])
        when 5 then pg_temp.bv_pick(s || 'eng', array['active','referred_out','paused','lost_contact'], array[50, 20, 10, 20])
        else        pg_temp.bv_pick(s || 'eng', array['discharged','referred_out','closed','lost_contact'], array[45, 25, 15, 15])
    end;
    v_she := case
        when v_eng in ('lost_contact') then pg_temp.bv_pick(s || 'she', array['left_shelter','in_transit'], array[60, 40])
        when v_eng in ('discharged','closed') then pg_temp.bv_pick(s || 'she', array['left_shelter','external'], array[80, 20])
        when v_eng = 'referred_out' then pg_temp.bv_pick(s || 'she', array['left_shelter','external','in_transit'], array[55, 25, 20])
        else pg_temp.bv_pick(s || 'she', array['sheltered','external','in_transit'], array[56, 24, 20])
    end;
    v_leg := pg_temp.bv_pick(s || 'leg',
        array['undetermined','asylum_seeker','humanitarian_visa','irregular_situation','recognized_refugee','returnee'],
        array[25, 30, 15, 20, 6, 4]);
    v_rec := case
        when v_eng = 'closed' then 'closed'
        when v_stage = 6 then pg_temp.bv_pick(s || 'rec', array['closed','under_review','open'], array[60, 25, 15])
        else 'open' end;

    v_eng_chain := case when v_eng = 'first_contact' then array['first_contact']
                        when v_eng = 'under_assessment' then array['first_contact','under_assessment']
                        when v_stage >= 3 then array['first_contact','under_assessment', v_eng]
                        else array['first_contact', v_eng] end;
    v_she_chain := case when v_she = 'not_applicable' then array['not_applicable'] else array['not_applicable', v_she] end;
    v_leg_chain := case when v_leg = 'undetermined' then array['undetermined'] else array['undetermined', v_leg] end;
    v_rec_chain := case when v_rec = 'open' then array['open'] else array['open', v_rec] end;

    v_t1 := greatest(v_opened + interval '1 hour', v_now - interval '2 hours');
    perform pg_temp.bv_status_chain(v_case, ax_stg, v_stage_codes[1:v_stage], v_opened, v_t1, v_cw, v_org);
    perform pg_temp.bv_status_chain(v_case, ax_eng, v_eng_chain, v_opened, v_t1, v_cw, v_org);
    perform pg_temp.bv_status_chain(v_case, ax_she, v_she_chain, v_opened, v_t1, v_cw, v_org);
    perform pg_temp.bv_status_chain(v_case, ax_leg, v_leg_chain, v_opened, v_t1, v_cw, v_org);
    perform pg_temp.bv_status_chain(v_case, ax_rec, v_rec_chain, v_opened, v_t1, v_cw, v_org);

    -- ---- Marcadores de vulnerabilidad (correlacionados con edad y perfil)
    for m in 1 .. array_length(v_markers, 1) loop
        v_prob := v_probs[m];
        if v_markers[m] = 'pregnant_or_lactating' then v_prob := case when v_sex = 2 and v_age between 18 and 40 then 0.22 else 0 end; end if;
        if v_markers[m] = 'unaccompanied_child' then v_prob := case when v_age < 18 and not p_child and v_age >= 12 then 0.45 else 0 end; end if;
        if v_markers[m] = 'separated_child' then v_prob := case when v_age < 18 and not p_child and v_age >= 12 then 0.15 else 0 end; end if;
        if v_markers[m] = 'indigenous_language_speaker' then v_prob := case when v_nat in ('Guatemala','Honduras') then 0.13 else 0.01 end; end if;
        if v_markers[m] = 'older_person_at_risk' then v_prob := case when v_age >= 60 then 0.6 else 0 end; end if;
        if v_prob > 0 and not v_no_sens and pg_temp.bv_rnd(s || 'mk' || m) < v_prob then
            insert into public.case_vulnerability_marker (case_id, organization_id, marker_code, notes, affirmed_by, affirmed_at, created_at)
            values (v_case, v_org, v_markers[m], 'Marcador afirmado en ventanilla (dato sintético de demostración).', v_in, v_opened, v_opened);
            if v_markers[m] = 'unaccompanied_child' then v_unaccompanied := true; end if;
        end if;
    end loop;

    -- ---- Consentimientos
    insert into public.consent (
        organization_id, person_id, case_id, privacy_notice_id, consent_type, status,
        is_minor_assent, legal_guardian_name, legal_guardian_role, authority_letter_ref,
        granted_at, granted_by_user_id, notes, created_at
    )
    select v_org, v_person, v_case, v_notice, t, 'granted',
           v_age < 18,
           case when v_unaccompanied then 'Representante de la Procuraduría de Protección' end,
           case when v_unaccompanied then 'Procuraduría de Protección de NNA' end,
           case when v_unaccompanied then 'DIF/PPNNA/2026/' || lpad(p_i::text, 4, '0') end,
           v_opened + interval '5 minutes', v_in,
           'Consentimiento informado en el ingreso (dato sintético de demostración).', v_opened
    from unnest(case when v_no_sens then array['general_care'] else array['general_care','sensitive_data'] end) t;

    v_cons_status := pg_temp.bv_pick(s || 'sec', array['none','granted','opposed'], array[75, 20, 5]);
    if v_cons_status <> 'none' then
        insert into public.consent (organization_id, person_id, case_id, privacy_notice_id, consent_type, status, is_minor_assent, granted_at, granted_by_user_id, notes, created_at)
        values (v_org, v_person, v_case, v_notice, 'secondary_use_research', v_cons_status, v_age < 18, v_opened + interval '15 minutes', v_in,
                case when v_cons_status = 'opposed' then 'Oposición a usos secundarios (dato sintético).' else 'Autoriza estadística agregada (dato sintético).' end, v_opened);
        if v_cons_status = 'opposed' then
            insert into public.arco_request (
                organization_id, person_id, case_id, request_type, status, details, reason,
                requested_by_name, is_legal_representative, received_at, handled_by_user_id, resolved_at, resolution_notes, created_at
            ) values (
                v_org, v_person, v_case, 'opposition', 'approved_executed',
                'Oposición formal a tratamientos secundarios y reportes externos (dato sintético).',
                'La persona titular no desea que su información se use para estadística ni estudios.',
                v_given || ' ' || v_pat, false, v_opened + interval '1 day', v_dir, v_opened + interval '1 day 1 hour',
                'Se asentó la oposición; el expediente se excluye de reportes agregados.', v_opened + interval '1 day');
        end if;
    end if;

    -- ---- Bitácora de área (1 a 3 entradas) y compartición ocasional
    v_n := 1 + (pg_temp.bv_rnd(s || 'n1') < 0.6)::int + (pg_temp.bv_rnd(s || 'n2') < 0.35)::int;
    for j in 1 .. v_n loop
        v_area_code := case when j = 1 then 1
            else pg_temp.bv_pick(s || 'ja' || j, array['1','2','3','4','5'], array[40, 22, 18, 12, 8])::int end;
        v_area := areas_ids[v_area_code]::uuid;
        v_type := case when j = 1 then 'intake_interview'
            else pg_temp.bv_pick(s || 'jt' || j, array['follow_up','referral','note','incident'], array[55, 20, 20, 5]) end;
        v_author := case when j = 1 then v_in when v_area_code = 1 then v_cw else v_dir end;
        v_work := j > 1 and pg_temp.bv_rnd(s || 'jw' || j) < 0.18;
        v_occ := least(v_now - interval '5 minutes',
                       v_opened + (v_now - v_opened) * (((j - 1)::double precision / v_n) + 0.02));
        v_entry := md5('entry:' || s || ':' || j)::uuid;
        v_vis := 'area_private';
        v_share := null;

        if j > 1 and not v_work and pg_temp.bv_rnd(s || 'js' || j) < 0.22 then
            v_vis := 'shared';
            v_to_area := case when v_area_code = 2 then areas_ids[1]::uuid else areas_ids[2]::uuid end;
            v_share := md5('share:' || s || ':' || j)::uuid;
        end if;

        insert into public.journal_entry (
            id, organization_id, case_id, area_id, author_user_id, entry_type_key, body, is_work_note,
            occurred_at, created_at, visibility
        ) values (
            v_entry, v_org, v_case, v_area, v_author, v_type,
            case v_type
                when 'intake_interview' then 'Entrevista de ingreso con enfoque de protección. Se informa de servicios disponibles y del aviso de privacidad; se identifican necesidades inmediatas. (Registro sintético de demostración)'
                when 'follow_up' then 'Seguimiento del plan de acompañamiento: se revisan avances, se gestionan citas y se actualizan necesidades básicas. (Registro sintético de demostración)'
                when 'referral' then 'Se canaliza a institución aliada para atención especializada, documentando el consentimiento para la referencia. (Registro sintético de demostración)'
                when 'incident' then 'Incidente menor de convivencia atendido por el personal; se levanta acta interna sin afectaciones. (Registro sintético de demostración)'
                else 'Nota breve de seguimiento sobre la situación de la persona atendida. (Registro sintético de demostración)'
            end,
            v_work, v_occ, v_occ + interval '20 minutes', v_vis
        );

        if v_share is not null then
            insert into public.sharing_event (
                id, organization_id, journal_entry_id, case_id, from_area_id, to_area_id,
                from_visibility, to_visibility, reason, shared_by_user_id, shared_at,
                acknowledged_by_user_id, acknowledged_at
            ) values (
                v_share, v_org, v_entry, v_case, v_area, v_to_area,
                'area_private', 'shared',
                'Se comparte para coordinar la atención entre áreas (dato sintético de demostración).',
                v_author, least(v_now - interval '1 minute', v_occ + interval '1 hour'),
                case when pg_temp.bv_rnd(s || 'ack' || j) < 0.5 then v_dir end,
                case when pg_temp.bv_rnd(s || 'ack' || j) < 0.5 then least(v_now - interval '1 minute', v_occ + interval '1 day') end
            );
        end if;
    end loop;

    return v_case;
end $$;

do $$
declare
    i int;
    v_case uuid;
    v_folio text;
    v_days int;
    v_nat text;
    v_surname text;
begin
    -- Estatus iniciales: este bloque los asienta con historial propio (se restaura al terminar)
    alter table public."case" disable trigger trg_initialize_case_status;

    for i in 1 .. 52 loop
        v_case := pg_temp.bv_seed_case(i, false, null, null, null, null, null);

        if i in (3, 11, 19, 27, 41) then
            select c.case_number, current_date - c.intake_date, p.other_nationality, p.paternal_family_name
              into v_folio, v_days, v_nat, v_surname
            from public.case c join public.person p on p.id = c.titular_person_id
            where c.id = v_case;
            perform pg_temp.bv_seed_case(i, true, v_case, v_folio, v_days, v_nat, v_surname);
        end if;
    end loop;

    alter table public."case" enable trigger trg_initialize_case_status;
end $$;

-- Requerimientos de autoridad adicionales (Ethos E-03)
insert into public.authority_request (id, organization_id, authority_name, request_type, official_letter_ref, received_at, handled_by_user_id, response_summary, extract_delivered)
values
    ('d0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
     'Fiscalía General del Estado (dato sintético)', 'Solicitud de información de un expediente',
     'FGE/2026/SINT-0412', now() - interval '12 days', 'a0000000-0000-0000-0000-000000000001',
     'Se atendió con el protocolo institucional: solo con orden fundada y motivada.', true),
    ('d0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001',
     'Instituto Nacional de Migración (dato sintético)', 'Verificación de estancia en el albergue',
     'INM/2026/SINT-0977', now() - interval '3 days', 'a0000000-0000-0000-0000-000000000001',
     null, false)
on conflict (id) do nothing;
