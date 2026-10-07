import React, { createContext, useContext } from 'react';
import { Area, StatusAxis, StatusAxisCode, StatusValue } from '../types/database';

// Catálogos de la organización (áreas, ejes y valores de estatus) cargados desde la base.
export interface Catalog {
  areas: Area[];
  statusAxes: StatusAxis[];
  statusValues: Record<StatusAxisCode, StatusValue[]>;
  organizationName: string;
  /** Datos del responsable declarados por la asociación (aviso de privacidad y extracto ARCO) */
  organizationInfo: { responsibleName: string; responsibleAddress: string; arcoContact: string };
  userNames: Record<string, string>;
}

const EMPTY: Catalog = {
  organizationName: '',
  organizationInfo: { responsibleName: '', responsibleAddress: '', arcoContact: '' },
  userNames: {},
  areas: [],
  statusAxes: [],
  statusValues: {
    legal_status: [],
    engagement_status: [],
    shelter_status: [],
    record_status: [],
    case_stage: [],
  },
};

const CatalogContext = createContext<Catalog>(EMPTY);

export const CatalogProvider: React.FC<{ value: Catalog; children: React.ReactNode }> = ({ value, children }) => (
  <CatalogContext.Provider value={value}>{children}</CatalogContext.Provider>
);

export function useCatalog(): Catalog {
  return useContext(CatalogContext);
}
