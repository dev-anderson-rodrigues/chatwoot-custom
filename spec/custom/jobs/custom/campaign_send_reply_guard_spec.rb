require 'rails_helper'

# [FORK] Mensagem de campanha em massa: sem retry automatico e sem falha silenciosa. Ver
# custom/app/jobs/custom/campaign_send_reply_guard.rb.
RSpec.describe SendReplyJob do
  let(:account) { create(:account) }
  let(:label) { create(:label, account: account) }
  let(:telegram_inbox) { create(:channel_telegram, account: account).inbox }
  let(:contact) { create(:contact, account: account, name: 'Maria').tap { |c| c.update_labels([label.title]) } }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: telegram_inbox, source_id: '777') }
  let(:campaign) { create(:campaign, account: account, inbox: telegram_inbox, audience: [{ type: 'Label', id: label.id }]) }
  let!(:recipient) { dispatch_campaign }
  let(:message) { contact_inbox.conversations.last.messages.outgoing.last }

  # Mesmo caminho do disparo real: a mensagem nasce ligada ao destinatario `sent`.
  def dispatch_campaign
    contact_inbox
    allow_any_instance_of(Custom::Campaigns::OneoffMessageService).to receive_messages(sleep: nil, high_queue_backlog: 0) # rubocop:disable RSpec/AnyInstance
    Custom::Campaigns::OneoffMessageService.new(campaign: campaign).perform
    campaign.campaign_recipients.find_by(contact: contact)
  end

  describe 'quando o canal levanta excecao' do
    before { allow_any_instance_of(Telegram::SendOnTelegramService).to receive(:perform).and_raise(Net::ReadTimeout) } # rubocop:disable RSpec/AnyInstance

    it 'mensagem de campanha: nao levanta (nao ha retry do Sidekiq), a mensagem falha e o destinatario tambem' do
      expect { described_class.perform_now(message.id) }.not_to raise_error

      expect(message.reload).to be_failed
      expect(recipient.reload).to be_failed
      expect(recipient.error_message).to include('Net::ReadTimeout')
    end

    it 'mensagem que NAO e de campanha: levanta como no upstream (o Sidekiq refaz)' do
      other = create(:message, account: account, inbox: telegram_inbox, message_type: :outgoing, sender: nil,
                               conversation: create(:conversation, account: account, inbox: telegram_inbox, contact: contact, contact_inbox: contact_inbox))

      expect { described_class.perform_now(other.id) }.to raise_error(Net::ReadTimeout)
    end

    it 'mensagem da campanha do WIDGET (tem campaign_id mas nao ha destinatario): levanta como no upstream' do
      widget_message = create(:message, account: account, inbox: telegram_inbox, message_type: :outgoing, sender: nil,
                                        additional_attributes: { 'campaign_id' => campaign.id },
                                        conversation: create(:conversation, account: account, inbox: telegram_inbox, contact: contact, contact_inbox: contact_inbox))

      expect { described_class.perform_now(widget_message.id) }.to raise_error(Net::ReadTimeout)
    end
  end

  describe 'e-mail sem SMTP (o admin desligou depois de criar a campanha)' do
    let(:email_channel) { create(:channel_email, account: account, smtp_enabled: true) }
    let(:email_inbox) { email_channel.inbox }
    let(:contact) { create(:contact, account: account, name: 'Maria', email: 'maria@example.com').tap { |c| c.update_labels([label.title]) } }
    let(:campaign) do
      create(:campaign, account: account, inbox: email_inbox, audience: [{ type: 'Label', id: label.id }], template_params: { 'subject' => 'Fatura' })
    end
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: email_inbox) }
    let(:message) { contact_inbox.conversations.last.messages.outgoing.last }

    # O mailer retorna antes de montar o e-mail e o upstream levanta ao ler o message_id: a mensagem ja vira
    # `failed` por conta propria (motivo enigmatico, mas nao fica `sent` calada). O teste trava isso.
    it 'a mensagem e o destinatario ficam failed, nao sent para sempre' do
      email_channel.update_columns(smtp_enabled: false) # rubocop:disable Rails/SkipsModelValidations

      described_class.perform_now(message.id)

      expect(message.reload).to be_failed
      expect(recipient.reload).to be_failed
      expect(recipient.error_message).to be_present
    end
  end

  it 'canal que funciona: nada muda, o destinatario segue enviado' do
    allow_any_instance_of(Telegram::SendOnTelegramService).to receive(:perform) # rubocop:disable RSpec/AnyInstance

    described_class.perform_now(message.id)

    expect(message.reload).not_to be_failed
    expect(recipient.reload).to be_sent
  end
end
