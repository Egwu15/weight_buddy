import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// A single-page build. The prerender script (scripts/prerender.ts) runs after
// `vite build` and turns dist/index.html into the four pre-rendered pages plus
// a 404 page, so the output is static HTML that reads without JavaScript.
export default defineConfig({
  base: "/",
  plugins: [react()],
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
});
