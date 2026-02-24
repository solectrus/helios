import { defineConfig } from 'vite';
import ViteRails from 'vite-plugin-rails';
import tailwindcss from '@tailwindcss/vite';
export default defineConfig(() => ({
  plugins: [
    tailwindcss(),
    ViteRails({
      fullReload: {
        additionalPaths: [
          'config/routes.rb',
          'app/views/**/*',
          'app/components/**/*',
          'app/**/*.rb',
          'config/locales/**/*.yml',
        ],
      },
    }),
  ],
  build: {
    rollupOptions: {
      output: {
        manualChunks(id: string) {
          if (id.includes('node_modules')) {
            return 'vendor';
          }
        },
      },
    },
    chunkSizeWarningLimit: 620,
  },
  server: {
    hmr: {
      host: 'vite.helios.localhost',
      clientPort: 443,
    },
  },
}));
