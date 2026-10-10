import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

// Panel działa w każdej przeglądarce i instaluje się jako aplikacja (PWA) na Windows, macOS i Linux
// — bez osobnego klienta desktopowego (docs/01-project-brief.md, „Platformy").
export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      manifest: {
        name: 'FleetCore',
        short_name: 'FleetCore',
        description: 'Zarządzanie flotą: kartoteka, koszty, podatki, rozliczenia',
        lang: 'pl',
        display: 'standalone',
        start_url: '/',
        background_color: '#ffffff',
        theme_color: '#1f4e79',
        icons: [
          { src: '/icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: '/icon-512.png', sizes: '512x512', type: 'image/png' },
        ],
      },
      workbox: {
        // Dane API NIE są cache'owane przez service worker — panel pokazuje stan z serwera albo błąd,
        // nigdy wczorajsze dane bez ostrzeżenia. Offline-first dotyczy aplikacji mobilnej, nie panelu.
        navigateFallbackDenylist: [/^\/v1\//],
      },
    }),
  ],
  server: {
    port: 5173,
    proxy: { '/v1': 'http://localhost:3000' },
  },
});
