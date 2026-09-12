# frozen_string_literal: true

require 'rails_helper'

# O enterprise soma o Captain ao `Inbox#active_bot?`, entao caixa com Captain
# tambem produz o gemeo `conversation_bot_resolved` e entra no resumo como robo.
# Sem este spec, ligar o Captain mudaria o relatorio em silencio.
RSpec.describe V2::Reports::OwnershipSummaryBuilder do
  subject(:builder) { described_class.new(account, params) }

  let(:account) { create(:account) }
  let(:listener) { ReportingEventListener.instance }
  let(:captain_inbox) { create(:inbox, account: account) }
  let(:params) { { since: 7.days.ago.to_i.to_s, until: Time.current.to_i.to_s } }

  before do
    create(:captain_inbox, captain_assistant: create(:captain_assistant, account: account), inbox: captain_inbox)
  end

  def resolve!(conversation, at:)
    travel_to(at) do
      listener.conversation_resolved(Events::Base.new('conversation.resolved', at, conversation: conversation.reload))
    end
  end

  def open!(conversation, at:)
    travel_to(at) do
      listener.conversation_opened(Events::Base.new('conversation.opened', at, conversation: conversation.reload))
    end
  end

  it 'counts what the Captain closed on its own as the bot' do
    conversa = create(:conversation, account: account, inbox: captain_inbox, created_at: 3.days.ago)
    resolve!(conversa, at: 2.days.ago)

    atual = builder.metrics[:current]

    expect(atual[:bot_resolutions]).to eq(1)
    expect(atual[:human_resolutions]).to eq(0)
  end

  it 'counts as human what someone opened before closing, even in a Captain inbox' do
    conversa = create(:conversation, account: account, inbox: captain_inbox, created_at: 3.days.ago)
    open!(conversa, at: 2.days.ago - 1.hour)
    resolve!(conversa, at: 2.days.ago)

    atual = builder.metrics[:current]

    expect(atual[:bot_resolutions]).to eq(0)
    expect(atual[:human_resolutions]).to eq(1)
  end
end
