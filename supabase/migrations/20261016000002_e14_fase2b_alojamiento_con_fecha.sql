-- ==============================================================================
-- E14 fase 2b · Ingreso y egreso del albergue, capturados con el estatus de alojamiento
--
-- Decisión del Product Owner (16 oct 2026), opción A: el estatus manda y la fecha acompaña.
--  * «Albergada» (`sheltered`) = ingreso al albergue; «Salida del albergue» (`left_shelter`) = egreso.
--  * «Reubicada», «En tránsito» y «Atención externa» son estatus fuera del albergue (la persona puede no haber
--    ingresado nunca): no son ingreso ni egreso y no llevan fecha.
--  * La fecha es obligatoria. La interfaz propone el día del movimiento y se puede cambiar (incluida la precisión:
--    día, mes o año); la base no pone ninguna por su cuenta.
--  * `fn_change_shelter_status` cambia el estatus y registra la fecha en una sola operación: si la fecha no cuadra
--    (futura, anterior al ingreso, etc.) el estatus tampoco cambia. El cambio genérico de estatus ya no permite
--    pasar a «albergada» ni a «salida del albergue» (`BV328`).
--  * Un ingreso posterior al egreso en el mismo caso se rechaza (`BV327`): el reingreso es un caso nuevo vinculado.
--  * Lo ya guardado no se toca: los casos con esos estatus y sin fecha siguen «No registrado».
--  * Errores con código estable: BV328, BV329.
--
-- Idempotente: el reinicio de la demo reaplica todas las migraciones.
-- ==============================================================================

