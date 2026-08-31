# frozen_string_literal: true

# Aumenta o read timeout do proxy que o vite_rails coloca na frente da aplicacao
# em desenvolvimento.
#
# Por que isso e necessario:
#
# O vite_rails instala o ViteRuby::DevServerProxy (uma subclasse de Rack::Proxy)
# e nao expoe nenhuma opcao para o timeout. O Rack::Proxy usa
# `opts.fetch(:read_timeout, 60)` -- 60 segundos fixos.
#
# Na primeira compilacao a frio, os dois blocos de <style> mais pesados do
# dashboard estouram esse limite:
#
#   - dashboard/components-next/flag/Flag.vue, que faz
#     `@import 'flag-icons/css/flag-icons.min.css'` -- 540 referencias url()
#     que o Vite precisa resolver uma a uma;
#   - dashboard/App.vue, que puxa a arvore inteira de SCSS via
#     `@import './assets/scss/app'`.
#
# Em Docker Desktop no Windows o codigo fica num bind mount 9p, ordens de
# grandeza mais lento que o filesystem do container. Medido nesta maquina: o
# CSS do App.vue leva **213s** para compilar a frio e devolve 1,7 MB. O proxy
# desiste aos 60s, devolve `Net::ReadTimeout` como 500, e a aplicacao abre em
# tela branca -- sem nenhum erro no log do Vite, porque o Vite ainda estava
# compilando quando o Rails cortou a conexao.
#
# O default de 600s da folga sobre esses 213s. Complementarmente, o
# `server.warmup` em vite.config.ts manda o Vite compilar os modulos pesados
# assim que sobe, para que o navegador em geral nem chegue a esperar.
#
# NAO da para usar `config.middleware.swap` aqui: o vite_rails registra o
# insert_before numa engine initializer que so e mesclada na pilha depois deste
# arquivo, entao o swap falha com "No such middleware to insert before".
# Por isso injetamos a opcao no proprio construtor, que e independente de ordem.
#
# So vale em desenvolvimento: em producao os assets sao pre-compilados e este
# proxy nem existe.
if Rails.env.development? && defined?(ViteRuby::DevServerProxy)
  module ViteDevServerProxyTimeout
    def initialize(app = nil, opts = {})
      super(app, { read_timeout: ENV.fetch('VITE_PROXY_READ_TIMEOUT', 600).to_i }.merge(opts))
    end
  end

  ViteRuby::DevServerProxy.prepend(ViteDevServerProxyTimeout)
end
