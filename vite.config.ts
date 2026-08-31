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

// [FORK] O intervalo importa muito mais do que parece. Cada ciclo do chokidar
// refaz `stat` em todos os arquivos observados, e sobre o bind mount 9p do
// Docker Desktop no Windows cada `stat` e uma ida e volta cara. Com os 300ms
// que o Vite usa por padrao, o watcher varre a arvore tres vezes por segundo e
// disputa I/O com a propria compilacao -- o dev server fica com CPU alta mesmo
// parado e a primeira carga da pagina se arrasta.
//
// 1000ms mantem o HMR confortavel (o atraso extra e imperceptivel ao salvar) e
// corta o trabalho do watcher para um terco.
const pollInterval = Number(process.env.VITE_POLL_INTERVAL ?? 1000);

// [FORK] Reduz a superficie observada. Nada aqui e fonte do frontend, mas sao
// pastas grandes e movimentadas -- log e tmp mudam a todo request do Rails, o
// que faria o watcher trabalhar a toa.
const watchIgnored = [
  '**/.git/**',
  '**/node_modules/**',
  '**/tmp/**',
  '**/log/**',
  '**/storage/**',
  '**/coverage/**',
  '**/public/packs/**',
  '**/.lh/**',
];

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
    ...(usePolling
      ? {
          watch: {
            usePolling: true,
            interval: pollInterval,
            binaryInterval: pollInterval,
            ignored: watchIgnored,
          },
        }
      : {}),
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
