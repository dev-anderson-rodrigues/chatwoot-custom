import { defineConfig } from 'vite';
import ruby from 'vite-plugin-ruby';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from './vite.shared';
import yaml from '@rollup/plugin-yaml';

// [FORK] O watcher do Vite (chokidar) depende de inotify, e o Docker Desktop no Windows
// nao propaga eventos de filesystem do host para o container via bind mount. Sem polling,
// salvar um .vue nao dispara HMR nenhum. O polling custa CPU, entao fica atras de uma
// variavel de ambiente: so o Windows paga. Ver docs-fork/ambiente-local.md.
const usePolling = process.env.FORCE_POLLING_FILE_WATCHER === 'true';

export default defineConfig({
  plugins: [ruby(), vue(vueOptions), yaml()],
  css: {
    preprocessorOptions: {
      scss: {
        api: 'modern-compiler',
      },
    },
  },
  resolve: { alias: aliases },
  server: usePolling
    ? { watch: { usePolling: true, interval: 300 } }
    : {},
});
