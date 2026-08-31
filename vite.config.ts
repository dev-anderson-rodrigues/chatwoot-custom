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

// [FORK] O Vite 6 recusa request cujo header Host nao esteja na allowedHosts.
// Em Docker isso quebra o caminho normal: a pagina pede /vite-dev/... na porta
// do Rails, o vite_ruby faz proxy para o container `vite`, e o Vite devolve 403
// -- a aplicacao carrega sem nenhum asset. Buscar direto na 3036 funciona,
// porque ai o Host e localhost. Sem lista definida, nada muda.
const allowedHosts = (process.env.VITE_ALLOWED_HOSTS ?? '')
  .split(',')
  .map(host => host.trim())
  .filter(Boolean);

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
  server: {
    ...(usePolling ? { watch: { usePolling: true, interval: 300 } } : {}),
    ...(allowedHosts.length ? { allowedHosts } : {}),
    // Compila os modulos mais pesados assim que o dev server sobe, em vez de
    // esperar o navegador pedir. Sao os que estouram o read_timeout do proxy
    // do vite_ruby na primeira carga (ver
    // config/initializers/vite_dev_server_proxy_timeout.rb): a arvore SCSS
    // inteira via App.vue e as 540 url() do flag-icons via Flag.vue.
    // Os caminhos sao relativos ao root do Vite, que o vite-plugin-ruby aponta
    // para app/javascript (sourceCodeDir em config/vite.json) -- nao a raiz do
    // repositorio.
    warmup: {
      clientFiles: [
        './entrypoints/dashboard.js',
        './dashboard/App.vue',
        './dashboard/components-next/flag/Flag.vue',
      ],
    },
  },
});
