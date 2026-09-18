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

// [FORK] Em modo polling o chokidar cria UM fs.watchFile por arquivo, e todos
// os stat() desses pollers disputam o threadpool do libuv, que por padrao tem
// 4 threads. Em app/javascript sao 5.122 arquivos; a 1000ms isso exige 10,5s
// de trabalho por ciclo de 1s. A fila satura e TODA operacao de filesystem do
// Vite passa a esperar nela -- medido, um fs.stat dentro do processo saturado
// custava 3.445ms contra 0,20ms num processo limpo no mesmo container.
//
// Era essa a causa da aplicacao nao abrir. Tres frentes atacam o mesmo
// problema: o intervalo (aqui), o tamanho do pool (UV_THREADPOOL_SIZE no
// docker-compose.dev.local.yaml) e o numero de arquivos observados (abaixo).
const pollInterval = Number(process.env.VITE_POLL_INTERVAL ?? 3000);

// [FORK] Metade dos arquivos observados sao traducoes: dashboard/i18n/locale
// tem 2.704 dos 5.122 arquivos de app/javascript, um diretorio por idioma.
// Ninguem edita 40 idiomas na mesma sessao, entao observar so os que estao em
// uso corta quase 2.600 pollers. Para trabalhar noutro idioma:
// VITE_WATCHED_LOCALES=en,es,fr
const watchedLocales = (process.env.VITE_WATCHED_LOCALES ?? 'en,pt_BR')
  .split(',')
  .map(locale => locale.trim())
  .filter(Boolean);

const IGNORED_DIRS =
  /[/\\](?:\.git|node_modules|tmp|log|storage|coverage|\.lh)[/\\]/;
const LOCALE_DIR = /[/\\]i18n[/\\]locale[/\\]([^/\\]+)/;

const watchIgnored = (candidate: string) => {
  if (IGNORED_DIRS.test(candidate)) return true;

  const locale = candidate.match(LOCALE_DIR);
  return locale ? !watchedLocales.includes(locale[1]) : false;
};

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
    // esperar o navegador pedir. O bloco <style> do App.vue puxa a arvore SCSS
    // inteira e leva ~213s a frio nesta maquina -- tempo suficiente para
    // estourar o read_timeout padrao do proxy do vite_ruby (ver
    // config/initializers/vite_dev_server_proxy_timeout.rb).
    //
    // Os caminhos sao relativos ao root do Vite, que o vite-plugin-ruby aponta
    // para app/javascript (sourceCodeDir em config/vite.json) -- nao a raiz do
    // repositorio.
    warmup: {
      clientFiles: ['./entrypoints/dashboard.js', './dashboard/App.vue'],
    },
  },
});
