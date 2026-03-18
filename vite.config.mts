import { defineConfig } from 'vite';
import RailsVite from 'rails-vite-plugin';
import tailwindcss from '@tailwindcss/vite';
export default defineConfig(() => ({
  plugins: [
    tailwindcss(),
    RailsVite({
      sourceDir: 'app/frontend',
      refresh: [
        'config/routes.rb',
        'app/views/**/*',
        'app/components/**/*',
        'app/**/*.rb',
        'config/locales/**/*.yml',
      ],
    }),
  ],
  build: {
    rolldownOptions: {
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
    port: 3036,
    hmr: {
      host: 'vite.helios.localhost',
      clientPort: 443,
      protocol: 'wss',
    },
  },
}));
