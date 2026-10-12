import React from 'react';

// Norma de usabilidad: ningún botón deshabilitado sin decir por qué.
// El motivo es texto visible (un tooltip no existe en celular ni con teclado) y el botón lo enlaza con
// aria-describedby para que también lo lea un lector de pantalla. `audit:ui` lo comprueba en cada pantalla.
export const reasonId = (base: string) => `${base}-motivo`;

export const DisabledReason: React.FC<{ id: string; reason: string | null; className?: string }> = ({ id, reason, className = '' }) =>
  reason ? (
    <p id={reasonId(id)} role="status" className={`text-xs text-gray-700 ${className}`}>
      {reason}
    </p>
  ) : null;

// Atributo para el botón: lo enlaza con su explicación mientras esté deshabilitado.
export const describedBy = (id: string, reason: string | null) => (reason ? { 'aria-describedby': reasonId(id) } : {});
