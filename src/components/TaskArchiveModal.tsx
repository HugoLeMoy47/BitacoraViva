import React from 'react';
import { Archive } from 'lucide-react';
import { t } from '../lib/i18n';
import { Task } from '../types/database';
import { ModalShell } from './ModalShell';

// Confirmación de la baja lógica. Ninguna tarea se borra (Regla Dura 3): archivar la saca del
// tablero pero conserva su historia y su auditoría, y es definitivo. La interfaz lo dice ANTES.

interface TaskArchiveModalProps {
  task: Task;
  busy: boolean;
  onClose: () => void;
  onConfirm: () => void;
}

export const TaskArchiveModal: React.FC<TaskArchiveModalProps> = ({ task, busy, onClose, onConfirm }) => (
  <ModalShell onClose={onClose} className="fixed inset-0 z-50 flex items-center justify-center bg-carbon/60 p-4 backdrop-blur-sm">
    <div className="w-full max-w-md rounded-xl bg-white shadow-2xl">
      <div className="flex items-center gap-2 border-b border-gray-100 px-6 py-4">
        <Archive className="h-5 w-5 text-alerta-dark" aria-hidden="true" />
        <h3 className="text-base font-bold text-carbon">{t('tasks.archive_title')}</h3>
      </div>
      <div className="space-y-3 px-6 py-5 text-sm text-carbon">
        <p className="break-words font-semibold">{task.name}</p>
        <p className="rounded-lg border border-alerta/20 bg-alerta-bg p-3 text-xs text-alerta-dark">{t('tasks.archive_body')}</p>
      </div>
      <div className="flex items-center justify-end gap-3 border-t border-gray-100 px-6 py-4">
        <button type="button" onClick={onClose} className="min-h-11 rounded-lg border border-gray-300 px-4 text-sm font-medium text-gray-700 hover:bg-gray-50">
          {t('common.cancel')}
        </button>
        <button
          type="button"
          onClick={onConfirm}
          disabled={busy}
          className="inline-flex min-h-11 items-center gap-2 rounded-lg bg-carbon px-4 text-sm font-semibold text-white hover:bg-carbon-light disabled:opacity-60"
        >
          <Archive className="h-4 w-4" aria-hidden="true" />
          {t('tasks.archive_confirm')}
        </button>
      </div>
    </div>
  </ModalShell>
);
