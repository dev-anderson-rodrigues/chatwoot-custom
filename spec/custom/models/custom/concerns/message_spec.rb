require 'rails_helper'

# [FORK] Gancho em Message: o resultado do envio de uma mensagem de campanha chega ao destinatario.
# Ver custom/app/models/custom/concerns/message.rb e custom/app/services/custom/campaigns/recipient_status_sync.rb.
RSpec.describe Message do
  let(:account) { create(:account) }
  let(:label) { create(:label, account: account) }
  let(:inbox) { create(:channel_telegram, account: account).inbox }
  let(:campaign) { create(:campaign, account: account, inbox: inbox, audience: [{ type: 'Label', id: label.id }]) }
  let(:contact) { create(:contact, account: account).tap { |c| c.update_labels([label.title]) } }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let!(:recipient) { dispatch_campaign }
  let(:message) { contact_inbox.conversations.last.messages.outgoing.last }

  # Mesmo caminho do disparo real: o servico grava a conversa, a mensagem e o destinatario `sent`.
  def dispatch_campaign
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    allow_any_instance_of(Custom::Campaigns::OneoffMessageService).to receive(:sleep) # rubocop:disable RSpec/AnyInstance
    Custom::Campaigns::OneoffMessageService.new(campaign: campaign).perform
    campaign.campaign_recipients.find_by(contact: contact)
  end

  def update_status(status, error = nil)
    Messages::StatusUpdateService.new(message, status, error).perform
  end

  it 'a mensagem da campanha esta ligada ao destinatario' do
    expect(recipient).to be_sent
    expect(recipient.source_id).to eq("message:#{message.id}")
  end

  it 'falha do canal vira falha do destinatario, com o motivo' do
    update_status('failed', 'Bad Request: chat not found')

    expect(recipient.reload).to be_failed
    expect(recipient.error_message).to eq('Bad Request: chat not found')
    expect(recipient.failed_at).to be_present
  end

  it 'entregue e lido sobem o estado do destinatario' do
    update_status('delivered')
    expect(recipient.reload).to be_delivered
    expect(recipient.delivered_at).to be_present

    update_status('read')
    expect(recipient.reload).to be_read
  end

  it 'falha depois de entregue nao rebaixa o destinatario' do
    update_status('delivered')
    update_status('failed', 'late error')

    expect(recipient.reload).to be_delivered
  end

  it 'atualizar a mensagem sem mudar o status nao mexe no destinatario' do
    expect { message.update!(source_id: 'external-1') }.not_to(change { recipient.reload.attributes })
  end

  it 'mensagem sem marca de campanha nao consulta os destinatarios' do
    other = create(:message, account: account, inbox: inbox, message_type: :outgoing,
                             conversation: create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox))
    allow(CampaignRecipient).to receive(:find_by).and_call_original

    Messages::StatusUpdateService.new(other, 'failed', 'x').perform

    expect(CampaignRecipient).not_to have_received(:find_by)
  end

  it 'um erro ao repassar nao derruba quem atualizou a mensagem' do
    allow_any_instance_of(Custom::Campaigns::RecipientStatusSync).to receive(:perform).and_raise('boom') # rubocop:disable RSpec/AnyInstance

    expect { update_status('failed', 'x') }.not_to raise_error
    expect(message.reload).to be_failed
  end
end
