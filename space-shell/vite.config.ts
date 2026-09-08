import { defineConfig } from 'vite'

// Builds the space-shell runtime as a single self-contained IIFE that bundles
// vue + the host packages. Output is copied into the macOS app's resources and
// served to the WKWebView as `__runtime__.js`.
export default defineConfig({
  define: {
    'process.env.NODE_ENV': JSON.stringify('production'),
    '__VUE_OPTIONS_API__': 'true',
    '__VUE_PROD_DEVTOOLS__': 'false',
    '__VUE_PROD_HYDRATION_MISMATCH_DETAILS__': 'false',
  },
  build: {
    target: 'safari17',
    cssCodeSplit: false,
    lib: {
      entry: 'src/index.ts',
      name: 'ConstructSpaceShell',
      formats: ['iife'],
      fileName: () => 'space-shell.js',
    },
    rollupOptions: {
      output: {
        // Inline everything; the WKWebView loads a single file offline.
        inlineDynamicImports: true,
        assetFileNames: 'space-shell.[ext]',
      },
    },
    outDir: 'dist',
    emptyOutDir: true,
  },
})
