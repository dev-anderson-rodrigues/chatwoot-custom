require 'rails_helper'

RSpec.describe V2::Reports::OwnershipSummaryBuilder do
  subject(:builder) { described_class.new(account, params) }

  let(:account) { create(:account) }
  let(:listener) { ReportingEventListener.instance }
  let(:agent) { create(:user, account: account) }
  let(:bot_inbox) { create(:inbox, account: account) }
  let(:params) { { since: 7.days.ago.to_i.to_s, until: Time.current.to_i.to_s } }

  before do
    create(:agent_bot_inbox, agent_bot: create(:agent_bot, account: account), inbox: bot_inbox)
  end

  # Os eventos saem do listener real: e ele que decide se o gemeo
  # `conversation_bot_resolved` sai, e o classificador aposta nesse contrato.
  #
  # Cada chamada viaja para o instante do evento porque o relatorio filtra por
  # `created_at` -- que e a hora em que a linha foi inserida, seguindo o padrao
  # do upstream. Sem viajar, todo evento nasceria "agora" e cairia sempre na
  # janela atual, inclusive os que o teste quer no periodo anterior.
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

  def handoff!(conversation, at:)
    travel_to(at) do
      listener.conversation_bot_handoff(Events::Base.new('conversation.bot_handoff', at, conversation: conversation.reload))
    end
  end

  def bot_conversation(assignee: nil, created_at: 8.days.ago)
    create(:conversation, account: account, inbox: bot_inbox, assignee: assignee, created_at: created_at)
  end

  describe '#metrics' do
    it 'separates what the bot closed alone from what a human closed' do
      resolve!(bot_conversation, at: 2.days.ago)
      resolve!(bot_conversation, at: 2.days.ago)

      trabalhada = bot_conversation
      open!(trabalhada, at: 3.days.ago)
      resolve!(trabalhada, at: 2.days.ago)

      atual = builder.metrics[:current]

      expect(atual[:bot_resolutions]).to eq(2)
      expect(atual[:human_resolutions]).to eq(1)
    end

    it 'averages the handling time of each side separately' do
      # O `value` do evento e o tempo desde a criacao da conversa.
      resolve!(bot_conversation(created_at: 2.days.ago - 100.seconds), at: 2.days.ago)

      trabalhada = bot_conversation(created_at: 2.days.ago - 900.seconds)
      open!(trabalhada, at: 2.days.ago - 500.seconds)
      resolve!(trabalhada, at: 2.days.ago)

      atual = builder.metrics[:current]

      expect(atual[:bot_avg_resolution_seconds]).to eq(100)
      expect(atual[:human_avg_resolution_seconds]).to eq(900)
    end

    it 'reports the previous window of the same size, for comparison' do
      resolve!(bot_conversation(created_at: 20.days.ago), at: 10.days.ago)
      resolve!(bot_conversation, at: 2.days.ago)
      resolve!(bot_conversation, at: 1.day.ago)

      resultado = builder.metrics

      expect(resultado[:current][:bot_resolutions]).to eq(2)
      expect(resultado[:previous][:bot_resolutions]).to eq(1)
    end

    it 'counts each handed off conversation once' do
      conversa = bot_conversation
      handoff!(conversa, at: 3.days.ago)
      # O listener deduplica, mas o relatorio nao pode depender disso.
      handoff!(conversa, at: 2.days.ago)

      expect(builder.metrics[:current][:handoffs]).to eq(1)
    end

    it 'reports the first response time, which is human by construction' do
      conversa = bot_conversation(created_at: 3.days.ago)
      mensagem = create(:message, message_type: 'outgoing', sender: agent, account: account,
                                  inbox: bot_inbox, conversation: conversa, created_at: 3.days.ago + 60.seconds)
      travel_to(mensagem.created_at) do
        listener.first_reply_created(
          Events::Base.new('first.reply.created', mensagem.created_at, message: mensagem)
        )
      end

      expect(builder.metrics[:current][:human_avg_first_response_seconds]).to eq(60)
    end

    it 'ignores what happened outside both windows' do
      resolve!(bot_conversation(created_at: 100.days.ago), at: 90.days.ago)

      resultado = builder.metrics

      expect(resultado[:current][:bot_resolutions]).to eq(0)
      expect(resultado[:previous][:bot_resolutions]).to eq(0)
    end

    it 'never reads another account' do
      outra = create(:account)
      outra_inbox = create(:inbox, account: outra)
      create(:agent_bot_inbox, agent_bot: create(:agent_bot, account: outra), inbox: outra_inbox)
      resolve!(create(:conversation, account: outra, inbox: outra_inbox), at: 2.days.ago)

      expect(builder.metrics[:current][:bot_resolutions]).to eq(0)
    end

    it 'returns zeros instead of nil when the period has no events' do
      atual = builder.metrics[:current]

      expect(atual.values).to all(eq(0))
    end

    it 'refuses to run without a valid time window' do
      expect { described_class.new(account, {}).metrics }.to raise_error(KeyError)
    end
  end
end
