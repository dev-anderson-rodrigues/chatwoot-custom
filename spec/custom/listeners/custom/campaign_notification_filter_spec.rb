require 'rails_helper'

# [FORK] Conversa criada por disparo em massa nao notifica como "nova conversa". Ver
# custom/app/listeners/custom/campaign_notification_filter.rb.
RSpec.describe NotificationListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:inbox) { create(:channel_telegram, account: account).inbox }
  let(:event_name) { :'conversation.created' }

  before do
    setting = agent.notification_settings.first
    setting.selected_email_flags = [:email_conversation_creation]
    setting.selected_push_flags = []
    setting.save!
    create(:inbox_member, user: agent, inbox: inbox)
  end

  def created_event(conversation)
    Events::Base.new(event_name, Time.zone.now, conversation: conversation.reload)
  end

  def campaign_for(type_attrs = {})
    create(:campaign, account: account, inbox: inbox, **type_attrs)
  end

  it 'conversa comum notifica quem optou pelo aviso (comportamento do upstream preservado)' do
    conversation = create(:conversation, account: account, inbox: inbox)

    listener.conversation_created(created_event(conversation))

    expect(agent.notifications.count).to eq(1)
  end

  it 'conversa criada por campanha em massa (one_off) NAO notifica: seriam milhares de avisos de uma vez' do
    conversation = create(:conversation, account: account, inbox: inbox, campaign: campaign_for)

    listener.conversation_created(created_event(conversation))

    expect(agent.notifications.count).to eq(0)
  end

  it 'conversa da campanha do widget (ongoing) continua notificando: la a conversa nasce porque o visitante respondeu' do
    widget_inbox = create(:inbox, account: account, channel: create(:channel_widget, account: account))
    create(:inbox_member, user: agent, inbox: widget_inbox)
    conversation = create(:conversation, account: account, inbox: widget_inbox, campaign: create(:campaign, account: account, inbox: widget_inbox))

    listener.conversation_created(created_event(conversation))

    expect(agent.notifications.count).to eq(1)
  end
end
