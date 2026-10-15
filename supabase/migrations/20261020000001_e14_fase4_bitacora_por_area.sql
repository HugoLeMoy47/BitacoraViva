-- ==============================================================================
-- E14 fase 4 · Bitácora por área
--
-- Contexto: la hoja de casos de CAFEMIN lleva una columna por servicio (hospitalidad, proyecto de vida, salud física,
-- psicología, psicoterapia, psiquiatría, empleabilidad/trabajo externo, servicio interno, formación, escuela, jurídico),
-- más textos de Trabajo Social (diagnóstico, entrevista, reunión de casos, llamadas de atención, ruta de atención integral).
-- En el sistema todo eso son ENTRADAS DE BITÁCORA (inmutables, privadas del área por omisión), no campos.
--
-- Cómo
--  * Tipos de entrada nuevos: `diagnosis` (diagnóstico de Trabajo Social), `integral_route` (ruta de atención integral),
--    `case_meeting` (reunión de casos) y `warning` (llamada de atención; el ordinal 1ra/2da/3ra se DERIVA al mostrarla).
--    La entrevista de Trabajo Social es `intake_interview` (autor: quien la hizo) y las intervenciones, `follow_up`.
--  * Línea de servicio: diccionario editable `service_line` de `catalog_item` (dirección y Trabajo Social) sembrado con las
--    once columnas de la hoja. Es un dato OPCIONAL de la entrada (`service_line_item_id`); las áreas y sus permisos no cambian.
--  * Procedencia: `source` ('app' | 'import'), `source_author_label` (autoría original de lo importado, texto de la hoja) e
--    `import_batch_id` (lote, para la fase 6). Una entrada importada exige su autoría original; una escrita aquí no lleva
--    autoría ajena. Los tres, junto con la línea de servicio, son inmutables como el resto de la entrada.
--  * `fn_create_journal_entry` recibe la línea de servicio (opcional); lo asentado desde el sistema nace con procedencia «app».
--
-- Idempotente: el reinicio de la demo reaplica todas las migraciones.
-- ==============================================================================

-- ---------------------------------------------------------------- 1. Tipos de entrada nuevos
do $$
declare
    v_name text;
begin
    for v_name in
        select c.conname from pg_constraint c
        where c.conrelid = 'public.journal_entry'::regclass and c.contype = 'c'
          and pg_get_constraintdef(c.oid) ilike '%entry_type_key%'
    loop
        execute format('alter table public.journal_entry drop constraint %I', v_name);
    end loop;
end $$;
alter table public.journal_entry add constraint journal_entry_entry_type_key_check
    check (entry_type_key in (
        'intake_interview', 'follow_up', 'referral', 'home_visit', 'incident', 'note',
        'diagnosis', 'integral_route', 'case_meeting', 'warning'
    ));

-- ---------------------------------------------------------------- 2. Línea de servicio (diccionario editable)
alter table public.catalog_item drop constraint if exists catalog_item_catalog_check;
alter table public.catalog_item add constraint catalog_item_catalog_check
    check (catalog in ('language', 'religion', 'specific_need', 'service_line'));

insert into public.catalog_item (organization_id, catalog, key, label_es, legacy_code, is_system, sort_order)
select o.id, 'service_line', v.key, v.label_es, v.legacy_code, false, v.sort_order
from public.organization o
cross join (values
    ('hospitality', 'Hospitalidad', 'HOSPITALIDAD', 1),
    ('life_project', 'Proyecto de vida', 'PROYECTO DE VIDA', 2),
    ('physical_health', 'Salud física', 'SALUD FÍSICA', 3),
    ('psychology', 'Psicología', 'PSICOLOGÍA', 4),
    ('psychotherapy', 'Psicoterapia', 'PSICOTERAPIA', 5),
    ('psychiatry', 'Psiquiatría', 'PSIQUIATRÍA', 6),
    ('employability', 'Empleabilidad / trabajo externo', 'EMPLEABILIDAD', 7),
    ('internal_service', 'Servicio interno', 'SERVICIO INTERNO', 8),
    ('training', 'Formación', 'FORMACIÓN', 9),
    ('school', 'Escuela', 'ESCUELA', 10),
    ('legal', 'Jurídico', 'JURÍDICO', 11)
) as v(key, label_es, legacy_code, sort_order)
on conflict (organization_id, catalog, key) do nothing;

-- ---------------------------------------------------------------- 3. Columnas de la entrada
alter table public.journal_entry
    add column if not exists service_line_item_id uuid references public.catalog_item(id) on delete restrict,
    add column if not exists source text not null default 'app',
    add column if not exists source_author_label text,
    add column if not exists import_batch_id uuid;

alter table public.journal_entry drop constraint if exists journal_entry_source_check;
alter table public.journal_entry add constraint journal_entry_source_check
    check (
        (source = 'app' and source_author_label is null and import_batch_id is null)
        or (source = 'import' and nullif(btrim(source_author_label), '') is not null)
    );
create index if not exists idx_journal_entry_service_line on public.journal_entry (case_id, service_line_item_id)
    where service_line_item_id is not null;

