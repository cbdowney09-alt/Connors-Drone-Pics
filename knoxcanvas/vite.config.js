import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  base: '/Connors-Drone-Pics/knoxcanvas/',
  build: {
    outDir: '../docs/knoxcanvas',
    emptyOutDir: true,
  },
});
