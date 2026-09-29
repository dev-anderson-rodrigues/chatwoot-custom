# [FORK] Disparo em massa por qualquer caixa de entrada (Onda 7 / fatia 2).
#
# O upstream tem um servico por provider (Twilio, SMS, WhatsApp) que fala direto com a API.
# Aqui o envio passa pelo pipeline NORMAL de mensagem de saida -- cria a conversa e a
# mensagem na caixa e deixa o canal enviar (SendReplyJob) --, o que serve para e-mail,
# Telegram, Instagram, Facebook, LINE, TikTok e API sem um servico por canal.
#
# COMO O RESULTADO VOLTA
#
# O envio de verdade e assincrono (SendReplyJob, fila `high`) e uma falha so aparece depois,
# quando o canal chama Messages::StatusUpdateService. Por isso o destinatario e marcado `sent`
# (= entregue ao canal) com source_id "message:<id da mensagem>", e o gancho em Message
# (Custom::Concerns::Message -> Custom::Campaigns::RecipientStatusSync) o corrige para
# failed/delivered/read quando o canal informar. Esse source_id sintetico e o unico vinculo
# destinatario <-> mensagem: nao precisa de coluna nova. O Custom::CampaignSendReplyGuard cobre o que
# NAO passa por mudanca de status (excecao do canal e e-mail que nunca saiu).
#
# O QUE NAO SE ENVIA (e aparece como `skipped` com o motivo, nunca some em silencio)
#
#   - contato bloqueado (o model cria a conversa como resolvida, mas a mensagem sairia);
#   - e-mail: contato sem endereco;
#   - variavel vazia, sintaxe Liquid que nao renderiza ou marcacao suspeita num valor vindo do contato
#     (ver Custom::Campaigns::MessageRenderer);
#   - Telegram/Instagram/Facebook/LINE/TikTok: contato que nunca falou naquela caixa. Nesses
#     canais o id do contato so nasce quando a PESSOA escreve primeiro; nao ha como cria-lo
#     daqui (restricao da plataforma, nao do codigo). So e-mail e API montam o vinculo sozinhos;
#   - canal com janela de resposta (Instagram, Facebook, TikTok, API configurada): so envia
#     se alguma conversa do contato tem a janela aberta (Conversations::MessageWindowService).
#
# A CONVERSA
#
# E-mail: sempre uma conversa nova por campanha (cada campanha tem o seu assunto). Demais canais sem
# janela: a mensagem entra na conversa aberta do contato (mesma regra que decide para onde vai a
# RESPOSTA do cliente, ver Telegram::IncomingMessageService#set_conversation) e, sem conversa aberta, abre
# uma nova. Canal com janela: entra na conversa cuja janela esta aberta (resolvida ou nao -- a plataforma
# decide pela ultima mensagem do contato, nao pelo estado da conversa) e, sem nenhuma, o contato e pulado.
#
# A conversa nova nasce `snoozed` sem prazo ("ate o cliente responder"). Aberta, uma campanha de
# 5 mil contatos criaria 5 mil conversas abertas, "aguardando resposta" e distribuidas pelo
# rodizio de atribuicao. Soneca sem prazo nao aparece nas listas abertas, nao e atribuida e
# VOLTA sozinha a `open` quando o cliente responde (Message#reopen_conversation), na mesma
# conversa, com a mensagem enviada a vista do agente. (`resolved` reabriria no e-mail, mas no
# Telegram/Instagram a resposta abriria uma conversa nova, sem o contexto.) EXCECAO: caixa com bot de
# atendimento ativo -- ali o proprio model cria TODA conversa nova como `pending`, com o bot (o bot atende
# a resposta, como em qualquer conversa daquela caixa; Conversation#determine_conversation_status).
#
# `waiting_since` nasce zerado: o model o preenche em toda conversa nova e a mensagem de campanha nao o
# limpa (nao e resposta humana nem de bot), entao sem isso o "aguardando ha X" contaria desde o ENVIO.
#
# A marca `campaign_id` na conversa e na mensagem e a mesma que a campanha do widget usa:
# a mensagem nao conta como resposta humana (Message#human_response?), o relatorio de Origem
# a classifica como campanha e o filtro de conversas por campanha passa a valer. O remetente
# e NULO, nao o agente da campanha: um usuario contaria no tempo de primeira resposta.
#
# RETOMADA E CONCORRENCIA
#
# So processa destinatario `queued` e a conversa + mensagem + destinatario sao gravados na MESMA
# transacao -- se o job morrer entre um e outro, ou tudo existe ou nada existe. A transacao tambem
# garante a ORDEM: o SendReplyJob so sai no after_commit, entao a falha do canal nunca chega antes do
# `mark_sent!`. Dentro dela a linha do destinatario e TRAVADA (`lock!`) e reconferida: dois jobs na mesma
# campanha (o reaper com falso positivo) ja nao duplicam -- o segundo espera o commit do primeiro e pula.
# O resultado de skip/falha so e gravado se o destinatario AINDA estiver `queued`: uma excecao de
# after_commit chega DEPOIS do commit (a mensagem existe, o destinatario ja e `sent`) e nao pode
# rebaixa-lo para `failed`.
#
# Um erro num destinatario so falha aquele destinatario (senao, com o reaper, a campanha cairia em loop).
#
# VOLUME
#
# A pausa entre envios (SendPacing) limita a taxa de CRIACAO, nao a de entrega: com o canal lento
# (SMTP degradado) a fila `high` -- a dos agentes -- cresceria sem freio. Por isso, antes de cada envio, a
# campanha espera a fila `high` baixar de CAMPAIGN_MAX_HIGH_QUEUE (padrao 100; 0 desliga), por no maximo
# 60 s por destinatario (bem abaixo dos 10 min de batimento do reaper).
class Custom::Campaigns::OneoffMessageService
  include Custom::Campaigns::SendPacing

  pattr_initialize [:campaign!]

  # Canais em que o ContactInboxBuilder monta o vinculo do contato (source_id) a partir de
  # dados do proprio contato. Nos demais o id vem do canal, quando a pessoa escreve primeiro.
  CONTACT_INBOX_BUILDABLE = %w[Channel::Email Channel::Api].freeze

  SOURCE_ID_PREFIX = 'message:'.freeze
  # Conversas do contato examinadas em busca de janela aberta.
  WINDOW_CANDIDATES = 3
  MAX_QUEUE_WAIT = 60
  QUEUE_POLL = 5

  def self.source_id_for(message)
    "#{SOURCE_ID_PREFIX}#{message.id}"
  end

  def perform
    validate_campaign!
    create_recipients.each { |recipient| process_recipient(recipient) }
    complete_campaign
  end

  private

  delegate :inbox, to: :campaign

  def validate_campaign!
    raise "Invalid campaign #{campaign.id}" unless campaign.one_off? && Custom::Campaign::GENERIC_INBOX_TYPES.include?(inbox.inbox_type)
    raise 'Completed Campaign' if campaign.completed?
  end

  def email?
    inbox.channel_type == 'Channel::Email'
  end

  def telegram?
    inbox.channel_type == 'Channel::Telegram'
  end

  def reason(key, **)
    Custom::Campaigns::Reasons.t(campaign.account, key, **)
  end

  def audience_labels
    label_ids = Array(campaign.audience).select { |audience| audience['type'] == 'Label' }.pluck('id')
    campaign.account.labels.where(id: label_ids).pluck(:title)
  end

  def create_recipients
    contacts = campaign.account.contacts.tagged_with(audience_labels, any: true)
    Rails.logger.info "Processing #{contacts.count} contacts for campaign #{campaign.id}"

    contacts.find_each.map { |contact| recipient_for(contact) }
  end

  # Corrida com outro job na criacao (o indice unico campaign+contato barra): pega o que ele criou.
  def recipient_for(contact)
    campaign.campaign_recipients.find_or_create_by!(contact: contact) do |recipient|
      recipient.account = campaign.account
      recipient.inbox = inbox
    end
  rescue ActiveRecord::RecordNotUnique
    campaign.campaign_recipients.find_by!(contact: contact)
  end

  # `reload`, nao o objeto em memoria: a lista e carregada antes do envio, e numa retomada quem
  # ja foi enviado/falhou/pulado NAO pode ser reenviado.
  def process_recipient(recipient)
    return unless recipient.reload.queued?

    deliver(recipient)
  rescue Custom::Campaigns::Skip => e
    Rails.logger.info "Campaign #{campaign.id} recipient #{recipient.id} skipped: #{e.message}"
    record_outcome(recipient) { recipient.mark_skipped!(e.message) }
  rescue StandardError => e
    Rails.logger.error "Campaign #{campaign.id} recipient #{recipient.id}: #{e.class}: #{e.message}"
    record_outcome(recipient) { recipient.mark_failed!(message: reason('failure.unexpected', message: e.message).truncate(500)) }
    pause(send_interval)
  end

  # So grava o resultado se o destinatario AINDA esta `queued` (com a linha travada): se outro job o
  # enviou, ou se a excecao veio de um after_commit -- depois de a mensagem existir --, `sent` nao pode
  # virar `skipped`/`failed`. Ultimo recurso: nao levanta (destinatario apagado no meio da execucao).
  # `reload` primeiro: depois de um rollback o objeto pode ter atributos sujos (message_content) e o
  # `lock!` recusa registro com alteracao nao salva.
  def record_outcome(recipient)
    recipient.reload.with_lock do
      if recipient.queued?
        yield
      else
        Rails.logger.error "Campaign #{campaign.id} recipient #{recipient.id} is already #{recipient.status}; " \
                           'an error after the message was created is not recorded over it'
      end
    end
  rescue StandardError => e
    Rails.logger.error "Campaign #{campaign.id} recipient #{recipient.id}: could not record the outcome (#{e.message})"
  end

  # A ordem importa: tudo que pode PULAR o contato vem antes de qualquer escrita, para um contato
  # pulado nao deixar conversa para tras.
  def deliver(recipient)
    contact = recipient.contact
    ensure_reachable!(contact)

    body, subject = render_message(contact)
    contact_inbox = contact_inbox_for(contact)
    wait_for_queue_room

    send_message(recipient, contact_inbox, body, subject)
    pause(send_interval)
  end

  def ensure_reachable!(contact)
    raise Custom::Campaigns::Skip, reason('skip.blocked') if contact.blocked?
    raise Custom::Campaigns::Skip, reason('skip.no_email') if email? && contact.email.blank?
  end

  # [texto, assunto] -- o assunto so existe no e-mail.
  def render_message(contact)
    renderer = Custom::Campaigns::MessageRenderer.new(campaign: campaign, contact: contact)
    [renderer.body(campaign.message), (renderer.subject(campaign.email_subject) if email?)]
  end

  def send_message(recipient, contact_inbox, body, subject)
    ActiveRecord::Base.transaction do
      recipient.lock!
      next unless recipient.queued? # outro job ja o enviou enquanto este renderizava

      conversation = conversation_for(contact_inbox, subject)
      message = create_message(conversation, body)
      recipient.message_content = body
      recipient.mark_sent!(self.class.source_id_for(message))
    end
  end

  def contact_inbox_for(contact)
    existing = contact.contact_inboxes.where(inbox_id: inbox.id).order(:id).last
    return existing if existing

    raise Custom::Campaigns::Skip, reason('skip.no_conversation', channel: inbox.inbox_type) unless CONTACT_INBOX_BUILDABLE.include?(inbox.channel_type)
    # Vinculo novo = nenhuma mensagem recebida ainda = fora de qualquer janela. Barrar aqui evita
    # deixar um vinculo orfao para tras (API com janela configurada).
    raise Custom::Campaigns::Skip, reason('skip.outside_window') if messaging_window_required?

    ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
  end

  def conversation_for(contact_inbox, subject)
    conversation = reusable_conversation(contact_inbox)
    return conversation if conversation
    raise Custom::Campaigns::Skip, reason('skip.outside_window') if messaging_window_required?

    create_conversation(contact_inbox, subject)
  end

  # E-mail: nunca reaproveita. Canal com janela: a conversa cuja janela esta aberta. Os demais espelham o
  # que decide para onde vai a RESPOSTA do cliente: `lock_to_single_conversation` usa sempre a ultima;
  # senao a ultima nao resolvida.
  def reusable_conversation(contact_inbox)
    return if email?
    return windowed_conversation(contact_inbox) if messaging_window_required?

    conversations = contact_inbox.conversations
    inbox.lock_to_single_conversation ? conversations.last : conversations.where.not(status: :resolved).last
  end

  # A janela e da ULTIMA MENSAGEM RECEBIDA do contato, nao do estado da conversa: um contato que escreveu
  # ha 1 hora e cuja conversa o agente ja resolveu continua alcancavel.
  def windowed_conversation(contact_inbox)
    contact_inbox.conversations.order(last_activity_at: :desc, id: :desc).limit(WINDOW_CANDIDATES).find do |conversation|
      Conversations::MessageWindowService.new(conversation).can_reply?
    end
  end

  # A janela so depende da caixa: uma conversa recem-criada (sem mensagem recebida) nao pode
  # ser respondida no canal que tem janela, e pode em todos os outros.
  def messaging_window_required?
    return @messaging_window_required if defined?(@messaging_window_required)

    probe = Conversation.new(account_id: campaign.account_id, inbox: inbox)
    @messaging_window_required = !Conversations::MessageWindowService.new(probe).can_reply?
  end

  # Ninguem esta esperando resposta, mas o model preenche `waiting_since` em TODA conversa nova
  # (`ensure_waiting_since`) e a mensagem de campanha nao o limpa (nao e resposta humana nem de
  # bot). Sem zera-lo aqui, quando o cliente respondesse o relogio de espera continuaria valendo
  # desde o ENVIO da campanha (`set_waiting_since_on_incoming_message` so grava se estiver vazio),
  # inflando o "aguardando ha X", a ordenacao por maior espera e o tempo de resposta do agente.
  # `update_column` de proposito: e o ajuste de um valor que acabou de nascer, sem evento.
  def create_conversation(contact_inbox, subject)
    conversation = Conversation.create!(
      account_id: campaign.account_id,
      inbox_id: inbox.id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id,
      campaign_id: campaign.id,
      status: :snoozed,
      additional_attributes: conversation_attributes(contact_inbox, subject)
    )
    conversation.update_column(:waiting_since, nil) # rubocop:disable Rails/SkipsModelValidations
    conversation
  end

  def conversation_attributes(contact_inbox, subject)
    attributes = subject.present? ? { 'mail_subject' => subject } : {}
    attributes.merge!(telegram_attributes(contact_inbox)) if telegram?
    attributes
  end

  # O Telegram envia para `conversation.additional_attributes['chat_id']` (Channel::Telegram#chat_id), que so o
  # webhook de entrada preenche. Uma conversa criada aqui, sem isso, iria para a API com chat_id nulo e
  # falharia. Copia da ultima conversa do contato (qualquer estado) e, sem nenhuma, usa o id do contato:
  # no chat privado o chat_id e o id do usuario.
  def telegram_attributes(contact_inbox)
    previous = contact_inbox.conversations.where("additional_attributes ->> 'chat_id' IS NOT NULL").order(:id).last
    known = previous&.additional_attributes&.slice('chat_id', 'business_connection_id')
    known.presence || { 'chat_id' => contact_inbox.source_id }
  end

  def create_message(conversation, content)
    Messages::MessageBuilder.new(nil, conversation, { content: content, message_type: 'outgoing', campaign_id: campaign.id }).perform
  end

  # Espera a fila `high` baixar (ver o cabecalho): protege o atendimento, nao o provider.
  def wait_for_queue_room
    limit = max_high_queue
    return if limit <= 0

    waited = 0
    while waited < MAX_QUEUE_WAIT && high_queue_backlog > limit
      pause(QUEUE_POLL)
      waited += QUEUE_POLL
    end
  end

  def max_high_queue
    ENV.fetch('CAMPAIGN_MAX_HIGH_QUEUE', 100).to_i
  end

  def high_queue_backlog
    Sidekiq::Queue.new('high').size
  rescue StandardError => e
    Rails.logger.warn "Campaign #{campaign.id}: could not read the high queue size (#{e.message})"
    0
  end

  # `completed!` roda as validacoes do model: uma campanha que ficou invalida no caminho (remetente
  # tirado da conta, por exemplo) levantaria DEPOIS de enviar tudo, e o reaper a reenfileiraria para
  # sempre. Todos os destinatarios ja tem desfecho -- so falta fecha-la.
  def complete_campaign
    Rails.logger.info "Campaign #{campaign.id} finished: #{campaign.campaign_recipients.group(:status).count}"
    campaign.completed!
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Campaign #{campaign.id} finished but is no longer valid (#{e.message}); completing without validation"
    campaign.update_columns(campaign_status: Campaign.campaign_statuses[:completed], completed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end
end
