# [FORK] Gancho em Message para o rastreio por destinatario das campanhas (Onda 7 / fatia 2).
#
# Quando o canal falha (ou confirma) o envio de uma mensagem de campanha, o resultado chega como
# uma atualizacao de `status` da mensagem. Aqui ela e repassada ao destinatario. O upstream ja
# chama `Message.include_mod_with('Concerns::Message')`, entao nao ha arquivo do upstream editado.
#
# So age em mensagem marcada com `campaign_id` (a mesma marca da campanha do widget) -- um filtro
# barato para nao consultar campaign_recipients a cada mudanca de status de toda mensagem.
module Custom::Concerns::Message
  extend ActiveSupport::Concern

  included do
    after_update_commit :sync_campaign_recipient_status, if: :campaign_message_status_changed?
  end

  private

  def campaign_message_status_changed?
    saved_change_to_status? && additional_attributes&.dig('campaign_id').present?
  end

  # Nunca pode derrubar quem atualizou a mensagem: o commit ja aconteceu, e o chamador
  # (os servicos de envio de cada canal) trataria a excecao como falha do envio.
  def sync_campaign_recipient_status
    Custom::Campaigns::RecipientStatusSync.new(message: self).perform
  rescue StandardError => e
    Rails.logger.error "Campaign recipient status sync failed for message #{id}: #{e.class}: #{e.message}"
  end
end
