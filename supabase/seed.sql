-- ==============================================================================
-- Bitácora Viva — Seed Data para Entorno de Desarrollo y Pruebas
-- Albergue Demo: Albergue Santa Fe (Tenancy inicial)
-- ==============================================================================

-- 1. Organización de demostración
insert into public.organization (id, slug, legal_name, display_name, active)
values (
    '00000000-0000-0000-0000-000000000001',
    'albergue-santa-fe',
    'Albergue Santa Fe A.C.',
    'Albergue Santa Fe',
    true
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
        insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
        values
            (v_user_dir, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'director@alberguesantafe.org', crypt('albergue2026!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Elena Morales (Directora)"}', now(), now()),
            (v_user_case, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'caseworker@alberguesantafe.org', crypt('albergue2026!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Carlos Méndez (Trabajo Social)"}', now(), now()),
            (v_user_intk, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'intake@alberguesantafe.org', crypt('albergue2026!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Mariana Ríos (Oficial de Ingreso)"}', now(), now()),
            (v_user_view, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'viewer@alberguesantafe.org', crypt('albergue2026!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Dr. Roberto Soto (Observador/Auditor)"}', now(), now())
        on conflict (id) do nothing;

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
        birth_date, birth_date_is_estimated, sex_id, nationality_country_id, is_self_identified_migrant,
        primary_language_id, phone_number
    ) values (
        v_p_wendy, v_org, 'Wendy Carolina', 'Ramos', 'García', 'Caro',
        '1996-05-14', false, 2, 93, true, 1, '+504 9876 5432'
    ) on conflict (id) do nothing;

    -- 2. Persona: Dylan Ramos (Hijo acompañado, 6 años)
    insert into public.person (
        id, organization_id, given_name, paternal_family_name, preferred_name,
        birth_date, birth_date_is_estimated, sex_id, nationality_country_id, is_self_identified_migrant,
        primary_language_id
    ) values (
        v_p_dylan, v_org, 'Dylan Josué', 'Ramos', 'Dylancito',
        '2020-02-10', false, 1, 93, true, 1
    ) on conflict (id) do nothing;

    -- 3. Persona: Mateo Chen (Adolescente guatemalteco no acompañado, 16 años)
    insert into public.person (
        id, organization_id, given_name, paternal_family_name, preferred_name,
        birth_date, birth_date_is_estimated, sex_id, nationality_country_id, is_self_identified_migrant,
        primary_language_id, other_language
    ) values (
        v_p_mateo, v_org, 'Mateo', 'Chen', 'Mateo',
        '2010-09-02', true, 1, 86, true, 1, 'Maya Qʼeqchiʼ'
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

