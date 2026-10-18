# invite-user (ADR-0010)

Función de borde **delgada** para dar de alta a una persona. La regla de quién puede invitar vive en la base
(`fn_prepare_invitation`, con la sesión de quien invita; `fn_complete_invitation`, solo para la llave de servicio). La función
solo invita por correo y deshace si algo falla.

- `handler.ts`: la lógica, sin dependencias de Deno (se prueba con `npm run test:unit`).
- `index.ts`: el cableado con la llave de servicio, que inyecta Supabase.

## Secretos del proyecto (los pone una persona, no el repositorio)

| Secreto | Qué es |
|---|---|
| `ALLOWED_ORIGINS` | Orígenes de la aplicación, separados por coma (por ejemplo, la URL publicada y `http://localhost:5173`) |
| `INVITE_REDIRECT_URL` | Adonde lleva el enlace del correo: la pantalla para elegir contraseña, `/?bienvenida=1` (fija; no viene de la petición). Se usa un parámetro de consulta y no `#/…` porque Supabase añade los datos de la sesión como fragmento (`#access_token=…`) |

`SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY` los inyecta Supabase.

```bash
npx supabase secrets set ALLOWED_ORIGINS="https://…,http://localhost:5173" INVITE_REDIRECT_URL="https://…/?bienvenida=1"
```

## Despliegue (con confirmación del Product Owner, como `db push`)

```bash
npx supabase functions deploy invite-user
```

La función exige un JWT válido (`verify_jwt`). Para quitarla: `npx supabase functions delete invite-user`.

## Antes de usarla con cuentas reales

- **MFA (D-13):** pendiente; no invitar cuentas reales de dirección hasta cerrarlo.
- **Correo propio:** el correo predeterminado de Supabase es solo para la demo; para producción, configurar un SMTP propio.
- **Autenticación → URL Configuration:** la *Site URL* y la lista de *Redirect URLs* deben incluir la dirección publicada (por ejemplo `https://…/**`); si no, el enlace del correo no lleva a la pantalla de bienvenida.
- **Registro público desactivado** en la configuración de Auth del proyecto.
- **Rotar la llave de servicio** si se sospecha que se expuso.
