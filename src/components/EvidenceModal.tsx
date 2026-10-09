import React, { useCallback, useEffect, useRef, useState } from 'react';
import { Camera, Eye, Image as ImageIcon, X } from 'lucide-react';
import { t } from '../lib/i18n';
import { formatDate } from '../lib/format';
import { EVIDENCE_MIME_TYPES } from '../lib/evidence';
import { evidenceApi, taskErrorMessage } from '../lib/tasks';
import { useToast } from '../lib/toast';
import { Task, TaskEvidence } from '../types/database';
import { ModalShell } from './ModalShell';

// Evidencia fotográfica de una tarea (BV-7.14, BV-7.15).
//  · Las fotos viven en un bucket PRIVADO: no existe una dirección que se pueda copiar y pegar. «Ver» pide
//    permiso a la base —que deja constancia del acceso— y firma una dirección que caduca en 60 s; la imagen
//    ya cargada sigue visible, la dirección no.
//  · Nada se reemplaza ni se borra: una foto equivocada se corrige subiendo otra.

interface EvidenceModalProps {
  task: Task;
  /** Puede subir fotos: quien tiene la tarea asignada y abierta, o la coordinación */
  canUpload: boolean;
  busy: boolean;
  /** Sube la foto y devuelve si quedó guardada */
  onUpload: (taskId: string, file: File) => Promise<boolean>;
  onClose: () => void;
}

const SECONDARY =
  'inline-flex min-h-11 items-center justify-center gap-1.5 rounded-lg border border-gray-300 bg-white px-4 text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:opacity-50';

function formatSize(bytes: number): string {
  return bytes >= 1024 * 1024 ? `${(bytes / (1024 * 1024)).toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`;
}

export const EvidenceModal: React.FC<EvidenceModalProps> = ({ task, canUpload, busy, onUpload, onClose }) => {
  const toast = useToast();
  const [items, setItems] = useState<TaskEvidence[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [openingId, setOpeningId] = useState<string | null>(null);
  const [shown, setShown] = useState<{ id: string; url: string } | null>(null);
  const cameraRef = useRef<HTMLInputElement>(null);
  const galleryRef = useRef<HTMLInputElement>(null);

  const refresh = useCallback(async () => {
    try {
      setItems(await evidenceApi.list(task.id));
      setFailed(false);
    } catch (e) {
      setFailed(true);
      toast.error(taskErrorMessage(e));
    }
  }, [task.id, toast]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  const view = async (ev: TaskEvidence) => {
    setOpeningId(ev.id);
    try {
      setShown({ id: ev.id, url: await evidenceApi.open(ev.id) });
    } catch (e) {
      toast.error(taskErrorMessage(e));
    } finally {
      setOpeningId(null);
    }
  };

  const picked = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    if (await onUpload(task.id, file)) await refresh();
  };

  const accept = EVIDENCE_MIME_TYPES.join(',');

  return (
    <ModalShell onClose={onClose} className="fixed inset-0 z-50 flex items-center justify-center bg-carbon/60 p-4 backdrop-blur-sm">
      <div className="flex max-h-[90vh] w-full max-w-lg flex-col rounded-xl bg-white shadow-2xl">
        <div className="flex items-center justify-between border-b border-gray-100 px-6 py-4">
          <div className="flex min-w-0 items-center gap-2">
            <Camera className="h-5 w-5 shrink-0 text-turquesa-dark" aria-hidden="true" />
            <h3 className="truncate text-base font-bold text-carbon">{t('tasks.evidence.title')}</h3>
          </div>
          <button type="button" onClick={onClose} aria-label={t('common.close')} className="flex h-11 w-11 items-center justify-center rounded-lg text-gray-600 hover:bg-gray-100">
            <X className="h-5 w-5" aria-hidden="true" />
          </button>
        </div>

        <div className="space-y-4 overflow-y-auto px-6 py-5">
          <p className="break-words text-sm font-semibold text-carbon">{task.name}</p>
          <p className="text-xs text-gray-600">{t('tasks.evidence.privacy')}</p>

          {canUpload ? (
            <div>
              <div className="flex flex-wrap gap-2">
                <button type="button" onClick={() => cameraRef.current?.click()} disabled={busy} className="inline-flex min-h-11 items-center gap-1.5 rounded-lg bg-turquesa px-4 text-sm font-semibold text-carbon hover:bg-turquesa-hover disabled:opacity-50">
                  <Camera className="h-4 w-4" aria-hidden="true" />
                  {t('tasks.evidence.take')}
                </button>
                <button type="button" onClick={() => galleryRef.current?.click()} disabled={busy} className={SECONDARY}>
                  <ImageIcon className="h-4 w-4" aria-hidden="true" />
                  {t('tasks.evidence.choose')}
                </button>
              </div>
              <input ref={cameraRef} type="file" accept={accept} capture="environment" onChange={picked} className="sr-only" tabIndex={-1} aria-label={t('tasks.evidence.take')} data-testid="evidence-camera" />
              <input ref={galleryRef} type="file" accept={accept} onChange={picked} className="sr-only" tabIndex={-1} aria-label={t('tasks.evidence.choose')} data-testid="evidence-gallery" />
              <p className="mt-2 text-xs text-gray-600">{t('tasks.evidence.limits')}</p>
              {busy && <p className="mt-2 text-xs font-medium text-turquesa-dark" role="status">{t('tasks.evidence.uploading')}</p>}
            </div>
          ) : (
            <p className="rounded-lg border border-gray-200 bg-gray-50 px-3 py-2 text-xs text-gray-700">{t('tasks.evidence.read_only')}</p>
          )}

          <div>
            <h4 className="text-xs font-semibold uppercase tracking-wide text-gray-600">{t('tasks.evidence.list_title')}</h4>
            {failed ? (
              <p className="mt-2 text-sm text-gray-600">{t('tasks.evidence.load_failed')}</p>
            ) : items === null ? (
              <p className="mt-2 text-sm text-gray-600">{t('session.loading')}</p>
            ) : items.length === 0 ? (
              <p className="mt-2 rounded-lg border border-dashed border-gray-300 px-3 py-5 text-center text-sm text-gray-600">{t('tasks.evidence.empty')}</p>
            ) : (
              <ul className="mt-2 space-y-2">
                {items.map((ev, i) => (
                  <li key={ev.id} className="rounded-lg border border-gray-200 p-3">
                    <div className="flex items-center justify-between gap-3">
                      <div className="min-w-0 text-sm">
                        <p className="font-medium text-carbon">{t('tasks.evidence.photo_n').replace('{n}', String(items.length - i))}</p>
                        <p className="text-xs text-gray-600">
                          {formatDate(ev.created_at)} · {formatSize(ev.size_bytes)}
                        </p>
                      </div>
                      <button type="button" onClick={() => view(ev)} disabled={openingId === ev.id} className={SECONDARY}>
                        <Eye className="h-4 w-4" aria-hidden="true" />
                        {t('tasks.evidence.view')}
                      </button>
                    </div>
                    {shown?.id === ev.id && (
                      <img src={shown.url} alt={t('tasks.evidence.photo_alt').replace('{task}', task.name)} className="mt-3 max-h-80 w-full rounded-lg border border-gray-200 object-contain" />
                    )}
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>

        <div className="flex justify-end border-t border-gray-100 px-6 py-3">
          <button type="button" onClick={onClose} className={SECONDARY}>
            {t('common.close')}
          </button>
        </div>
      </div>
    </ModalShell>
  );
};
