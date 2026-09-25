# [FORK] Envio de mensagem de campanha em massa: sem retry automatico (Onda 7 / fatia 2).
#
# O SendReplyJob do upstream deixa a excecao do canal subir e o Sidekiq refaz ate 3 vezes
# (config/sidekiq.yml). Para uma resposta de agente isso e certo; para uma COBRANCA em massa e um risco: se a
# excecao vem DEPOIS de o provider ter aceitado a mensagem (timeout de leitura, resposta que nao e JSON), o
# retry entrega de novo e o cliente e cobrado 2x. Mesmo criterio do servico do WhatsApp (que so repete o que
# o provider recusou ANTES de processar): duplicar e pior que falhar.
#
# Aqui a excecao do canal vira `failed` na mensagem, com o motivo (o gancho de Message repassa ao destinatario),
# e o job NAO levanta -- entao nao ha retry. Retries esgotados tambem deixavam o destinatario `sent` para sempre:
# a mensagem nao mudava de status.
#
# So mexe em mensagem de campanha do disparo generico (identificada pelo destinatario, "message:<id>");
# qualquer outra segue exatamente como no upstream, inclusive o retry.
#
# Ligado por custom/config/initializers/campaign_dispatch_overrides.rb.
module Custom::CampaignSendReplyGuard
  def perform(message_id)
    super
  rescue StandardError => e
    fail_campaign_message(message_id, e)
  end

  private

  def fail_campaign_message(message_id, error)
    message = campaign_message(message_id)
    raise error if message.nil? # nao e da campanha: comportamento do upstream (o Sidekiq refaz)

    Rails.logger.error "Campaign message #{message_id}: send failed and will not be retried (#{error.class}: #{error.message})"
    Messages::StatusUpdateService.new(message, 'failed', error.message.to_s.truncate(500)).perform
  end

  # Mensagem do disparo generico: tem a marca de campanha E um destinatario apontando para ela.
  def campaign_message(message_id)
    message = Message.find_by(id: message_id)
    return if message.blank? || message.additional_attributes&.dig('campaign_id').blank?
    return unless CampaignRecipient.exists?(source_id: Custom::Campaigns::OneoffMessageService.source_id_for(message))

    message
  end
end
