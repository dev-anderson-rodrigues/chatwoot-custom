# frozen_string_literal: true

require 'rails_helper'

# O enterprise soma o Captain ao `Inbox#active_bot?`, entao caixa com Captain
# tambem produz o gemeo `conversation_bot_resolved`. E por isso que o
# classificador se ancora no gemeo e nao em `agent_bot_inboxes`, como fazia a
# fonte: com `agent_bot_inboxes`, conversa resolvida pelo Captain (ou por
# dialogflow) cairia em "Humanos".
RSpec.describe Reports::ConversationOwnershipFinder do
  subject(:finder) { described_class.new(account) }

  let(:account) { create(:account) }
  let(:listener) { ReportingEventListener.instance }
  let(:captain_inbox) { create(:inbox, account: account) }

  before do
    create(:captain_inbox, captain_assistant: create(:captain_assistant, account: account), inbox: captain_inbox)
  end

  def resolve!(conversation, at: Time.current)
    listener.conversation_resolved(Events::Base.new('conversation.resolved', at, conversation: conversation.reload))
  end

  def open!(conversation, at: Time.current)
    listener.conversation_opened(Events::Base.new('conversation.opened', at, conversation: conversation.reload))
  end

  it 'conta como robo a conversa que o Captain resolveu sozinho' do
    conversation = create(:conversation, account: account, inbox: captain_inbox)
    resolve!(conversation)

    expect(finder.resolutions('bot').count).to eq(1)
  end

  it 'conta como humana a conversa da caixa do Captain que alguem abriu antes de resolver' do
    conversation = create(:conversation, account: account, inbox: captain_inbox)
    open!(conversation, at: 2.hours.ago)
    resolve!(conversation, at: 1.hour.ago)

    expect(finder.resolutions('bot').count).to eq(0)
    expect(finder.resolutions('human').count).to eq(1)
  end
end
