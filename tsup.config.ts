import { defineConfig } from 'tsup';

// `clean` stays off in both builds: tsup runs them in parallel, so one build's clean
// could delete the other's output. `prepublishOnly` runs `npm run clean` first.
export default defineConfig([
  {
    entry: { index: 'src/index.ts', ui: 'src/ui/index.ts' },
    format: ['cjs', 'esm'],
    dts: true,
    splitting: false,
    sourcemap: true,
    clean: false,
    treeshake: true,
    minify: false,
    target: 'es2020',
    outDir: 'dist',
    esbuildOptions(options) {
      options.charset = 'utf8';
    }
  },
  {
    entry: { 'feedbackkit-ui': 'src/ui/global.ts' },
    format: ['iife'],
    globalName: 'FeedbackKitUI',
    dts: false,
    sourcemap: true,
    clean: false,
    minify: true,
    target: 'es2020',
    outDir: 'dist',
    esbuildOptions(options) {
      options.charset = 'utf8';
    }
  }
]);
