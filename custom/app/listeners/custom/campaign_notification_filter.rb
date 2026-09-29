# [FORK] Conversa criada por disparo em massa nao notifica os agentes como "nova conversa" (Onda 7 / fatia 2).
#
# O NotificationListener avisa todo membro da caixa que ativou "nova conversa" a cada conversa criada
# (so pula as `pending`). Uma campanha de 5 mil contatos cria 5 mil conversas de uma vez -- 5 mil
# notificacoes (push/e-mail) para cada agente que optou por esse aviso. Quem disparou a conversa foi o
# sistema, nao o cliente. Quando o cliente RESPONDE ela volta a `open` e aparece nas listas em tempo real
# (nao ha aviso de "nova conversa" nesse momento -- e o preco de nao inundar quem optou pelo aviso).
#
# So conversas de campanha `one_off`; a campanha do widget (`ongoing`) segue notificando, pois ali a
# conversa nasce porque o visitante respondeu.
#
# Ligado por custom/config/initializers/campaign_dispatch_overrides.rb.
module Custom::CampaignNotificationFilter
  def conversation_created(event)
    conversation = event.data[:conversation]
    return if conversation.campaign_id.present? && conversation.campaign&.one_off?

    super
  end
end
