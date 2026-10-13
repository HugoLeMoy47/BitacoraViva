import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'url';
import path from 'path';
import { execSync } from 'child_process';
import { readFileSync } from 'fs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Versión visible en el pie y en /version.json: número del paquete + commit + fecha de compilación.
// Sirve para comprobar qué hay publicado en la URL.
const pkg = JSON.parse(readFileSync(path.resolve(__dirname, 'package.json'), 'utf8'));
const commit = (() => {
  // BUILD_COMMIT lo fija el despliegue (el commit que se compila); GITHUB_SHA es el último de main y puede ser otro
  const explicit = process.env.BUILD_COMMIT || process.env.GITHUB_SHA;
  if (explicit) return explicit.slice(0, 7);
  try {
    return execSync('git rev-parse --short=7 HEAD', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
  } catch {
    return 'local';
  }
})();
const buildInfo = { version: pkg.version as string, commit, built: new Date().toISOString() };

export default defineConfig({
  define: { __BUILD_INFO__: JSON.stringify(buildInfo) },
  plugins: [
    react(),
    {
      name: 'version-json',
      generateBundle() {
        this.emitFile({ type: 'asset', fileName: 'version.json', source: JSON.stringify(buildInfo) });
      },
    },
  ],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 5173,
    host: true,
  },
});
