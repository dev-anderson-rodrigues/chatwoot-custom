# [FORK] Textos de motivo do disparo em massa (config/locales/fork.*.yml) no idioma da CONTA.
#
# Gravados no destinatario da campanha e mostrados como estao na tela de resultados, entao o idioma e o
# da conta no momento do envio -- nao o do usuario que abre a tela depois. Conta em idioma sem
# traducao cai no ingles (em producao o fallback do I18n ja faz isso; em development/test nao).
module Custom::Campaigns::Reasons
  module_function

  def t(account, key, **)
    I18n.t("campaign_dispatch.#{key}", **, locale: locale_for(account),
                                           default: I18n.t("campaign_dispatch.#{key}", **, locale: I18n.default_locale))
  end

  def locale_for(account)
    locale = account&.locale.to_s
    I18n.available_locales.map(&:to_s).include?(locale) ? locale : I18n.default_locale
  end
end
