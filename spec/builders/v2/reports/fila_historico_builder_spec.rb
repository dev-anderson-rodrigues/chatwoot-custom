require 'rails_helper'

RSpec.describe V2::Reports::FilaHistoricoBuilder do
  subject(:builder) { described_class.new(account, params) }

  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:bot_inbox) { create(:inbox, account: account) }
  let!(:agent) { create(:user, account: account, name: 'Ana Souza') }
  let(:listener) { ReportingEventListener.instance }
  let(:params) { { since: 7.days.ago.to_i.to_s, until: Time.current.to_i.to_s } }

  before do
    create(:agent_bot_inbox, agent_bot: create(:agent_bot, account: account), inbox: bot_inbox)
  end

  # `inbox: inbox()` (com parenteses): sem eles o parametro se autorreferencia
  # e devolve nil em vez do inbox compartilhado (Lint/CircularArgumentReference).
  def conversa(inbox: inbox(), team: nil, assignee: nil, created_at: 2.days.ago) # rubocop:disable Style/MethodCallWithoutArgsParentheses
    create(:conversation, account: account, inbox: inbox, contact: contact, team: team,
                          assignee: assignee, created_at: created_at)
  end

  # Eventos saem do listener real, nao de factory -- e ele que decide se o
  # gemeo `conversation_bot_resolved` sai (mesma tecnica de
  # conversation_ownership_finder_spec.rb).
  def resolve!(conversation, at: Time.current)
    listener.conversation_resolved(Events::Base.new('conversation.resolved', at, conversation: conversation.reload))
  end

  # Mensagem do agente + evento first_response, no mesmo instante.
  def responder!(conversation, sender: agent, at: Time.current)
    message = create(:message, message_type: 'outgoing', sender: sender, account: account,
                               inbox: conversation.inbox, conversation: conversation, created_at: at)
    listener.first_reply_created(Events::Base.new('first.reply.created', at, message: message))
    message
  end

  describe '#metrics' do
    it 'devolve as cinco secoes' do
      expect(builder.metrics.keys).to contain_exactly(:kpis, :daily_evolution, :by_team, :by_agent, :capacity_vs_demand)
    end
  end

  describe '#kpis (via metrics)' do
    it 'total conta conversas criadas no periodo' do
      2.times { conversa }

      expect(builder.metrics[:kpis][:current][:total]).to eq(2)
    end

    it 'TME medio e maximo vem so de first_response de conversas do periodo' do
      c1 = conversa(assignee: agent)
      responder!(c1, at: c1.created_at + 30.seconds)
      c2 = conversa(assignee: agent)
      responder!(c2, at: c2.created_at + 90.seconds)

      kpis = builder.metrics[:kpis][:current]
      expect(kpis[:avg_wait_seconds]).to eq(60)
      expect(kpis[:max_wait_seconds]).to eq(90)
    end

    it 'devolve zero em vez de dividir por zero quando nao ha conversa' do
      kpis = builder.metrics[:kpis][:current]
      expect(kpis).to eq(total: 0, avg_wait_seconds: 0, max_wait_seconds: 0, abandon_rate: 0.0, abandoned_count: 0)
    end

    it 'compara com o periodo anterior de mesma duracao' do
      dentro = conversa(created_at: 3.days.ago)
      resolve!(dentro, at: 3.days.ago)
      fora = conversa(created_at: 20.days.ago)
      resolve!(fora, at: 20.days.ago)

      expect(builder.metrics[:kpis][:current][:total]).to eq(1)
      expect(builder.metrics[:kpis][:previous][:total]).to eq(0)
    end
  end

  describe 'abandono' do
    it 'nao conta quando o robo resolve sozinho, mesmo sem first_response' do
      conversation = conversa(inbox: bot_inbox)
      resolve!(conversation)

      expect(builder.metrics[:kpis][:current][:abandoned_count]).to eq(0)
    end

    it 'nao conta quando um humano respondeu antes de resolver' do
      conversation = conversa(assignee: agent)
      responder!(conversation, at: conversation.created_at + 1.minute)
      resolve!(conversation, at: conversation.created_at + 2.minutes)

      expect(builder.metrics[:kpis][:current][:abandoned_count]).to eq(0)
    end

    it 'conta quando a resolucao e humana e nunca houve first_response' do
      # Caixa comum (sem bot ativo) => o finder classifica como humana mesmo
      # sem assignee, por nao existir o gemeo `conversation_bot_resolved`.
      outro_inbox = create(:inbox, account: account)
      humana = conversa(inbox: outro_inbox)
      resolve!(humana)

      expect(builder.metrics[:kpis][:current][:abandoned_count]).to eq(1)
    end

    it 'conta uma unica vez quando a conversa e reaberta e resolvida duas vezes' do
      outro_inbox = create(:inbox, account: account)
      conversation = conversa(inbox: outro_inbox)
      resolve!(conversation, at: 3.days.ago)
      conversation.update!(status: :open)
      resolve!(conversation, at: 2.days.ago)

      expect(builder.metrics[:kpis][:current][:abandoned_count]).to eq(1)
    end

    it 'nao conta conversa ainda aberta' do
      outro_inbox = create(:inbox, account: account)
      conversa(inbox: outro_inbox)

      expect(builder.metrics[:kpis][:current][:abandoned_count]).to eq(0)
    end
  end

  describe '#daily_evolution' do
    it 'agrupa volume e TME pela mesma data (conversations.created_at)' do
      dia1 = conversa(assignee: agent, created_at: 3.days.ago.beginning_of_day + 10.hours)
      # first_response registrado no dia SEGUINTE, mas a conversa foi criada no dia1 --
      # sem a correcao do eixo, o TME apareceria sob a data do evento, nao da conversa.
      responder!(dia1, at: 2.days.ago.beginning_of_day + 9.hours)

      resultado = builder.daily_evolution.index_by { |row| row[:date] }
      chave1 = 3.days.ago.beginning_of_day.strftime('%Y-%m-%d')
      chave2 = 2.days.ago.beginning_of_day.strftime('%Y-%m-%d')

      expect(resultado[chave1][:volume]).to eq(1)
      expect(resultado[chave1][:avg_wait_minutes]).to be > 0
      expect(resultado).not_to have_key(chave2)
    end
  end

  describe '#by_team' do
    it 'enumera todas as equipes da conta, inclusive as ociosas no periodo' do
      ativa = create(:team, account: account, name: 'Suporte')
      ociosa = create(:team, account: account, name: 'Vendas')
      conversa(team: ativa, assignee: agent)

      resultado = builder.by_team.index_by { |row| row[:id] }

      # Team normaliza o nome para minusculas (before_validation) -- comparar
      # com o `.name` real do model, nao com o literal que a factory recebeu.
      expect(resultado[ativa.id]).to include(name: ativa.name, total: 1)
      expect(resultado[ociosa.id]).to include(name: ociosa.name, total: 0)
    end

    it 'inclui a linha "sem equipe" so quando ha conversa sem equipe' do
      conversa(team: nil)

      resultado = builder.by_team.index_by { |row| row[:id] }

      expect(resultado[nil]).to include(name: nil, total: 1)
    end

    it 'nao inclui a linha "sem equipe" quando toda conversa tem equipe' do
      time = create(:team, account: account)
      conversa(team: time)

      expect(builder.by_team.map { |row| row[:id] }).not_to include(nil)
    end

    it 'conta abandono por equipe' do
      time = create(:team, account: account)
      conversation = conversa(team: time)
      resolve!(conversation)

      resultado = builder.by_team.index_by { |row| row[:id] }
      expect(resultado[time.id][:abandoned]).to eq(1)
    end

    # Achado da revisao desta fatia: enumerar a conta inteira quando ha
    # filtro de team_id mostrava "0" para toda equipe fora do filtro,
    # indistinguivel de "equipe sem atendimento no periodo".
    it 'so lista a equipe filtrada quando params[:team_id] esta presente' do
      filtrada = create(:team, account: account)
      outra = create(:team, account: account)
      conversa(team: filtrada, assignee: agent)
      conversa(team: outra, assignee: agent)

      filtrado = described_class.new(account, params.merge(team_id: filtrada.id))

      expect(filtrado.by_team.map { |row| row[:id] }).to contain_exactly(filtrada.id)
    end
  end

  describe '#by_agent' do
    it 'so lista agente com conversa atribuida no periodo, nome nulo nao aparece' do
      conversa(assignee: agent)
      conversa # sem atendente -- nao deve contar em by_agent

      resultado = builder.by_agent.index_by { |row| row[:id] }

      expect(resultado[agent.id]).to include(name: 'Ana Souza', total: 1)
      expect(resultado.keys).not_to include(nil)
      expect(builder.by_agent.sum { |row| row[:total] }).to eq(1)
    end

    it 'calcula % de carga sobre o total atribuido' do
      outro = create(:user, account: account, name: 'Bruno')
      conversa(assignee: agent)
      conversa(assignee: agent)
      conversa(assignee: outro)

      resultado = builder.by_agent.index_by { |row| row[:id] }
      expect(resultado[agent.id][:load_pct]).to eq(66.7)
      expect(resultado[outro.id][:load_pct]).to eq(33.3)
    end
  end

  describe '#capacity_vs_demand' do
    it 'capacidade e agentes da equipe x referencia, uso capado em 100%' do
      time = create(:team, account: account)
      create(:team_member, team: time, user: agent)
      5.times { conversa(team: time, assignee: agent) }

      linha = builder.capacity_vs_demand.find { |row| row[:id] == time.id }
      expect(linha[:agents]).to eq(1)
      expect(linha[:demand]).to eq(5)
      expect(linha[:usage_pct]).to eq(100)
    end

    it 'equipe sem agente tem capacidade zero e uso 100% quando ha demanda' do
      time = create(:team, account: account)
      conversa(team: time)

      linha = builder.capacity_vs_demand.find { |row| row[:id] == time.id }
      expect(linha[:capacity]).to eq(0)
      expect(linha[:usage_pct]).to eq(100)
    end

    # Deriva de by_team (o mesmo achado se aplica aqui de graca), mas trava
    # explicitamente para nao regredir se capacity_vs_demand parar de reusar
    # by_team no futuro.
    it 'so lista a equipe filtrada quando params[:team_id] esta presente' do
      filtrada = create(:team, account: account)
      outra = create(:team, account: account)
      conversa(team: filtrada, assignee: agent)
      conversa(team: outra, assignee: agent)

      filtrado = described_class.new(account, params.merge(team_id: filtrada.id))

      expect(filtrado.capacity_vs_demand.map { |row| row[:id] }).to contain_exactly(filtrada.id)
    end
  end

  describe 'recorte Todos/Humanos/IA' do
    it 'delega para o Reports::ConversationOwnershipFinder, nao duplica o predicado' do
      conversa(inbox: bot_inbox)
      conversa(inbox: bot_inbox, assignee: agent)

      bot_builder = described_class.new(account, params.merge(agent_type: 'bot'))
      human_builder = described_class.new(account, params.merge(agent_type: 'human'))

      expect(bot_builder.metrics[:kpis][:current][:total]).to eq(1)
      expect(human_builder.metrics[:kpis][:current][:total]).to eq(1)
    end
  end

  describe 'desempenho' do
    it 'usa NOT EXISTS correlacionado para abandono e handoff, nao NOT IN' do
      outro_inbox = create(:inbox, account: account)
      conversa(inbox: outro_inbox)

      reporting_events_queries = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        reporting_events_queries << payload[:sql] if payload[:sql].include?('reporting_events') && !payload[:cached]
      end

      described_class.new(account, params.merge(agent_type: 'bot')).metrics

      expect(reporting_events_queries).not_to be_empty
      expect(reporting_events_queries.grep(/NOT IN \(SELECT/)).to be_empty
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end

    it 'calcula TME medio e maximo numa unica consulta, nao duas separadas' do
      conversation = conversa(assignee: agent)
      responder!(conversation, at: conversation.created_at + 1.minute)

      wait_queries = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        wait_queries << payload[:sql] if payload[:sql].include?('AVG(reporting_events.value)') && !payload[:cached]
      end

      builder.by_team

      expect(wait_queries.size).to eq(1)
      expect(wait_queries.first).to match(/MAX\(reporting_events\.value\)/)
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end

    it 'inclui conversa criada exatamente na fronteira de since e until' do
      since_time = 7.days.ago.change(usec: 0)
      until_time = since_time + 1.hour

      conversa(created_at: since_time)
      conversa(created_at: until_time)

      builder_com_fronteira = described_class.new(
        account, since: since_time.to_i.to_s, until: until_time.to_i.to_s
      )

      expect(builder_com_fronteira.metrics[:kpis][:current][:total]).to eq(2)
    end

    it 'periodo anterior nao conta o instante exato da fronteira duas vezes' do
      since_time = 7.days.ago.change(usec: 0)
      until_time = since_time + 6.days
      conversa(created_at: since_time)

      builder_com_fronteira = described_class.new(
        account, since: since_time.to_i.to_s, until: until_time.to_i.to_s
      )

      expect(builder_com_fronteira.metrics[:kpis][:current][:total]).to eq(1)
      expect(builder_com_fronteira.metrics[:kpis][:previous][:total]).to eq(0)
    end

    it 'nunca le conversa ou evento de outra conta' do
      outra_conta = create(:account)
      outro_inbox_ac = create(:inbox, account: outra_conta)
      outra_conversa = create(:conversation, account: outra_conta, inbox: outro_inbox_ac,
                                             contact: create(:contact, account: outra_conta))
      ReportingEventListener.instance.conversation_resolved(
        Events::Base.new('conversation.resolved', Time.current, conversation: outra_conversa.reload)
      )

      expect(builder.metrics[:kpis][:current][:total]).to eq(0)
      expect(builder.by_team).to eq([])
      expect(builder.by_agent).to eq([])
    end
  end
end