-- ---------------------------------------------------------------- 4. Inmutabilidad: lo nuevo tampoco se edita
-- Se redefine a partir de la definición vigente (20261014000001); solo se agregan las columnas nuevas a la guarda.
create or replace function public.fn_prevent_update_journal_entry()
returns trigger
language plpgsql
as $function$
begin
    if old.is_work_note is distinct from new.is_work_note then
        raise exception 'Violación de Ethos E-02: una nota de trabajo protegida no deja de serlo (ni una entrada ordinaria pasa a serlo).' using errcode = 'BV608';
    end if;
    if new.is_work_note and new.visibility is distinct from old.visibility then
        raise exception 'Violación de Ethos E-02: una nota de trabajo protegida no se comparte.' using errcode = 'BV609';
    end if;

    -- Purga estricta por ejercicio de derecho ARCO de cancelación (ADR-0001)
    if new.body = '[CONTENIDO SUPRIMIDO POR EJERCICIO DE DERECHO ARCO DE CANCELACIÓN - ADR-0001]' then
        if not public.has_role('director') then
            raise exception 'Violación de seguridad: La purga por anonimización de bitácora está reservada exclusivamente al rol director (ADR-0001).' using errcode = 'BV610';
        end if;
        return new;
    end if;

    if old.body != new.body or
       old.author_user_id != new.author_user_id or
       old.area_id != new.area_id or
       old.occurred_at != new.occurred_at or
       old.created_at != new.created_at or
       old.entry_type_key != new.entry_type_key or
       old.case_id != new.case_id or
       old.organization_id != new.organization_id or
       old.service_line_item_id is distinct from new.service_line_item_id or
       old.source is distinct from new.source or
       old.source_author_label is distinct from new.source_author_label or
       old.import_batch_id is distinct from new.import_batch_id then
        raise exception 'Violación de integridad: El contenido original de un registro de bitácora no admite edición. Utilice una fe de erratas (BV-4.2).' using errcode = 'BV611';
    end if;

    return new;
end;
$function$;

-- ---------------------------------------------------------------- 5. Asentar una entrada con su línea de servicio
-- Se sustituye la firma de 6 parámetros por una de 7 (el nuevo es opcional); el resto es la definición vigente.
drop function if exists public.fn_create_journal_entry(uuid, text, text, timestamptz, boolean, uuid);
create or replace function public.fn_create_journal_entry(
    p_case_id uuid, p_entry_type_key text, p_body text,
    p_occurred_at timestamptz default now(), p_is_work_note boolean default false,
    p_area_id uuid default null, p_service_line_item_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
    v_user_id uuid;
    v_org_id uuid;
    v_area_id uuid;
    v_new_entry_id uuid;
    v_area_code text;
begin
    if auth.uid() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: se requiere una sesión con rol operativo vigente.' using errcode = 'BV101';
    end if;
    perform public.fn_assert_same_org('case', p_case_id);
    v_user_id := auth.uid();

    if p_body is null or trim(p_body) = '' then
        raise exception 'El texto de la intervención en bitácora es obligatorio.' using errcode = 'BV310';
    end if;

    select organization_id into v_org_id from public.case where id = p_case_id;
    if v_org_id is null then
        raise exception 'Expediente no encontrado.' using errcode = 'BV203';
    end if;

    -- E14 f4: la línea de servicio, si se indica, es un valor activo del diccionario de esta organización
    if p_service_line_item_id is not null then
        perform public.fn_assert_catalog_item(v_org_id, 'service_line', p_service_line_item_id);
    end if;

    if p_area_id is not null then
        -- Escribir a nombre de un área exige ser de esa área (o dirección) y que sea de la misma
        -- organización. Quien no tiene área asignada (ingreso) solo escribe en coordinación.
        select a.code into v_area_code
        from public.area a
        where a.id = p_area_id and a.organization_id = v_org_id and a.active;
        if v_area_code is null then
            raise exception 'Área no válida para esta organización.' using errcode = 'BV208';
        end if;

        if not public.has_role('director') then
            if exists (
                select 1 from public.user_role ur
                where ur.user_id = v_user_id and ur.revoked_at is null and ur.area_id is not null
            ) then
                if not exists (
                    select 1 from public.user_role ur
                    where ur.user_id = v_user_id and ur.revoked_at is null and ur.area_id = p_area_id
                ) then
                    raise exception 'Permiso denegado: solo se escribe a nombre del propio área (Ethos C2, C4).' using errcode = 'BV117';
                end if;
            elsif v_area_code <> 'coordinacion' then
                raise exception 'Permiso denegado: sin área asignada solo se escribe a nombre de coordinación.' using errcode = 'BV118';
            end if;
        end if;
        v_area_id := p_area_id;
    else
        select area_id into v_area_id
        from public.user_role
        where user_id = v_user_id and revoked_at is null and area_id is not null
        limit 1;

        if v_area_id is null then
            select id into v_area_id
            from public.area
            where organization_id = v_org_id and code = 'coordinacion'
            limit 1;
        end if;
    end if;

    if v_area_id is null then
        raise exception 'No se pudo determinar el área operativa para el registro de bitácora.' using errcode = 'BV702';
    end if;

    insert into public.journal_entry (
        organization_id, case_id, area_id, author_user_id, entry_type_key,
        body, is_work_note, occurred_at, created_at, visibility, service_line_item_id, source
    ) values (
        v_org_id, p_case_id, v_area_id, v_user_id, p_entry_type_key,
        p_body, p_is_work_note, coalesce(p_occurred_at, now()), now(), 'area_private', p_service_line_item_id, 'app'
    ) returning id into v_new_entry_id;

    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_org_id, v_user_id, 'INSERT', 'journal_entry', v_new_entry_id,
        jsonb_build_object(
            'case_id', p_case_id,
            'entry_type_key', p_entry_type_key,
            'is_work_note', p_is_work_note,
            'area_id', v_area_id,
            'occurred_at', p_occurred_at,
            'service_line_item_id', p_service_line_item_id
        ));

    return v_new_entry_id;
end;
$function$;
revoke execute on function public.fn_create_journal_entry(uuid, text, text, timestamptz, boolean, uuid, uuid) from public, anon;
grant execute on function public.fn_create_journal_entry(uuid, text, text, timestamptz, boolean, uuid, uuid) to authenticated;
