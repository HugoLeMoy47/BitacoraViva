-- ==============================================================================
-- Regla Dura 7: el estatus no se sobrescribe (se cierra el vigente y se abre uno nuevo)
--
-- Hallazgo (pruebas negativas de RLS): la politica de UPDATE de case_status se llama
-- "restringida al cierre de vigencia" pero solo comprueba organizacion y rol, no
-- columnas. Un caseworker podia cambiar value_id del estatus vigente con un UPDATE
-- directo, sin historial.
--
-- Se impone en la base, para cualquier rol (incluido el propietario), igual que el
-- candado de audit_event: la unica modificacion permitida sobre una fila es cerrar
-- su vigencia (valid_to de NULL a una fecha). Es exactamente lo que hace
-- fn_change_case_status, que no se ve afectada.
-- ==============================================================================

create or replace function public.fn_enforce_case_status_append_only()
returns trigger
language plpgsql as $$
begin
    if old.valid_to is not null then
        raise exception 'Violación de Regla Dura 7: un estatus ya cerrado es inmutable.';
    end if;

    if new.valid_to is null then
        raise exception 'Violación de Regla Dura 7: el estatus no se sobrescribe. Cierre la vigencia y abra uno nuevo con fn_change_case_status.';
    end if;

    if (to_jsonb(new) - 'valid_to') is distinct from (to_jsonb(old) - 'valid_to') then
        raise exception 'Violación de Regla Dura 7: de un estatus solo puede cambiar el cierre de su vigencia (valid_to).';
    end if;

    if new.valid_to < old.valid_from then
        raise exception 'El cierre de vigencia no puede ser anterior a su inicio.';
    end if;

    return new;
end;
$$;

drop trigger if exists trg_case_status_append_only on public.case_status;
create trigger trg_case_status_append_only
before update on public.case_status
for each row execute function public.fn_enforce_case_status_append_only();
