-- ==============================================================================
-- E15 fase 3 · Registro de origen (KOBO / red de albergues) y «Servicio social»
--
-- Decisión del Product Owner (22 oct 2026): de KOBO y la red de albergues se guarda **solo lo que no se repite** en la ficha, como dato
-- informativo; y se podrá informar por origen más adelante (deuda D-23, no se construye ahora).
--
-- Cómo
--  * El registro de origen son **preguntas de la ficha social** (E15 fase 2) en una sección propia, `origin`: así las edita
--    Trabajo Social en «Diccionarios» y se versionan como el resto. No se guardan la edad ni la nacionalidad de KOBO
--    (ya están en la ficha). El mes de registro se calcula de la fecha.
--  * Se siembran tres preguntas: tipo de población (texto; sensible: es perfil migratorio), fecha de registro de origen
--    (fecha con precisión) y quién registró (texto, la etiqueta que trae la hoja).
--  * «Servicio social» se agrega a las líneas de servicio de la bitácora.
--
-- Idempotente: el reinicio de la demo reaplica todas las migraciones.
-- ==============================================================================

-- ---------------------------------------------------------------- 1. La sección de origen
do $$
declare
    v_name text;
begin
    for v_name in
        select c.conname from pg_constraint c
        where c.conrelid = 'public.social_question'::regclass and c.contype = 'c'
          and pg_get_constraintdef(c.oid) ilike '%section%'
    loop
        execute format('alter table public.social_question drop constraint %I', v_name);
    end loop;
end $$;
alter table public.social_question add constraint social_question_section_check
    check (section in ('migration', 'sensitive', 'origin'));

insert into public.social_question (organization_id, key, label_es, section, answer_type, has_detail, is_sensitive, sort_order)
select o.id, v.key, v.label_es, 'origin', v.answer_type, false, v.is_sensitive, v.sort_order
from public.organization o
cross join (values
    ('origin_population_type', 'Tipo de población (registro de origen)', 'text', true, 1),
    ('origin_registered_on', 'Fecha de registro de origen (red de albergues)', 'date', false, 2),
    ('origin_registered_by', 'Quién hizo el registro de origen', 'text', false, 3)
) as v(key, label_es, answer_type, is_sensitive, sort_order)
on conflict (organization_id, key) do nothing;

-- ---------------------------------------------------------------- 2. «Servicio social» como línea de servicio
insert into public.catalog_item (organization_id, catalog, key, label_es, legacy_code, is_system, sort_order)
select o.id, 'service_line', 'social_service', 'Servicio social', 'SERVICIO SOCIAL', false, 12
from public.organization o
on conflict (organization_id, catalog, key) do nothing;
