# [FORK] Campanha de disparo em massa por qualquer caixa de entrada (Onda 7 / fatia 2).
#
# O model do upstream so aceita disparo em massa por SMS, Twilio SMS e WhatsApp, cada um com
# um servico proprio que fala direto com o provider. As demais caixas (e-mail, Telegram,
# Instagram...) sao atendidas aqui por um unico servico generico, que usa o pipeline normal
# de mensagem de saida: Custom::Campaigns::OneoffMessageService.
#
# Os tres metodos que decidem o tipo de caixa sao PRIVADOS da classe, e um `include` nao os
# sobrescreve (a classe vem antes do modulo na cadeia). Por isso o `included` faz `prepend` de
# um modulo de overrides -- o upstream so chama `Campaign.include_mod_with('Campaign')`, entao
# nada do campaign.rb precisa ser editado.
module Custom::Campaign
  extend ActiveSupport::Concern

  # Lista explicita, e nao "qualquer caixa que as outras nao cubram": um canal novo que o
  # upstream venha a criar nao herda o disparo em massa por acidente. Sao os nomes que
  # `Inbox#inbox_type` devolve. Website continua sendo campanha "ongoing" (widget) e
  # SMS/Twilio SMS/WhatsApp continuam nos servicos proprios do upstream.
  GENERIC_INBOX_TYPES = %w[Email Telegram Instagram Facebook LINE API Tiktok].freeze

  # O agendador (TriggerScheduledItemsJob) so pega campanha agendada nos ultimos 3 dias: uma data mais antiga
  # nunca dispararia. Data no passado significa "enviar agora".
  PAST_SCHEDULE_TOLERANCE = 5.minutes

  included do
    prepend Overrides

    # So na criacao e quando o assunto/a caixa mudam: o upstream chama `update!` na campanha a cada
    # passo do disparo (mark_processing!, completed!), e uma regra que passasse a falhar depois --
    # o admin desligou o SMTP da caixa -- travaria uma campanha ja em andamento.
    validate :email_campaign_requires_subject, if: :email_requirements_changed?
    validate :email_campaign_requires_own_sender, if: :email_requirements_changed?
  end

  # O assunto do e-mail fica em template_params (a API ja aceita e devolve esse campo), com
  # variaveis Liquid como o corpo. Evita coluna nova e mexer em view do upstream.
  def email_subject
    template_params.to_h.with_indifferent_access[:subject]
  end

  private

  def generic_inbox?
    inbox.present? && GENERIC_INBOX_TYPES.include?(inbox.inbox_type)
  end

  def email_campaign?
    inbox&.inbox_type == 'Email'
  end

  def email_requirements_changed?
    new_record? || will_save_change_to_template_params? || will_save_change_to_inbox_id?
  end

  # Sem assunto o Chatwoot manda "[#123] New messages on this conversation" -- nao serve
  # para uma cobranca.
  def email_campaign_requires_subject
    return unless email_campaign?
    return if email_subject.present?

    errors.add(:template_params, I18n.t('campaign_dispatch.validation.email_subject', default: 'must include a subject for e-mail campaigns'))
  end

  # E-mail em massa sem SMTP proprio sairia pelo SMTP GLOBAL da plataforma (o mailer usa `SMTP_ADDRESS`
  # quando a caixa nao tem o dela), com o `support_email` que o admin da conta escolhe como remetente:
  # um tenant disparando a base inteira pela infraestrutura compartilhada queima a reputacao de envio
  # de todos. A caixa precisa enviar pelo SMTP dela (ou por uma conexao Google/Microsoft) -- as mesmas
  # condicoes que o ConversationReplyMailer ja aceita como "caixa que envia por conta propria".
  # Instalacao de uma empresa so, que quer usar o SMTP da plataforma, liga CAMPAIGN_EMAIL_ALLOW_PLATFORM_SMTP.
  def email_campaign_requires_own_sender
    return unless email_campaign?
    return if platform_smtp_allowed? || own_email_sender?(inbox.channel)

    errors.add(:inbox, I18n.t('campaign_dispatch.validation.email_sender',
                              default: 'needs its own SMTP (or a Google/Microsoft connection) to send campaigns'))
  end

  def own_email_sender?(channel)
    channel.smtp_enabled || (channel.imap_enabled && (channel.google? || channel.microsoft?))
  end

  def platform_smtp_allowed?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('CAMPAIGN_EMAIL_ALLOW_PLATFORM_SMTP', false))
  end

  module Overrides
    private

    def validate_campaign_inbox
      return if generic_inbox?

      super
    end

    def ensure_correct_campaign_attributes
      return super unless generic_inbox?

      self.campaign_type = 'one_off'
      self.scheduled_at ||= Time.now.utc
      # So na criacao: depois de disparada a campanha tem, por definicao, agendamento no passado.
      self.scheduled_at = Time.now.utc if new_record? && scheduled_at < PAST_SCHEDULE_TOLERANCE.ago
    end

    def execute_campaign
      return super unless generic_inbox?

      Custom::Campaigns::OneoffMessageService.new(campaign: self).perform
    end
  end
end
