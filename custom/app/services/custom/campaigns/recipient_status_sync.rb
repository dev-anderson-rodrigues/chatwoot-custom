# [FORK] Repassa ao destinatario da campanha o resultado da entrega de UMA mensagem.
#
# O disparo generico (Custom::Campaigns::OneoffMessageService) marca o destinatario `sent` assim
# que a mensagem e entregue ao canal, porque o envio de verdade e assincrono. Quando o canal
# depois falha -- ou informa entregue/lido --, este servico corrige o destinatario. O vinculo e o
# source_id sintetico "message:<id>" gravado no envio; mensagem que nao veio de campanha generica
# nao acha destinatario e nao faz nada.
#
# Reaproveita CampaignRecipient#update_from_whatsapp_status! apesar do nome: ele ja faz o lock e
# impede rebaixar delivered/read para failed, e o formato do erro que ele le
# (errors: [{ message: }]) e simples de montar. `sent` nao e tratado: e o estado inicial.
class Custom::Campaigns::RecipientStatusSync
  pattr_initialize [:message!]

  def perform
    recipient = CampaignRecipient.find_by(source_id: Custom::Campaigns::OneoffMessageService.source_id_for(message))
    return if recipient.blank?

    recipient.update_from_whatsapp_status!(
      status: message.status,
      timestamp: Time.current.to_i,
      errors: [{ message: message.external_error }]
    )
  end
end
