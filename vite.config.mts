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
            // survey-core and highlight.js are only reached via dynamic
            // import() (survey_controller / stack_preview_controller), so
            // giving each its own group keeps them out of the eagerly-loaded
            // vendor chunk — they load on demand on the few pages that use
            // them. Order matters: specific groups must precede the catch-all.
            {
              test: /node_modules\/survey|utils\/survey_theme/,
              name: 'survey',
            },
            {
              test: /node_modules\/highlight\.js/,
              name: 'highlight',
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
