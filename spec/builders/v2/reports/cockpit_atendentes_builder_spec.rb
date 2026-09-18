require 'rails_helper'

RSpec.describe V2::Reports::CockpitAtendentesBuilder do
  subject(:builder) { described_class.new(account, params) }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:ana) { create(:user, account: account, name: 'Ana Souza', email: 'ana@exemplo.com') }
  let!(:bruno) { create(:user, account: account, name: 'Bruno Lima', email: 'bruno@exemplo.com') }
  let(:params) { { since: 7.days.ago.to_i.to_s, until: Time.current.to_i.to_s } }

  def conversation_for(agent, created_at: 2.days.ago, status: :open, updated_at: nil)
    create(:conversation, account: account, inbox: inbox, assignee: agent,
                          status: status, created_at: created_at, updated_at: updated_at || created_at)
  end

  def resolution_event(agent, value:, created_at: 2.days.ago)
    create(:reporting_event, account_id: account.id, name: 'conversation_resolved',
                             user_id: agent.id, value: value, created_at: created_at)
  end

  before do
    # Presenca vem do Redis; sem stub o teste dependeria de estado externo.
    allow(OnlineStatusTracker).to receive(:get_available_users)
      .and_return({ ana.id.to_s => 'online', bruno.id.to_s => 'busy' })
  end

  describe '#metrics' do
    it 'returns one row per agent with volume, resolutions and presence' do
      conversation_for(ana)
      conversation_for(ana)
      conversation_for(bruno)
      resolution_event(ana, value: 100)

      rows = builder.metrics[:agents]
      row = rows.find { |r| r[:id] == ana.id }

      expect(row[:conversations]).to eq(2)
      expect(row[:resolutions_count]).to eq(1)
      expect(row[:avg_handle_seconds]).to eq(100)
      expect(row[:status]).to eq('online')
    end

    it 'ranks agents by volume, busiest first' do
      conversation_for(bruno)
      conversation_for(bruno)
      conversation_for(ana)

      rows = builder.metrics[:agents]

      expect(rows.first[:id]).to eq(bruno.id)
      expect(rows.first[:rank]).to eq(1)
      expect(rows.second[:rank]).to eq(2)
    end

    it 'falls back to offline for an agent the presence tracker does not know' do
      allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})

      expect(builder.metrics[:agents].map { |r| r[:status] }.uniq).to eq(['offline'])
    end

    it 'counts by resolution date when the screen asks for it' do
      # Aberta fora da janela, encerrada dentro: e o caso que separa "quantas
      # entraram" de "quantas fechei".
      conversa = conversation_for(ana, created_at: 30.days.ago, status: :resolved, updated_at: 1.day.ago)
      create(:reporting_event, account_id: account.id, name: 'conversation_resolved',
                               conversation_id: conversa.id, user_id: ana.id, value: 60, created_at: 1.day.ago)

      por_abertura = described_class.new(account, params).metrics[:agents].find { |r| r[:id] == ana.id }
      por_encerramento = described_class.new(account, params.merge(date_field: 'resolved'))
                                        .metrics[:agents].find { |r| r[:id] == ana.id }

      expect(por_abertura[:conversations]).to eq(0)
      expect(por_encerramento[:conversations]).to eq(1)
    end

    it 'does not treat a conversation merely edited in the window as resolved in it' do
      # `updated_at` muda com etiqueta, nota ou reabertura. Contar por ele faria
      # "encerradas hoje" incluir o que so foi tocado hoje.
      conversa = conversation_for(ana, created_at: 60.days.ago, status: :resolved, updated_at: 1.hour.ago)
      create(:reporting_event, account_id: account.id, name: 'conversation_resolved',
                               conversation_id: conversa.id, user_id: ana.id, value: 60, created_at: 60.days.ago)

      row = described_class.new(account, params.merge(date_field: 'resolved'))
                           .metrics[:agents].find { |r| r[:id] == ana.id }

      expect(row[:conversations]).to eq(0)
    end

    it 'counts a reopened and re-resolved conversation once' do
      conversa = conversation_for(ana, status: :resolved)
      2.times do
        create(:reporting_event, account_id: account.id, name: 'conversation_resolved',
                                 conversation_id: conversa.id, user_id: ana.id, value: 60, created_at: 1.day.ago)
      end

      row = described_class.new(account, params.merge(date_field: 'resolved'))
                           .metrics[:agents].find { |r| r[:id] == ana.id }

      expect(row[:conversations]).to eq(1)
    end

    it 'keeps a closed conversation on the row of whoever resolved it, even after reassignment' do
      # O `user_id` do evento e quem estava atribuido na resolucao. Pelo assignee
      # atual, reatribuir depois movia a conversa de linha e mudava o numero de um
      # periodo ja fechado -- e "encerradas" e "resolucoes" discordavam.
      conversa = conversation_for(ana, status: :resolved)
      create(:reporting_event, account_id: account.id, name: 'conversation_resolved',
                               conversation_id: conversa.id, user_id: ana.id, value: 60, created_at: 1.day.ago)
      conversa.update!(assignee: bruno)

      rows = described_class.new(account, params.merge(date_field: 'resolved')).metrics[:agents]
      row_ana = rows.find { |r| r[:id] == ana.id }
      row_bruno = rows.find { |r| r[:id] == bruno.id }

      expect([row_ana[:conversations], row_ana[:resolutions_count]]).to eq([1, 1])
      expect([row_bruno[:conversations], row_bruno[:resolutions_count]]).to eq([0, 0])
    end

    it 'refuses to run without a valid time window instead of returning an empty report' do
      # O `.to_i` antigo transformava ausencia em 1970 e o relatorio saia zerado
      # sem aviso.
      expect { described_class.new(account, {}).metrics }.to raise_error(KeyError)
      expect { described_class.new(account, params.merge(since: 'ontem')).metrics }.to raise_error(ArgumentError)
    end

    it 'averages csat per agent and weights the account average by responses' do
      create(:csat_survey_response, account: account, assigned_agent_id: ana.id, rating: 5, created_at: 1.day.ago)
      create(:csat_survey_response, account: account, assigned_agent_id: ana.id, rating: 4, created_at: 1.day.ago)
      create(:csat_survey_response, account: account, assigned_agent_id: bruno.id, rating: 1, created_at: 1.day.ago)

      result = builder.metrics
      row_ana = result[:agents].find { |r| r[:id] == ana.id }

      expect(row_ana[:csat]).to eq(4.5)
      expect(row_ana[:csat_responses]).to eq(2)
      # Ponderada: (5 + 4 + 1) / 3 = 3.33, nao a media das medias (4.5 e 1 => 2.75).
      expect(result[:kpis][:avg_csat]).to eq(3.3)
    end

    it 'leaves csat null for an agent with no response instead of showing zero' do
      row = builder.metrics[:agents].find { |r| r[:id] == ana.id }

      expect(row[:csat]).to be_nil
      expect(row[:csat_responses]).to eq(0)
    end

    it 'weights the handle time by volume and ignores agents without data' do
      conversation_for(ana)
      conversation_for(ana)
      conversation_for(bruno)
      resolution_event(ana, value: 300)
      resolution_event(bruno, value: 600)

      # (300*2 + 600*1) / 3 = 400. A media simples daria 450.
      expect(builder.metrics[:kpis][:avg_handle_seconds]).to eq(400)
    end

    it 'reports presence counts in the kpis' do
      kpis = builder.metrics[:kpis]

      expect(kpis[:agents_total]).to eq(2)
      expect(kpis[:agents_online]).to eq(2)
      expect(kpis[:agents_busy]).to eq(1)
      expect(kpis[:agents_offline]).to eq(0)
    end

    it 'filters by team and recomputes the kpis for the filtered set' do
      team = create(:team, account: account)
      create(:team_member, team: team, user: ana)
      conversation_for(ana)
      conversation_for(bruno)

      result = described_class.new(account, params.merge(team_id: team.id)).metrics

      expect(result[:agents].map { |r| r[:id] }).to eq([ana.id])
      expect(result[:agents].first[:team_name]).to eq(team.name)
      # O topo tem que falar do time selecionado, nao da conta inteira.
      expect(result[:kpis][:agents_total]).to eq(1)
      expect(result[:kpis][:conversations_total]).to eq(1)
    end

    it 'filters by name or email' do
      result = described_class.new(account, params.merge(search: 'bruno@')).metrics

      expect(result[:agents].map { |r| r[:id] }).to eq([bruno.id])
    end

    it 'filters by presence status' do
      result = described_class.new(account, params.merge(status: 'busy')).metrics

      expect(result[:agents].map { |r| r[:id] }).to eq([bruno.id])
    end

    it 'ignores what happened outside the window' do
      conversation_for(ana, created_at: 30.days.ago)
      resolution_event(ana, value: 100, created_at: 30.days.ago)

      row = builder.metrics[:agents].find { |r| r[:id] == ana.id }

      expect(row[:conversations]).to eq(0)
      expect(row[:avg_handle_seconds]).to eq(0)
    end
  end
end
