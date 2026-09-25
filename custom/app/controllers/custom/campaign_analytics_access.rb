# [FORK] Analytics de campanha tambem para o disparo generico (Onda 7 / fatia 2).
#
# O controller de analytics (enterprise) so libera campanha de WhatsApp com a flag ligada, mas
# o rastreio por destinatario (campaign_recipients) e o mesmo para as caixas do disparo
# generico -- e e la que o operador ve quem foi pulado ou falhou, e por que. Sem isto, essas
# campanhas nao teriam onde mostrar o resultado.
#
# Ligado por custom/config/initializers/campaign_dispatch_overrides.rb.
module Custom::CampaignAnalyticsAccess
  private

  def ensure_whatsapp_campaign_analytics_enabled!
    return if generic_campaign?

    super
  end

  # No WhatsApp `sent` e "aceita pelo provider" (tem source_id) e inclui quem falhou depois. Aqui o
  # source_id existe desde a criacao da mensagem, entao um destinatario que o canal recusou DEPOIS teria
  # source_id e contaria como enviado E como falha: as faixas somariam mais que o publico. `Enviadas` =
  # entregue ao canal e sem falha -- enviadas + falharam + puladas (+ na fila) fecham o publico.
  def delivery_metrics
    metrics = super
    return metrics unless generic_campaign?

    counts = metrics[:status_counts]
    metrics.merge(sent: counts['sent'] + counts['delivered'] + counts['read'])
  end

  # A tabela mostra o telefone do contato; numa campanha de e-mail o que identifica quem
  # recebeu e o endereco.
  def recipient_payload(recipient)
    payload = super
    payload[:contact][:email] = recipient.contact.email
    payload
  end

  def generic_campaign?
    @campaign.one_off? && Custom::Campaign::GENERIC_INBOX_TYPES.include?(@campaign.inbox.inbox_type)
  end
end
