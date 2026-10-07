-- La identidad de la organización ya se audita con el disparador trg_audit_organization;
-- la función no debe escribir un segundo evento por el mismo cambio.
create or replace function public.fn_update_organization_identity(
    p_display_name text,
    p_legal_name text,
    p_folio_prefix text,
    p_about_text text,
    p_responsible_name text,
    p_responsible_address text,
    p_responsible_contact text,
    p_arco_contact text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_org uuid;
    v_prefix text;
begin
    if auth.uid() is null or not public.has_role('director') then
        raise exception 'Acceso denegado: solo la dirección configura la organización.';
    end if;
    v_org := public.current_organization_id();
    if v_org is null then
        raise exception 'Acceso denegado: sin organización.';
    end if;
    if coalesce(btrim(p_display_name), '') = '' or coalesce(btrim(p_legal_name), '') = '' then
        raise exception 'El nombre y la razón social son obligatorios.';
    end if;
    v_prefix := nullif(upper(btrim(coalesce(p_folio_prefix, ''))), '');
    if v_prefix is not null and v_prefix !~ '^[A-Z]{2,5}$' then
        raise exception 'El prefijo del folio debe tener de 2 a 5 letras (A–Z).';
    end if;

    update public.organization set
        display_name = btrim(p_display_name),
        legal_name = btrim(p_legal_name),
        folio_prefix = v_prefix,
        about_text = nullif(btrim(coalesce(p_about_text, '')), ''),
        responsible_name = nullif(btrim(coalesce(p_responsible_name, '')), ''),
        responsible_address = nullif(btrim(coalesce(p_responsible_address, '')), ''),
        responsible_contact = nullif(btrim(coalesce(p_responsible_contact, '')), ''),
        arco_contact = nullif(btrim(coalesce(p_arco_contact, '')), ''),
        updated_at = now()
    where id = v_org;

    -- La auditoría la escribe el disparador trg_audit_organization (un evento por cambio, con antes y después).

    return v_org;
end;
$$;

revoke execute on function public.fn_update_organization_identity(text, text, text, text, text, text, text, text) from public, anon;
grant execute on function public.fn_update_organization_identity(text, text, text, text, text, text, text, text) to authenticated;
