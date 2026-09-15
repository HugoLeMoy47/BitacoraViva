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

-- 3. Cuentas de demostración en auth.users y user_profile
-- Nota: En Supabase local, se insertan en auth.users con contraseña fija "albergue2026!"
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

        -- Asignación de roles
        insert into public.user_role (user_id, role_name)
        values
            (v_user_dir, 'director'),
            (v_user_case, 'caseworker'),
            (v_user_intk, 'intake_officer'),
            (v_user_view, 'viewer')
        on conflict (user_id, role_name) do nothing;
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
    '{"event": "genesis_albergue_santa_fe", "commitments": "Ethos C1-C8 activados", "version": "v1.0"}'::jsonb
) on conflict (id) do nothing;
