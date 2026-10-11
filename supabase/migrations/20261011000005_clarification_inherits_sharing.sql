-- ==============================================================================
-- Aclarar una entrada ya compartida: la aclaración le llega a quien recibió la original
-- (Ethos C2, C3 · ADR-0005 · ADR-0008)
--
-- Defecto hallado al auditar el 11 oct 2026: una aclaración (fe de erratas) de una entrada
-- `shared` heredaba la visibilidad `shared` pero no tenía `sharing_event`, y la política de
-- lectura de bitácora decide por `sharing_event`. Resultado: el área que recibió la
-- original NO veía la corrección, y seguía leyendo un dato equivocado.
--
-- Corrección: la aclaración copia las comparticiones de la entrada que corrige.
--   * Mismas áreas de origen y destino.
--   * Motivo genérico («hereda la compartición»): no se copia el texto libre del original.
--   * El acuse de Dirección se hereda tal cual: si la original está acusada, la copia también
--     (con la misma persona y momento); si estaba pendiente, la copia queda pendiente. Nunca se
--     inventa un acuse a nombre de otra persona (C4).
--   * Una nota de trabajo protegida no se comparte, así que no hereda nada (E-02).
-- El evento de auditoría de la aclaración dice cuántas comparticiones heredó.
-- ==============================================================================

create or replace function public.fn_create_clarification_note(
    p_superseded_entry_id uuid,
    p_body text,
    p_occurred_at timestamptz default now(),
    p_is_work_note boolean default false
)
returns uuid
security definer
set search_path = public
language plpgsql as $$
declare
    v_old_entry record;
    v_user_id uuid;
    v_new_entry_id uuid;
    v_work_note boolean;
    v_inherited int := 0;
begin
    if auth.uid() is null or not public.has_operational_role() then
        raise exception 'Acceso denegado: se requiere una sesión con rol operativo vigente.';
    end if;
    perform public.fn_assert_same_org('journal_entry', p_superseded_entry_id);
    v_user_id := auth.uid();

    if not public.fn_can_act_on_entry(p_superseded_entry_id) then
        raise exception 'Permiso denegado: solo la persona autora, el área de la entrada o Dirección pueden aclararla.';
    end if;

    if p_body is null or trim(p_body) = '' then
        raise exception 'El texto de la aclaración es obligatorio.';
    end if;

    select * into v_old_entry from public.journal_entry where id = p_superseded_entry_id;
    if v_old_entry.id is null then
        raise exception 'El registro de bitácora original a corregir no existe.';
    end if;

    if v_old_entry.superseded_by_id is not null then
        raise exception 'Este registro de bitácora ya ha sido superado por una aclaración previa.';
    end if;

    -- La aclaración de una nota de trabajo protegida es también nota de trabajo y nunca nace compartida (E-02)
    v_work_note := coalesce(p_is_work_note, false) or v_old_entry.is_work_note;

    insert into public.journal_entry (
        organization_id, case_id, area_id, author_user_id, entry_type_key,
        body, is_work_note, occurred_at, created_at, visibility
    ) values (
        v_old_entry.organization_id, v_old_entry.case_id, v_old_entry.area_id, v_user_id,
        v_old_entry.entry_type_key, p_body, v_work_note,
        coalesce(p_occurred_at, now()), now(),
        case when v_work_note then 'area_private' else v_old_entry.visibility end
    ) returning id into v_new_entry_id;

    -- La aclaración le llega a quien recibió la original (y hereda el estado real de su acuse)
    if v_old_entry.visibility = 'shared' and not v_work_note then
        insert into public.sharing_event (
            organization_id, journal_entry_id, case_id, from_area_id, to_area_id,
            from_visibility, to_visibility, reason, shared_by_user_id, shared_at,
            acknowledged_by_user_id, acknowledged_at
        )
        select s.organization_id, v_new_entry_id, s.case_id, s.from_area_id, s.to_area_id,
               s.from_visibility, s.to_visibility, 'Hereda la compartición de la entrada que aclara',
               v_user_id, now(), s.acknowledged_by_user_id, s.acknowledged_at
        from public.sharing_event s
        where s.journal_entry_id = p_superseded_entry_id;
        get diagnostics v_inherited = row_count;
    end if;

    update public.journal_entry
    set superseded_by_id = v_new_entry_id
    where id = p_superseded_entry_id;

    insert into public.audit_event (organization_id, user_id, action, table_name, record_id, new_values)
    values (v_old_entry.organization_id, v_user_id, 'CLARIFICATION', 'journal_entry', v_new_entry_id,
        jsonb_build_object(
            'case_id', v_old_entry.case_id,
            'superseded_entry_id', p_superseded_entry_id,
            'is_work_note', v_work_note,
            'inherited_sharing_events', v_inherited
        ));

    return v_new_entry_id;
end;
$$;
