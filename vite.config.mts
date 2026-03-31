import { defineConfig } from 'vite';
import RailsVite from 'rails-vite-plugin';
import tailwindcss from '@tailwindcss/vite';
import { compression } from 'vite-plugin-compression2';

export default defineConfig(() => ({
  plugins: [
    tailwindcss(),
    compression({ algorithm: 'gzip' }),
    compression({ algorithm: 'brotliCompress' }),
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
        codeSplitting: {
          groups: [
            {
              test: /node_modules\/survey/,
              name: 'survey',
            },
            {
              test: /node_modules/,
              name: 'vendor',
            },
          ],
        },
      },
    },
    chunkSizeWarningLimit: 1500,
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
