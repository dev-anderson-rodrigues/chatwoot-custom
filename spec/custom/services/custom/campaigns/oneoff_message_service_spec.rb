require 'rails_helper'

# [FORK] Disparo em massa por qualquer caixa (Onda 7 / fatia 2). Ver
# custom/app/services/custom/campaigns/oneoff_message_service.rb.
RSpec.describe Custom::Campaigns::OneoffMessageService do
  let(:account) { create(:account) }
  let(:label) { create(:label, account: account) }
  # Campanha de e-mail exige SMTP proprio na caixa (ver Custom::Campaign); o disparo real fica no contexto abaixo.
  let(:email_inbox) { create(:channel_email, account: account, smtp_enabled: true).inbox }
  let(:message_text) { 'Olá {{ contact.name }}, sua fatura vence em breve.' }
  let(:subject_text) { 'Fatura de {{ contact.name }}' }
  let(:campaign) { build_campaign(email_inbox, template_params: { 'subject' => subject_text }) }

  # O ritmo entre envios vive num modulo prepended/incluido, entao o `sleep` e trocado na classe.
  # A fila high vem zerada: a contrapressao tem describe proprio e nao depende do Redis dos demais testes.
  before do
    allow_any_instance_of(described_class).to receive(:sleep) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(described_class).to receive(:high_queue_backlog).and_return(0) # rubocop:disable RSpec/AnyInstance
  end

  def build_campaign(inbox, **attrs)
    create(:campaign, account: account, inbox: inbox, message: message_text,
                      audience: [{ type: 'Label', id: label.id }], **attrs)
  end

  def tagged_contact(**attrs)
    create(:contact, account: account, **attrs).tap { |contact| contact.update_labels([label.title]) }
  end

  def perform(target = campaign)
    described_class.new(campaign: target).perform
  end

  def recipient_for(contact, target = campaign)
    target.campaign_recipients.find_by(contact: contact)
  end

  describe 'e-mail' do
    let!(:contact) { tagged_contact(name: 'Maria', email: 'maria@example.com') }

    it 'abre uma conversa nova em soneca sem prazo, marcada com a campanha, e com o assunto renderizado' do
      perform

      conversation = contact.conversations.last
      expect(conversation).to be_snoozed
      expect(conversation.snoozed_until).to be_nil
      expect(conversation.campaign_id).to eq(campaign.id)
      expect(conversation.additional_attributes['mail_subject']).to eq('Fatura de Maria')
      expect(conversation.inbox).to eq(email_inbox)
    end

    it 'a conversa nao fica aguardando resposta (ninguem esta esperando)' do
      perform

      expect(contact.conversations.last.waiting_since).to be_nil
    end

    context 'when the customer replies' do
      def customer_reply(conversation, at:)
        create(:message, account: account, inbox: email_inbox, conversation: conversation, message_type: :incoming,
                         sender: contact, created_at: at)
      end

      it 'a mesma conversa reabre, com a mensagem enviada a vista e a espera contada a partir da resposta' do
        perform
        conversation = contact.conversations.last

        reply_at = 2.days.from_now.change(usec: 0)
        travel_to(reply_at) { customer_reply(conversation, at: reply_at) }

        conversation.reload
        expect(conversation).to be_open
        expect(conversation.messages.pluck(:message_type)).to eq(%w[outgoing incoming])
        expect(conversation.waiting_since).to eq(reply_at)
        expect(contact.conversations.count).to eq(1)
      end
    end

    it 'cria a mensagem de saida com Liquid renderizado, sem remetente e marcada com a campanha' do
      perform

      message = contact.conversations.last.messages.last
      expect(message).to be_outgoing
      expect(message.content).to eq('Olá Maria, sua fatura vence em breve.')
      expect(message.sender).to be_nil
      expect(message.additional_attributes['campaign_id']).to eq(campaign.id)
    end

    it 'nao conta como resposta humana (nao distorce o tempo de primeira resposta)' do
      perform

      expect(contact.conversations.last.messages.last.send(:human_response?)).to be(false)
    end

    it 'entrega ao canal pelo pipeline normal (SendReplyJob) e conclui a campanha' do
      expect { perform }.to have_enqueued_job(SendReplyJob)

      expect(campaign.reload).to be_completed
    end

    # Ponta a ponta pelo canal de e-mail de verdade (SendReplyJob -> Email::SendOnEmailService).
    context 'when the channel send job runs' do
      # Aqui o e-mail SAI de verdade (metodo :test): caixa sem SMTP proprio + SMTP da plataforma liberado.
      let(:email_inbox) { create(:channel_email, account: account).inbox }

      # O mailer so envia com SMTP configurado (ou em development) e, em teste, o initializer deixa o
      # metodo de entrega em :sendmail -- que nao existe no container.
      around do |example|
        original = ActionMailer::Base.delivery_method
        ActionMailer::Base.delivery_method = :test
        example.run
      ensure
        ActionMailer::Base.delivery_method = original
      end

      before do
        stub_const('ENV', ENV.to_hash.merge('SMTP_ADDRESS' => 'smtp.example.com', 'CAMPAIGN_EMAIL_ALLOW_PLATFORM_SMTP' => 'true'))
        ActionMailer::Base.deliveries.clear
      end

      it 'o e-mail sai para o contato com o assunto da campanha' do
        perform_enqueued_jobs { perform }

        mail = ActionMailer::Base.deliveries.last
        expect(mail.to).to eq(['maria@example.com'])
        expect(mail.subject).to eq('Fatura de Maria')
      end

      it 'e o destinatario segue como enviado, ja com o id do e-mail na mensagem' do
        perform_enqueued_jobs { perform }

        expect(recipient_for(contact)).to be_sent
        expect(contact.conversations.last.messages.last.source_id).to be_present
      end

      it 'se o canal falha ao enviar, o destinatario passa a falhou, com o motivo do canal' do
        allow(ConversationReplyMailer).to receive(:with).and_raise(StandardError, 'smtp is down')

        perform_enqueued_jobs { perform }

        recipient = recipient_for(contact)
        expect(recipient).to be_failed
        expect(recipient.error_message).to eq('smtp is down')
        expect(contact.conversations.last.messages.last).to be_failed
      end
    end

    it 'marca o destinatario como enviado, com o vinculo sintetico a mensagem e o texto renderizado' do
      perform

      recipient = recipient_for(contact)
      message = contact.conversations.last.messages.last
      expect(recipient).to be_sent
      expect(recipient.source_id).to eq("message:#{message.id}")
      expect(recipient.message_content).to eq('Olá Maria, sua fatura vence em breve.')
      expect(recipient.sent_at).to be_present
    end

    it 'cria o vinculo contato-caixa com o e-mail do contato' do
      perform

      expect(contact.contact_inboxes.find_by(inbox: email_inbox).source_id).to eq('maria@example.com')
    end

    it 'usa o vinculo que o contato ja tem, sem criar outro' do
      existing = create(:contact_inbox, contact: contact, inbox: email_inbox)

      expect { perform }.not_to change(ContactInbox, :count)
      expect(contact.conversations.last.contact_inbox).to eq(existing)
    end

    it 'abre uma conversa nova por campanha mesmo que o contato ja tenha uma aberta na caixa' do
      contact_inbox = create(:contact_inbox, contact: contact, inbox: email_inbox)
      open_conversation = create(:conversation, account: account, inbox: email_inbox, contact: contact, contact_inbox: contact_inbox)

      perform

      expect(contact.conversations.count).to eq(2)
      expect(open_conversation.reload.messages.count).to eq(0)
    end

    it 'pula contato sem e-mail com o motivo' do
      no_email = tagged_contact(name: 'Sem Email', email: nil)

      perform

      expect(recipient_for(no_email)).to be_skipped
      expect(recipient_for(no_email).error_message).to eq('Contact has no e-mail address')
      expect(no_email.conversations).to be_empty
    end

    it 'pula contato bloqueado com o motivo' do
      blocked = tagged_contact(name: 'Bloqueado', email: 'bloqueado@example.com', blocked: true)

      perform

      expect(recipient_for(blocked)).to be_skipped
      expect(recipient_for(blocked).error_message).to eq('Contact is blocked')
      expect(blocked.conversations).to be_empty
    end

    it 'os outros contatos seguem sendo enviados quando um e pulado' do
      tagged_contact(name: 'Sem Email', email: nil)

      perform

      expect(recipient_for(contact)).to be_sent
    end

    it 'nao cria a conversa de quem foi pulado por variavel vazia' do
      target = build_campaign(email_inbox, message: 'Deve R$ {{ contact.custom_attribute.valor }}',
                                           template_params: { 'subject' => subject_text })

      perform(target)

      expect(recipient_for(contact, target)).to be_skipped
      expect(contact.conversations).to be_empty
      expect(contact.contact_inboxes).to be_empty
    end
  end

  describe 'variaveis Liquid' do
    let!(:contact) { tagged_contact(name: 'Maria', email: 'maria@example.com', custom_attributes: { 'valor' => '120,00' }) }

    it 'renderiza atributo customizado do contato' do
      target = build_campaign(email_inbox, message: 'Deve R$ {{ contact.custom_attribute.valor }}',
                                           template_params: { 'subject' => subject_text })

      perform(target)

      expect(contact.conversations.last.messages.last.content).to eq('Deve R$ 120,00')
    end

    it 'pula, com o nome da variavel, quando o contato nao tem o dado' do
      without_value = tagged_contact(name: 'Joao', email: 'joao@example.com')
      target = build_campaign(email_inbox, message: 'Deve R$ {{ contact.custom_attribute.valor }}',
                                           template_params: { 'subject' => subject_text })

      perform(target)

      expect(recipient_for(without_value, target)).to be_skipped
      expect(recipient_for(without_value, target).error_message).to include('{{ contact.custom_attribute.valor }}')
      expect(recipient_for(contact, target)).to be_sent
    end

    it 'aceita vazio quando o operador usa o filtro default' do
      without_value = tagged_contact(name: 'Joao', email: 'joao@example.com')
      target = build_campaign(email_inbox, message: "Deve R$ {{ contact.custom_attribute.valor | default: '0,00' }}",
                                           template_params: { 'subject' => subject_text })

      perform(target)

      expect(recipient_for(without_value, target)).to be_sent
      expect(without_value.conversations.last.messages.last.content).to eq('Deve R$ 0,00')
    end

    it 'pula quando o assunto tem variavel vazia' do
      without_value = tagged_contact(name: 'Joao', email: 'joao@example.com')
      target = build_campaign(email_inbox, template_params: { 'subject' => 'Fatura {{ contact.custom_attribute.fatura }}' })

      perform(target)

      expect(recipient_for(without_value, target)).to be_skipped
      expect(recipient_for(without_value, target).error_message).to include('contact.custom_attribute.fatura')
    end

    it 'pula, em vez de mandar o texto cru, quando a sintaxe Liquid nao renderiza' do
      target = build_campaign(email_inbox, message: '{% if contact.name %} oi', template_params: { 'subject' => subject_text })

      perform(target)

      expect(recipient_for(contact, target)).to be_skipped
      expect(recipient_for(contact, target).error_message).to eq('Invalid Liquid syntax in the message')
    end
  end

  describe 'retomada e falhas' do
    let!(:contact) { tagged_contact(name: 'Maria', email: 'maria@example.com') }

    it 'nao reenvia para quem ja foi enviado' do
      campaign.campaign_recipients.create!(account: account, inbox: email_inbox, contact: contact, status: :sent)

      expect { perform }.not_to change(Message, :count)
    end

    it 'nao reenvia para quem ja falhou nem para quem ja foi pulado' do
      failed = tagged_contact(email: 'a@example.com')
      skipped = tagged_contact(email: 'b@example.com')
      campaign.campaign_recipients.create!(account: account, inbox: email_inbox, contact: failed, status: :failed)
      campaign.campaign_recipients.create!(account: account, inbox: email_inbox, contact: skipped, status: :skipped)

      perform

      expect(failed.conversations).to be_empty
      expect(skipped.conversations).to be_empty
    end

    it 'confere o estado no banco, nao o da lista carregada antes (outro job pode ter enviado)' do
      stale = campaign.campaign_recipients.create!(account: account, inbox: email_inbox, contact: contact)
      allow_any_instance_of(described_class).to receive(:create_recipients).and_return([stale]) # rubocop:disable RSpec/AnyInstance
      # rubocop:disable Rails/SkipsModelValidations
      CampaignRecipient.where(id: stale.id).update_all(status: CampaignRecipient.statuses[:sent])
      # rubocop:enable Rails/SkipsModelValidations

      expect { perform }.not_to change(Message, :count)
    end

    it 'um erro inesperado falha so aquele destinatario e a campanha segue' do
      other = tagged_contact(name: 'Ana', email: 'ana@example.com')
      calls = 0
      allow(Messages::MessageBuilder).to receive(:new).and_wrap_original do |original, *args|
        calls += 1
        raise 'boom' if calls == 1

        original.call(*args)
      end

      perform

      statuses = [recipient_for(contact), recipient_for(other)].map(&:status)
      expect(statuses).to contain_exactly('failed', 'sent')
      expect(campaign.campaign_recipients.failed.first.error_message).to eq('Unexpected error: boom')
      expect(campaign.reload).to be_completed
    end

    it 'conversa, mensagem e destinatario sao gravados juntos: se gravar o destinatario falha, nada fica para tras' do
      allow_any_instance_of(CampaignRecipient).to receive(:mark_sent!).and_raise('could not save') # rubocop:disable RSpec/AnyInstance

      expect { perform }.not_to change(Message, :count)

      expect(contact.conversations).to be_empty
      expect(recipient_for(contact)).to be_failed
    end

    it 'nao levanta nem interrompe a campanha se nem gravar a falha for possivel' do
      allow(Messages::MessageBuilder).to receive(:new).and_raise('boom')
      allow_any_instance_of(CampaignRecipient).to receive(:mark_failed!).and_raise('db down') # rubocop:disable RSpec/AnyInstance

      expect { perform }.not_to raise_error
      expect(campaign.reload).to be_completed
    end

    it 'levanta se a campanha ja foi concluida' do
      campaign.completed!

      expect { perform }.to raise_error('Completed Campaign')
    end

    it 'levanta se a caixa nao e atendida pelo disparo generico' do
      sms_inbox = create(:inbox, account: account, channel: create(:channel_sms, account: account))
      sms_campaign = create(:campaign, account: account, inbox: sms_inbox)

      expect { perform(sms_campaign) }.to raise_error("Invalid campaign #{sms_campaign.id}")
    end

    it 'sem audiencia nao ha destinatario e a campanha conclui' do
      empty = create(:campaign, account: account, inbox: email_inbox, audience: nil, template_params: { 'subject' => 'x' })

      expect { perform(empty) }.not_to change(Message, :count)
      expect(empty.reload).to be_completed
    end
  end

  describe 'idioma dos motivos' do
    let!(:no_email) { tagged_contact(name: 'Sem Email', email: nil) }

    it 'grava o motivo no idioma da conta' do
      account.update!(locale: 'pt_BR')

      perform

      expect(recipient_for(no_email).error_message).to eq('Contato sem endereço de e-mail')
    end

    it 'inclui os dados do caso no motivo traduzido (variavel vazia)' do
      account.update!(locale: 'pt_BR')
      tagged_contact(name: 'Joao', email: 'joao@example.com')
      target = build_campaign(email_inbox, message: 'Deve {{ contact.custom_attribute.valor }}', template_params: { 'subject' => 'x' })

      perform(target)

      joao = account.contacts.find_by(name: 'Joao')
      expect(recipient_for(joao, target).error_message).to eq('Variável vazia: {{ contact.custom_attribute.valor }}')
    end

    it 'cai no ingles quando o idioma da conta nao tem traducao' do
      account.update!(locale: 'fr')

      perform

      expect(recipient_for(no_email).error_message).to eq('Contact has no e-mail address')
    end

    it 'o idioma da conta nao vaza para fora do disparo' do
      account.update!(locale: 'pt_BR')

      expect { perform }.not_to change(I18n, :locale)
    end

    it 'a falha inesperada tambem sai no idioma da conta' do
      account.update!(locale: 'pt_BR')
      contact = tagged_contact(name: 'Maria', email: 'maria@example.com')
      allow(Messages::MessageBuilder).to receive(:new).and_raise('boom')

      perform

      expect(recipient_for(contact).error_message).to eq('Erro inesperado: boom')
    end
  end

  describe 'ritmo' do
    it 'pausa entre os envios (protege a fila high, a mesma dos agentes)' do
      tagged_contact(email: 'a@example.com')
      tagged_contact(email: 'b@example.com')
      expect_any_instance_of(described_class).to receive(:sleep).with(0.3).twice # rubocop:disable RSpec/AnyInstance

      perform
    end

    it 'nao pausa por contato pulado' do
      tagged_contact(email: nil)
      expect_any_instance_of(described_class).not_to receive(:sleep) # rubocop:disable RSpec/AnyInstance

      perform
    end

    it 'pausa tambem depois de uma falha inesperada (senao uma falha rapida em todos varreria a base sem folga)' do
      tagged_contact(email: 'a@example.com')
      allow(Messages::MessageBuilder).to receive(:new).and_raise('boom')
      expect_any_instance_of(described_class).to receive(:sleep).with(0.3).once # rubocop:disable RSpec/AnyInstance

      perform
    end

    it 'o intervalo vem de CAMPAIGN_SEND_INTERVAL_MS' do
      tagged_contact(email: 'a@example.com')
      stub_const('ENV', ENV.to_hash.merge('CAMPAIGN_SEND_INTERVAL_MS' => '1000'))
      expect_any_instance_of(described_class).to receive(:sleep).with(1.0) # rubocop:disable RSpec/AnyInstance

      perform
    end
  end

  describe 'Telegram (so quem ja falou primeiro)' do
    let(:telegram_inbox) { create(:channel_telegram, account: account).inbox }
    let(:target) { build_campaign(telegram_inbox) }
    let!(:contact) { tagged_contact(name: 'Maria') }

    it 'pula, com o motivo, o contato que nunca falou naquela caixa' do
      perform(target)

      recipient = recipient_for(contact, target)
      expect(recipient).to be_skipped
      expect(recipient.error_message).to include('Telegram').and include('wrote first')
      expect(contact.conversations).to be_empty
      expect(contact.contact_inboxes).to be_empty
    end

    context 'when the contact already has an open conversation in the inbox' do
      let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: telegram_inbox) }
      let!(:conversation) do
        create(:conversation, account: account, inbox: telegram_inbox, contact: contact, contact_inbox: contact_inbox, status: :open)
      end

      it 'a mensagem entra nessa conversa, sem abrir outra, e ela continua aberta' do
        expect { perform(target) }.not_to change(Conversation, :count)

        message = conversation.reload.messages.last
        expect(message.content).to eq('Olá Maria, sua fatura vence em breve.')
        expect(message.additional_attributes['campaign_id']).to eq(target.id)
        expect(conversation).to be_open
        expect(recipient_for(contact, target)).to be_sent
      end
    end

    context 'when the only conversation of the contact is resolved' do
      let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: telegram_inbox) }
      let!(:resolved) do
        create(:conversation, account: account, inbox: telegram_inbox, contact: contact, contact_inbox: contact_inbox, status: :resolved)
      end

      it 'abre uma conversa nova em soneca (a resposta do cliente nao reabre a resolvida)' do
        perform(target)

        conversation = contact_inbox.conversations.where.not(id: resolved.id).last
        expect(conversation).to be_snoozed
        expect(conversation.messages.last.content).to eq('Olá Maria, sua fatura vence em breve.')
        expect(resolved.reload.messages).to be_empty
      end

      it 'com a caixa travada em uma conversa, usa a ultima mesmo resolvida (e a que recebe a resposta)' do
        telegram_inbox.update!(lock_to_single_conversation: true)

        expect { perform(target) }.not_to change(Conversation, :count)

        expect(resolved.reload.messages.last.content).to eq('Olá Maria, sua fatura vence em breve.')
      end
    end
  end

  describe 'Instagram (janela de resposta)' do
    let(:instagram_inbox) { create(:channel_instagram, account: account).inbox }
    let(:target) { build_campaign(instagram_inbox) }
    let!(:contact) { tagged_contact(name: 'Maria') }
    let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: instagram_inbox) }
    let!(:conversation) do
      create(:conversation, account: account, inbox: instagram_inbox, contact: contact, contact_inbox: contact_inbox, status: :open)
    end

    def incoming_message(created_at:)
      create(:message, account: account, inbox: instagram_inbox, conversation: conversation, message_type: :incoming,
                       sender: contact, created_at: created_at)
    end

    it 'envia quando o contato escreveu dentro da janela' do
      incoming_message(created_at: 2.hours.ago)

      perform(target)

      expect(recipient_for(contact, target)).to be_sent
      expect(conversation.reload.messages.outgoing.last.content).to eq('Olá Maria, sua fatura vence em breve.')
    end

    it 'pula, com o motivo, quando a janela ja fechou' do
      incoming_message(created_at: 3.days.ago)

      expect { perform(target) }.not_to change(Message, :count)

      expect(recipient_for(contact, target)).to be_skipped
      expect(recipient_for(contact, target).error_message).to start_with('Outside the messaging window')
    end

    it 'envia na conversa resolvida quando o contato escreveu dentro da janela (a janela e da ultima mensagem dele)' do
      incoming_message(created_at: 1.hour.ago)
      conversation.resolved!

      expect { perform(target) }.not_to change(Conversation, :count)

      expect(recipient_for(contact, target)).to be_sent
      expect(conversation.reload.messages.outgoing.last.content).to eq('Olá Maria, sua fatura vence em breve.')
      expect(conversation).to be_resolved
    end

    it 'com varias conversas, usa a que tem a janela aberta' do
      old_one = create(:conversation, account: account, inbox: instagram_inbox, contact: contact, contact_inbox: contact_inbox, status: :resolved)
      create(:message, account: account, inbox: instagram_inbox, conversation: old_one, message_type: :incoming, sender: contact, created_at: 5.days.ago)
      incoming_message(created_at: 30.minutes.ago)

      perform(target)

      expect(conversation.reload.messages.outgoing.count).to eq(1)
      expect(old_one.reload.messages.outgoing.count).to eq(0)
    end

    it 'pula quando o contato so tem conversa resolvida (nao ha onde a resposta cair dentro da janela)' do
      conversation.resolved!

      expect { perform(target) }.not_to change(Conversation, :count)

      expect(recipient_for(contact, target)).to be_skipped
      expect(recipient_for(contact, target).error_message).to start_with('Outside the messaging window')
    end
  end

  describe 'API' do
    let(:api_inbox) { create(:channel_api, account: account).inbox }
    let(:target) { build_campaign(api_inbox) }
    let!(:contact) { tagged_contact(name: 'Maria') }

    it 'monta o vinculo do contato sozinho e abre a conversa' do
      perform(target)

      expect(recipient_for(contact, target)).to be_sent
      expect(contact.contact_inboxes.find_by(inbox: api_inbox)).to be_present
      expect(contact.conversations.last).to be_snoozed
    end

    it 'com janela de resposta configurada, pula sem deixar vinculo orfao' do
      api_inbox.channel.update!(additional_attributes: { 'agent_reply_time_window' => '24' })

      perform(target)

      expect(recipient_for(contact, target)).to be_skipped
      expect(contact.contact_inboxes).to be_empty
    end
  end

  describe 'concorrencia e resultado' do
    let!(:contact) { tagged_contact(name: 'Maria', email: 'maria@example.com') }

    it 'nao envia de novo quando outro job enviou o mesmo destinatario entre a checagem e o envio' do
      # O outro job ganha a corrida DEPOIS do reload/queued? e ANTES de a linha ser travada.
      allow_any_instance_of(CampaignRecipient).to receive(:lock!).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
        CampaignRecipient.where(campaign_id: campaign.id).update_all(status: CampaignRecipient.statuses[:sent], source_id: 'message:other') # rubocop:disable Rails/SkipsModelValidations
        original.call(*args)
      end

      expect { perform }.not_to change(Message, :count)

      recipient = recipient_for(contact)
      expect(recipient).to be_sent
      expect(recipient.source_id).to eq('message:other')
    end

    it 'skip nao sobrescreve um destinatario que outro job ja enviou' do
      blocked = tagged_contact(name: 'Bloqueado', email: 'b@example.com', blocked: true)
      allow_any_instance_of(described_class).to receive(:ensure_reachable!).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
        CampaignRecipient.where(contact_id: blocked.id).update_all(status: CampaignRecipient.statuses[:sent]) # rubocop:disable Rails/SkipsModelValidations
        original.call(*args)
      end

      perform

      expect(recipient_for(blocked)).to be_sent
    end

    it 'excecao de after_commit (depois de a mensagem existir) nao rebaixa o destinatario ja enviado para falhou' do
      allow(SendReplyJob).to receive(:perform_later).and_raise(StandardError, 'redis is down')

      perform

      expect(recipient_for(contact)).to be_sent
      expect(contact.conversations.last.messages.count).to eq(1)
    end

    it 'corrida na criacao do destinatario: usa o que o outro job criou' do
      existing = campaign.campaign_recipients.create!(account: account, inbox: email_inbox, contact: contact)
      recipients = campaign.campaign_recipients
      allow(recipients).to receive(:find_or_create_by!).and_raise(ActiveRecord::RecordNotUnique)
      allow(campaign).to receive(:campaign_recipients).and_return(recipients)

      expect(described_class.new(campaign: campaign).send(:recipient_for, contact)).to eq(existing)
    end

    it 'conclui a campanha mesmo que ela tenha ficado invalida no caminho (senao o reaper a repetiria para sempre)' do
      allow(campaign).to receive(:completed!).and_raise(ActiveRecord::RecordInvalid.new(campaign))

      perform

      expect(campaign.reload).to be_completed
      expect(campaign.completed_at).to be_present
      expect(recipient_for(contact)).to be_sent
    end

    it 'registra um resumo ao concluir' do
      allow(Rails.logger).to receive(:info)

      perform

      expect(Rails.logger).to have_received(:info).with(/Campaign #{campaign.id} finished: .*"sent" ?=> ?1/)
    end
  end

  describe 'contrapressao na fila high' do
    let(:pauses) { [] }

    before do
      tagged_contact(email: 'a@example.com')
      allow_any_instance_of(described_class).to receive(:sleep) { |_instance, seconds| pauses << seconds } # rubocop:disable RSpec/AnyInstance
    end

    it 'espera a fila baixar antes de criar a conversa e a mensagem' do
      allow_any_instance_of(described_class).to receive(:high_queue_backlog).and_return(500, 500, 10) # rubocop:disable RSpec/AnyInstance

      perform

      expect(pauses).to eq([5, 5, 0.3])
      expect(Message.where(account_id: account.id).count).to eq(1)
    end

    it 'nao espera mais de 60 s por destinatario: segue enviando (o reaper acharia que o job morreu)' do
      allow_any_instance_of(described_class).to receive(:high_queue_backlog).and_return(500) # rubocop:disable RSpec/AnyInstance

      perform

      expect(pauses.count(5)).to eq(12)
      expect(Message.where(account_id: account.id).count).to eq(1)
    end

    it 'CAMPAIGN_MAX_HIGH_QUEUE=0 desliga' do
      stub_const('ENV', ENV.to_hash.merge('CAMPAIGN_MAX_HIGH_QUEUE' => '0'))
      expect_any_instance_of(described_class).not_to receive(:high_queue_backlog) # rubocop:disable RSpec/AnyInstance

      perform

      expect(pauses).to eq([0.3])
    end

    it 'se nao consegue ler a fila (Redis fora), nao trava o disparo' do
      allow_any_instance_of(described_class).to receive(:high_queue_backlog).and_call_original # rubocop:disable RSpec/AnyInstance
      allow(Sidekiq::Queue).to receive(:new).and_raise(StandardError, 'redis is down')

      perform

      expect(pauses).to eq([0.3])
      expect(Message.where(account_id: account.id).count).to eq(1)
    end
  end

  describe 'Telegram: chat_id da conversa criada aqui' do
    let(:telegram_inbox) { create(:channel_telegram, account: account).inbox }
    let(:target) { build_campaign(telegram_inbox) }
    let!(:contact) { tagged_contact(name: 'Maria') }
    let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: telegram_inbox, source_id: '777') }

    it 'copia chat_id e business_connection_id da ultima conversa do contato, mesmo resolvida' do
      create(:conversation, account: account, inbox: telegram_inbox, contact: contact, contact_inbox: contact_inbox, status: :resolved,
                            additional_attributes: { 'chat_id' => '555', 'business_connection_id' => 'bc-1' })

      perform(target)

      created = contact_inbox.conversations.order(:id).last
      expect(created.additional_attributes).to include('chat_id' => '555', 'business_connection_id' => 'bc-1')
      expect(created).to be_snoozed
    end

    it 'sem conversa anterior, usa o id do contato (no chat privado o chat_id e o id do usuario)' do
      perform(target)

      expect(contact_inbox.conversations.last.additional_attributes).to include('chat_id' => '777')
    end

    it 'ponta a ponta: a API do Telegram recebe o chat_id' do
      stub_request(:post, %r{api\.telegram\.org/bot.*/sendMessage})
        .to_return(status: 200, body: { ok: true, result: { message_id: 99 } }.to_json, headers: { 'Content-Type' => 'application/json' })

      perform_enqueued_jobs { perform(target) }

      expect(a_request(:post, /sendMessage/).with(body: hash_including('chat_id' => '777'))).to have_been_made.once
      expect(recipient_for(contact, target)).to be_sent
    end
  end

  describe 'caixa com bot de atendimento ativo' do
    let(:api_inbox) { create(:channel_api, account: account).inbox }
    let(:target) { build_campaign(api_inbox) }
    let!(:contact) { tagged_contact(name: 'Maria') }

    before { create(:agent_bot_inbox, inbox: api_inbox, agent_bot: create(:agent_bot, account: account)) }

    it 'o proprio model cria a conversa como pending, com o bot (o bot atende a resposta), sem perder a marca da campanha' do
      perform(target)

      conversation = contact.conversations.last
      expect(conversation).to be_pending
      expect(conversation.campaign_id).to eq(target.id)
      expect(recipient_for(contact, target)).to be_sent
    end
  end
end
