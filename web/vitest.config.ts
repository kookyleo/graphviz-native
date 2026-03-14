import { defineConfig } from 'vitest/config';
import path from 'path';

export default defineConfig({
  test: {
    environment: 'happy-dom',
    globals: true,
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      exclude: [
        'node_modules/',
        'dist/',
        'src/**/*.d.ts',
      ],
    },
  },
  resolve: {
    alias: {
      'output/wasm/viz.js': path.resolve(__dirname, '../output/wasm/viz.js'),
    },
  },
});
