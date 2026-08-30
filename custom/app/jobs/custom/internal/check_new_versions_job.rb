# [FORK] Impede que o hub da Chatwoot dite o plano desta instalacao.
#
# O Internal::CheckNewVersionsJob roda agendado, pergunta ao hub qual e o plano
# da instalacao e grava a resposta em INSTALLATION_PRICING_PLAN (com locked:
# true). Logo depois chama o Internal::ReconcilePlanConfigService, que -- se o
# plano tiver virado 'community' -- reseta as configs premium e roda
# disable_features! em TODAS as contas.
#
# Como este fork opera como enterprise por decisao propria, o plano e uma
# configuracao local e nao um dado vindo do hub. Bloqueamos apenas as duas
# chaves de plano; o restante do update_plan_info (tokens de suporte) continua
# valendo, e o ping ao hub segue acontecendo normalmente.
#
# Cortar aqui, no ponto de escrita, e melhor do que sobrescrever
# ChatwootHub.pricing_plan: a configuracao continua sendo a fonte de verdade,
# segue editavel no super admin e o ChatwootApp.self_hosted_enterprise? -- que
# le a config direto, sem passar pelo ChatwootHub -- continua correto.
#
# Com o plano em 'enterprise', o ReconcilePlanConfigService ja retorna cedo
# sozinho, entao nao ha nada a neutralizar nele.
module Custom::Internal::CheckNewVersionsJob
  PLAN_CONFIG_KEYS = %w[INSTALLATION_PRICING_PLAN INSTALLATION_PRICING_PLAN_QUANTITY].freeze

  private

  def update_installation_config(key:, value:)
    return if PLAN_CONFIG_KEYS.include?(key.to_s)

    super
  end
end
