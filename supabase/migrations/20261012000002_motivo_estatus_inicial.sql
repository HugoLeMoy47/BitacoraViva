-- ==============================================================================
-- Motivo inicial de los estatus: una clave de traducción, no un texto en un idioma
--
-- Al abrir un expediente, el disparador dejaba como motivo «Apertura de expediente y nacimiento
-- automático de estatus»: texto técnico, en español y guardado en la base. Ahora guarda la clave
-- `i18n:status.reason_initial` y la interfaz la traduce (src/locales/es.json), de modo que el mismo
-- dato sirva en cualquier idioma. Los registros ya existentes conservan su texto (son de prueba).
-- ==============================================================================

create or replace function public.fn_initialize_case_status()
returns trigger
security definer
set search_path = public
language plpgsql as $$
declare
    r_axis record;
    v_val_id uuid;
    v_initial_code text;
begin
    for r_axis in 
        select id, code from public.status_axis where organization_id = new.organization_id
    loop
        case r_axis.code
            when 'legal_status' then v_initial_code := 'undetermined';
            when 'engagement_status' then v_initial_code := 'first_contact';
            when 'shelter_status' then v_initial_code := 'not_applicable';
            when 'record_status' then v_initial_code := 'open';
            when 'case_stage' then v_initial_code := 'intake';
            else v_initial_code := null;
        end case;

        if v_initial_code is not null then
            select id into v_val_id 
            from public.status_value 
            where axis_id = r_axis.id and code = v_initial_code limit 1;

            if v_val_id is not null then
                insert into public.case_status (
                    organization_id,
                    case_id,
                    axis_id,
                    value_id,
                    valid_from,
                    valid_to,
                    reason,
                    created_by
                ) values (
                    new.organization_id,
                    new.id,
                    r_axis.id,
                    v_val_id,
                    now(),
                    null,
                    'i18n:status.reason_initial',
                    new.opened_by
                );
            end if;
        end if;
    end loop;
    return new;
end;
$$;

