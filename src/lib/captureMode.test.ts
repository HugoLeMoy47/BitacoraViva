import { describe, expect, it, vi } from 'vitest';
import { enterCaptureMode, isCaptureMode, subscribeCaptureMode } from './captureMode';

// El modo captura oculta la navegación inferior del celular mientras haya una barra de acciones en pantalla
// (formularios y asistentes): evita apilar tres barras fijas sobre el contenido.
describe('modo captura', () => {
  it('empieza apagado', () => {
    expect(isCaptureMode()).toBe(false);
  });

  it('se enciende al entrar y se apaga al salir', () => {
    const leave = enterCaptureMode();
    expect(isCaptureMode()).toBe(true);
    leave();
    expect(isCaptureMode()).toBe(false);
  });

  it('sigue encendido mientras quede alguna barra en pantalla', () => {
    const a = enterCaptureMode();
    const b = enterCaptureMode();
    a();
    expect(isCaptureMode()).toBe(true);
    b();
    expect(isCaptureMode()).toBe(false);
  });

  it('salir dos veces con el mismo permiso no descuenta de más', () => {
    const a = enterCaptureMode();
    const b = enterCaptureMode();
    a();
    a();
    expect(isCaptureMode()).toBe(true);
    b();
    expect(isCaptureMode()).toBe(false);
  });

  it('avisa a quien escucha solo cuando cambia', () => {
    const listener = vi.fn();
    const unsubscribe = subscribeCaptureMode(listener);
    const leave = enterCaptureMode();
    leave();
    expect(listener).toHaveBeenCalledTimes(2);
    unsubscribe();
    enterCaptureMode()();
    expect(listener).toHaveBeenCalledTimes(2);
  });
});
