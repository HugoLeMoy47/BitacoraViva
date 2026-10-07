import React, { useState } from 'react';
import { X, Edit3, Save, AlertCircle } from 'lucide-react';
import { t } from '../lib/i18n';
import { Person } from '../types/database';

interface RectifyPersonModalProps {
  isOpen: boolean;
  onClose: () => void;
  person: Person;
  onRectify: (updates: Partial<Person>, reason: string) => void;
}

export const RectifyPersonModal: React.FC<RectifyPersonModalProps> = ({
  isOpen,
  onClose,
  person,
  onRectify,
}) => {
  const [givenName, setGivenName] = useState(person.given_name);
  const [paternalName, setPaternalName] = useState(person.paternal_family_name);
  const [maternalName, setMaternalName] = useState(person.maternal_family_name || '');
  const [preferredName, setPreferredName] = useState(person.preferred_name || '');
  const [birthDate, setBirthDate] = useState(person.birth_date);
  const [birthEstimated, setBirthEstimated] = useState(person.birth_date_is_estimated);
  const [phone, setPhone] = useState(person.phone_number || '');
  const [email, setEmail] = useState(person.email || '');
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);

  if (!isOpen) return null;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!reason.trim()) {
      setError(t('arco.modal_rectify.reason_placeholder'));
      return;
    }

    onRectify(
      {
        given_name: givenName.trim(),
        paternal_family_name: paternalName.trim(),
        maternal_family_name: maternalName.trim() || null,
        preferred_name: preferredName.trim() || null,
        birth_date: birthDate,
        birth_date_is_estimated: birthEstimated,
        phone_number: phone.trim() || null,
        email: email.trim() || null,
      },
      reason.trim()
    );
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 overflow-y-auto">
      <div className="bg-white rounded-xl shadow-2xl max-w-xl w-full overflow-hidden border border-gray-100 animate-in fade-in zoom-in-95 duration-200">
        {/* Encabezado */}
        <div className="bg-carbon px-6 py-4 flex items-center justify-between text-white border-b border-carbon-muted/20">
          <div className="flex items-center gap-2">
            <Edit3 className="w-5 h-5 text-turquesa" />
            <div>
              <h3 className="text-sm font-bold tracking-wide">
                {t('arco.modal_rectify.title')}
              </h3>
              <p className="text-xs text-gray-300">
                {person.given_name} {person.paternal_family_name}
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="text-gray-500 hover:text-white p-1 rounded transition"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Formulario */}
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <p className="text-xs text-gray-600">
            {t('arco.modal_rectify.subtitle')}
          </p>

          {error && (
            <div className="flex items-center gap-2 p-3 bg-red-50 border border-red-200 rounded-lg text-xs text-red-700">
              <AlertCircle className="w-4 h-4 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-semibold text-carbon mb-1" htmlFor="rectif-1">
                {t('arco.modal_rectify.given_name')}
              </label>
              <input id="rectif-1" name="rectif-1" autoComplete="off"
                type="text"
                required
                value={givenName}
                onChange={(e) => setGivenName(e.target.value)}
                className="w-full text-xs rounded-lg border-gray-300 border p-2 focus:ring-1 focus:ring-turquesa focus:outline-none"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-carbon mb-1" htmlFor="rectif-2">
                {t('arco.modal_rectify.paternal_name')}
              </label>
              <input id="rectif-2" name="rectif-2" autoComplete="off"
                type="text"
                required
                value={paternalName}
                onChange={(e) => setPaternalName(e.target.value)}
                className="w-full text-xs rounded-lg border-gray-300 border p-2 focus:ring-1 focus:ring-turquesa focus:outline-none"
              />
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-semibold text-carbon mb-1" htmlFor="rectif-3">
                {t('arco.modal_rectify.maternal_name')}
              </label>
              <input id="rectif-3" name="rectif-3" autoComplete="off"
                type="text"
                value={maternalName}
                onChange={(e) => setMaternalName(e.target.value)}
                className="w-full text-xs rounded-lg border-gray-300 border p-2 focus:ring-1 focus:ring-turquesa focus:outline-none"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-carbon mb-1" htmlFor="rectif-4">
                {t('arco.modal_rectify.preferred_name')}
              </label>
              <input id="rectif-4" name="rectif-4" autoComplete="off"
                type="text"
                value={preferredName}
                onChange={(e) => setPreferredName(e.target.value)}
                className="w-full text-xs rounded-lg border-gray-300 border p-2 focus:ring-1 focus:ring-turquesa focus:outline-none"
              />
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-semibold text-carbon mb-1" htmlFor="rectif-5">
                {t('arco.modal_rectify.birth_date')}
              </label>
              <input id="rectif-5" name="rectif-5" autoComplete="off"
                type="date"
                required
                value={birthDate}
                onChange={(e) => setBirthDate(e.target.value)}
                className="w-full text-xs rounded-lg border-gray-300 border p-2 focus:ring-1 focus:ring-turquesa focus:outline-none"
              />
              <div className="flex items-center gap-1.5 mt-1.5">
                <input
                  type="checkbox"
                  id="rect_est_birth"
                  checked={birthEstimated}
                  onChange={(e) => setBirthEstimated(e.target.checked)}
                  className="rounded text-turquesa focus:ring-turquesa"
                />
                <label htmlFor="rect_est_birth" className="text-xs text-gray-500 cursor-pointer">
                  {t('arco.modal_rectify.birth_estimated')}
                </label>
              </div>
            </div>

            <div>
              <label className="block text-xs font-semibold text-carbon mb-1" htmlFor="rectif-6">
                {t('arco.modal_rectify.phone')}
              </label>
              <input id="rectif-6" name="rectif-6" autoComplete="off"
                type="text"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder={t('arco.modal_rectify.ph_phone')}
                className="w-full text-xs rounded-lg border-gray-300 border p-2 focus:ring-1 focus:ring-turquesa focus:outline-none"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-carbon mb-1" htmlFor="rectif-7">
              {t('arco.modal_rectify.email')}
            </label>
            <input id="rectif-7" name="rectif-7" autoComplete="off"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full text-xs rounded-lg border-gray-300 border p-2 focus:ring-1 focus:ring-turquesa focus:outline-none"
            />
          </div>

          <div className="pt-2">
            <label className="block text-xs font-bold text-carbon mb-1" htmlFor="rectif-8">
              {t('arco.modal_rectify.reason')} <span className="text-red-500">*</span>
            </label>
            <textarea id="rectif-8" name="rectif-8" autoComplete="off"
              rows={2}
              required
              value={reason}
              onChange={(e) => {
                setReason(e.target.value);
                if (error) setError(null);
              }}
              placeholder={t('arco.modal_rectify.reason_placeholder')}
              className="w-full text-xs rounded-lg border-gray-300 border p-2 focus:ring-1 focus:ring-turquesa focus:outline-none"
            />
          </div>

          <div className="pt-3 border-t border-gray-200 flex justify-end gap-2">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-xs font-semibold rounded-lg border border-gray-300 text-carbon hover:bg-gray-50 transition"
            >
              Cancelar
            </button>
            <button
              type="submit"
              className="px-4 py-2 text-xs font-semibold rounded-lg bg-turquesa text-carbon hover:bg-turquesa-light transition flex items-center gap-1.5 shadow-sm"
            >
              <Save className="w-4 h-4" />
              <span>{t('arco.modal_rectify.btn_save')}</span>
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
