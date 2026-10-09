// Exportación a CSV (BV-7.8).
//
// Formato: separador PUNTO Y COMA y BOM de UTF-8. Excel en español interpreta la coma como separador
// decimal, así que un CSV separado por comas se abre con todo amontonado en una sola columna; el punto y
// coma es lo que espera, y el BOM evita que los acentos se vean como «Ã³». Google Sheets y LibreOffice
// aceptan ambos sin problema.

export const CSV_SEPARATOR = ';';

/** Caracteres con los que una hoja de cálculo empieza a leer una celda como fórmula en vez de texto. */
const FORMULA_STARTS = ['=', '+', '-', '@', '\t', '\r'];

/**
 * Neutraliza la inyección de fórmulas. El entrecomillado de CSV es correcto para el formato pero NO
 * impide que la hoja evalúe la celda: una tarea llamada `=1+1` se abre como fórmula, y con las
 * funciones adecuadas eso llega a ejecutar comandos en la máquina de quien abre el archivo. Este CSV
 * está hecho justamente para salir a la computadora de un tercero. La mitigación estándar es anteponer
 * un apóstrofo: las tres hojas de cálculo lo consumen y muestran el texto tal cual. No hay daño
 * colateral: ninguna columna exportada es numérica (son nombres, estados y fechas).
 */
export function neutralizeFormula(text: string): string {
  return FORMULA_STARTS.includes(text[0]) ? `'${text}` : text;
}

/** Escapa un valor: primero la guarda de fórmulas, luego el entrecomillado estándar de CSV. */
export function escapeField(value: unknown): string {
  if (value === null || value === undefined) return '';
  const text = neutralizeFormula(String(value));
  if (text === '') return '';
  if (text.includes(CSV_SEPARATOR) || text.includes('"') || text.includes('\n') || text.includes('\r')) {
    return `"${text.replace(/"/g, '""')}"`;
  }
  return text;
}

export interface CsvColumn {
  key: string;
  title: string;
}

/** Construye el contenido. CRLF: es lo que Excel espera para respetar saltos de línea dentro de celdas. */
export function buildCsv(columns: CsvColumn[], rows: Record<string, unknown>[]): string {
  const header = columns.map((c) => escapeField(c.title)).join(CSV_SEPARATOR);
  const body = rows.map((row) => columns.map((c) => escapeField(row[c.key])).join(CSV_SEPARATOR));
  return [header, ...body].join('\r\n');
}

/** Nombre con marca de tiempo local, para que descargas repetidas no se sobrescriban. */
export function csvFileName(prefix: string, view: string, now: Date = new Date()): string {
  const stamp = [
    now.getFullYear(),
    String(now.getMonth() + 1).padStart(2, '0'),
    String(now.getDate()).padStart(2, '0'),
    '_',
    String(now.getHours()).padStart(2, '0'),
    String(now.getMinutes()).padStart(2, '0'),
  ].join('');
  const clean = (s: string) =>
    s
      .toLowerCase()
      .normalize('NFD')
      .replace(/[̀-ͯ]/g, '')
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '');
  return `${clean(prefix)}_${clean(view)}_${stamp}.csv`;
}

/** Dispara la descarga. Aislado para que lo anterior siga siendo puro y revisable. */
export function downloadCsv(fileName: string, content: string): void {
  const blob = new Blob(['﻿' + content], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = fileName;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}