-- El cambio genérico de estatus, con el candado nuevo (a partir de la definición vigente, 20261014000001)
CREATE OR REPLACE FUNCTION public.fn_change_case_status(p_case_id uuid, p_axis_code text, p_new_value_code text, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_org_id uuid;
    v_axis_id uuid;
    v_old_status_id uuid;
    v_old_val_code text;
    v_new_val_id uuid;
    v_new_status_id uuid;
    v_user_id uuid;
begin
    if auth.uid() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: se requiere una sesión con rol operativo vigente.' using errcode = 'BV101';
    end if;
    perform public.fn_assert_same_org('case', p_case_id);
    v_user_id := auth.uid();

    if p_reason is null or trim(p_reason) = '' then
        raise exception 'Violación de integridad: Todo cambio de estatus exige un motivo explícito en texto (reason).' using errcode = 'BV305';
    end if;

    select organization_id into v_org_id from public.case where id = p_case_id;
    if v_org_id is null then
        raise exception 'Expediente no encontrado.' using errcode = 'BV203';
    end if;

    -- Compartimentación por área (BV-2.3)
    if p_axis_code = 'legal_status' then
        if not (public.has_role('director') or public.has_role_in_area('caseworker', 'legal')) then
            raise exception 'Permiso denegado: El estatus jurídico solo puede ser modificado por Dirección o personal adscrito al Área Jurídica.' using errcode = 'BV110';
        end if;
    end if;

    -- Cierre administrativo: facultad de Dirección
    if p_axis_code = 'record_status' and p_new_value_code = 'closed' then
        if not public.has_role('director') then
            raise exception 'Permiso denegado: El cierre administrativo del expediente es facultad exclusiva de Dirección.' using errcode = 'BV111';
        end if;
    end if;

    -- «anonymized» (terminal, irreversible) solo se alcanza anonimizando a la persona (ADR-0001)
    if p_new_value_code = 'anonymized'
       and coalesce(current_setting('bv.anonymizing', true), '') <> 'on' then
        raise exception 'Violación de Ethos C7: el estatus «anonymized» solo se alcanza anonimizando a la persona (fn_anonymize_person).' using errcode = 'BV502';
    end if;

    -- E14 f2b: «albergada» (ingreso) y «salida del albergue» (egreso) llevan la fecha del movimiento; solo se alcanzan
    -- por fn_change_shelter_status, que registra el estatus y la fecha en una sola operación
    if p_axis_code = 'shelter_status' and p_new_value_code in ('sheltered', 'left_shelter')
       and coalesce(current_setting('bv.shelter_date', true), '') <> 'on' then
        raise exception 'El ingreso y la salida del albergue llevan la fecha del movimiento: usa el cambio de alojamiento con fecha.' using errcode = 'BV328';
    end if;

    select id into v_axis_id from public.status_axis where organization_id = v_org_id and code = p_axis_code;
    if v_axis_id is null then
        raise exception 'Eje de estatus no válido para esta organización.' using errcode = 'BV206';
    end if;

    select id into v_new_val_id
    from public.status_value
    where axis_id = v_axis_id and code = p_new_value_code;

    if v_new_val_id is null then
        raise exception 'Valor de estatus destino no encontrado en el catálogo.' using errcode = 'BV207';
    end if;

    select cs.id, sv.code into v_old_status_id, v_old_val_code
    from public.case_status cs
    join public.status_value sv on sv.id = cs.value_id
    where cs.case_id = p_case_id and cs.axis_id = v_axis_id and cs.valid_to is null;

    if v_old_val_code = 'anonymized' then
        raise exception 'Violación de Ethos: Un expediente en estatus anonimizado es terminal e irreversible.' using errcode = 'BV503';
    end if;

    -- Reapertura: salir de «cerrado» es facultad de Dirección (BV-2.3)
    if p_axis_code = 'record_status' and v_old_val_code = 'closed' and p_new_value_code <> 'closed' then
        if not public.has_role('director') then
            raise exception 'Permiso denegado: Reabrir un expediente cerrado es facultad exclusiva de Dirección.' using errcode = 'BV112';
        end if;
    end if;

    -- Regla Dura 7: se cierra el vigente y se abre uno nuevo en la misma transacción
    if v_old_status_id is not null then
        update public.case_status
        set valid_to = now()
        where id = v_old_status_id;
    end if;

    insert into public.case_status (
        organization_id, case_id, axis_id, value_id, valid_from, valid_to, reason, created_by
    ) values (
        v_org_id, p_case_id, v_axis_id, v_new_val_id, now(), null, p_reason, v_user_id
    ) returning id into v_new_status_id;

    if p_axis_code = 'record_status' and p_new_value_code = 'closed' then
        update public.case
        set closed_at = now(), closed_by = v_user_id, closure_reason = p_reason
        where id = p_case_id;
    end if;

    return v_new_status_id;
end;
$function$;

create or replace function public.fn_change_shelter_status(
    p_case_id uuid,
    p_new_value_code text,
    p_reason text,
    p_date date,
    p_precision text
)
returns uuid
security definer
set search_path = public
language plpgsql as $$
declare
    v_status_id uuid;
begin
    if auth.uid() is null or public.current_organization_id() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: cambiar el alojamiento exige un rol que opere expedientes (E14).' using errcode = 'BV120';
    end if;
    perform public.fn_assert_same_org('case', p_case_id);

    if p_new_value_code is null or p_new_value_code not in ('sheltered', 'left_shelter') then
        raise exception 'Solo el ingreso y la salida del albergue llevan fecha: los demás estatus de alojamiento se cambian sin ella.' using errcode = 'BV329';
    end if;
    if p_date is null then
        raise exception 'La fecha del movimiento es obligatoria.' using errcode = 'BV325';
    end if;

    -- El estatus primero (valida rol, motivo y catálogo); la bandera vale solo dentro de esta transacción
    perform set_config('bv.shelter_date', 'on', true);
    v_status_id := public.fn_change_case_status(p_case_id, 'shelter_status', p_new_value_code, p_reason);
    perform set_config('bv.shelter_date', 'off', true);

    -- La fecha: ingreso o egreso. Si no cuadra, se levanta el error y todo se revierte (estatus incluido)
    perform public.fn_set_case_date(
        p_case_id,
        case p_new_value_code when 'sheltered' then 'shelter_entry' else 'shelter_exit' end,
        p_date,
        p_precision,
        p_reason
    );
    return v_status_id;
end;
$$;
revoke execute on function public.fn_change_shelter_status(uuid, text, text, date, text) from public, anon;
grant execute on function public.fn_change_shelter_status(uuid, text, text, date, text) to authenticated;
