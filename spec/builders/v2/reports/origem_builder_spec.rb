require 'rails_helper'

RSpec.describe V2::Reports::OrigemBuilder do
  subject(:builder) { described_class.new(account, params) }

  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:bot_inbox) { create(:inbox, account: account) }
  let!(:agent) { create(:user, account: account, name: 'Ana Souza') }
  let(:params) { { since: 7.days.ago.to_i.to_s, until: Time.current.to_i.to_s } }

  before do
    create(:agent_bot_inbox, agent_bot: create(:agent_bot, account: account), inbox: bot_inbox)
  end

  # `inbox: inbox()` (com parenteses), nao `inbox: inbox`: sem os parenteses o
  # parametro se autorreferencia (o nome do parametro sombreia o `let`),
  # devolvendo nil em vez do inbox compartilhado -- rubocop pegou isto
  # (Lint/CircularArgumentReference).
  def conversa(inbox: inbox(), team: nil, assignee: nil, created_at: 2.days.ago) # rubocop:disable Style/MethodCallWithoutArgsParentheses
    create(:conversation, account: account, inbox: inbox, contact: contact, team: team,
                          assignee: assignee, created_at: created_at)
  end

  # A primeira mensagem nao-activity decide recebido/efetuado. `created_at` da
  # mensagem cai um pouco depois da conversa, como o listener real grava.
  def mensagem(conversation, tipo:, sender: nil, additional_attributes: {})
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation,
                     message_type: tipo, sender: sender, additional_attributes: additional_attributes,
                     created_at: conversation.created_at + 1.minute)
  end

  describe '#metrics' do
    it 'devolve as seis secoes' do
      expect(builder.metrics.keys).to contain_exactly(
        :summary, :daily_evolution, :by_origin, :by_team, :by_inbox, :by_agent
      )
    end
  end

  describe '#summary' do
    it 'separa recebido (cliente comecou) de efetuado (empresa comecou)' do
      recebida = conversa
      mensagem(recebida, tipo: 'incoming')

      efetuada = conversa
      mensagem(efetuada, tipo: 'outgoing', sender: agent)

      resultado = builder.summary

      expect(resultado[:total]).to eq(2)
      expect(resultado[:recebidos]).to eq(1)
      expect(resultado[:efetuados]).to eq(1)
      expect(resultado[:recebidos_pct]).to eq(50.0)
      expect(resultado[:efetuados_pct]).to eq(50.0)
    end

    it 'conta conversa sem mensagem nao-activity como recebida' do
      conversa

      expect(builder.summary[:recebidos]).to eq(1)
      expect(builder.summary[:efetuados]).to eq(0)
    end

    it 'ignora mensagem activity ao decidir quem comecou' do
      efetuada = conversa
      create(:message, account: account, inbox: efetuada.inbox, conversation: efetuada,
                       message_type: 'activity', created_at: efetuada.created_at)
      mensagem(efetuada, tipo: 'outgoing', sender: agent)

      expect(builder.summary[:efetuados]).to eq(1)
    end

    it 'devolve zero em vez de dividir por zero quando nao ha conversa' do
      expect(builder.summary).to eq(
        total: 0, recebidos: 0, efetuados: 0, recebidos_pct: 0, efetuados_pct: 0
      )
    end

    it 'nunca le conversa de outra conta' do
      outra_conta = create(:account)
      outro_inbox = create(:inbox, account: outra_conta)
      outra_conversa = create(:conversation, account: outra_conta, inbox: outro_inbox,
                                             contact: create(:contact, account: outra_conta))
      create(:message, account: outra_conta, inbox: outro_inbox, conversation: outra_conversa,
                       message_type: 'incoming', created_at: outra_conversa.created_at + 1.minute)

      expect(builder.summary[:total]).to eq(0)
    end
  end

  describe '#daily_evolution' do
    it 'agrupa por dia e mantem recebido/efetuado separados' do
      dia1 = conversa(created_at: 3.days.ago.beginning_of_day + 10.hours)
      mensagem(dia1, tipo: 'incoming')

      outra_no_mesmo_dia = conversa(created_at: 3.days.ago.beginning_of_day + 14.hours)
      mensagem(outra_no_mesmo_dia, tipo: 'outgoing', sender: agent)

      dia2 = conversa(created_at: 1.day.ago.beginning_of_day + 9.hours)
      mensagem(dia2, tipo: 'incoming')

      resultado = builder.daily_evolution.index_by { |row| row[:date] }
      chave1 = 3.days.ago.beginning_of_day.strftime('%Y-%m-%d')
      chave2 = 1.day.ago.beginning_of_day.strftime('%Y-%m-%d')

      expect(resultado[chave1]).to eq(date: chave1, recebidos: 1, efetuados: 1)
      expect(resultado[chave2]).to eq(date: chave2, recebidos: 1, efetuados: 0)
    end
  end

  describe '#by_origin' do
    it 'da prioridade a campanha sobre o remetente' do
      c = conversa
      mensagem(c, tipo: 'outgoing', sender: agent, additional_attributes: { campaign_id: 42 })

      expect(builder.by_origin).to contain_exactly(
        include(key: 'campaign', kind: 'automation', count: 1, pct: 100.0)
      )
    end

    it 'classifica robo, template e atendente direto' do
      robo = conversa
      mensagem(robo, tipo: 'outgoing', sender: bot_inbox.agent_bot)

      via_template = conversa
      mensagem(via_template, tipo: 'template', sender: agent)

      direto = conversa
      mensagem(direto, tipo: 'outgoing', sender: agent)

      resultado = builder.by_origin.index_by { |row| row[:key] }

      expect(resultado['bot']).to include(kind: 'automation', count: 1)
      expect(resultado['template']).to include(kind: 'human', count: 1)
      expect(resultado['agent_direct']).to include(kind: 'human', count: 1)
    end

    it 'nao considera conversa recebida (cliente comecou)' do
      recebida = conversa
      mensagem(recebida, tipo: 'incoming')

      expect(builder.by_origin).to eq([])
    end
  end

  describe '#by_team' do
    it 'conta recebido/efetuado por equipe, e null quando nao ha equipe' do
      suporte = create(:team, account: account)
      com_equipe = conversa(team: suporte)
      mensagem(com_equipe, tipo: 'incoming')

      sem_equipe = conversa
      mensagem(sem_equipe, tipo: 'outgoing', sender: agent)

      resultado = builder.by_team.index_by { |row| row[:id] }

      expect(resultado[suporte.id]).to include(name: suporte.name, total: 1, recebidos: 1, efetuados: 0)
      expect(resultado[nil]).to include(name: nil, total: 1, recebidos: 0, efetuados: 1)
    end
  end

  describe '#by_inbox' do
    it 'conta recebido/efetuado por caixa' do
      outro_inbox = create(:inbox, account: account)
      c1 = conversa(inbox: inbox)
      mensagem(c1, tipo: 'incoming')
      c2 = conversa(inbox: outro_inbox)
      mensagem(c2, tipo: 'outgoing', sender: agent)

      resultado = builder.by_inbox.index_by { |row| row[:id] }

      expect(resultado[inbox.id]).to include(name: inbox.name, recebidos: 1, efetuados: 0)
      expect(resultado[outro_inbox.id]).to include(name: outro_inbox.name, recebidos: 0, efetuados: 1)
    end
  end

  describe '#by_agent' do
    it 'conta recebido/efetuado por atendente, e null quando nao ha atribuicao' do
      atribuida = conversa(assignee: agent)
      mensagem(atribuida, tipo: 'outgoing', sender: agent)

      sem_atendente = conversa
      mensagem(sem_atendente, tipo: 'incoming')

      resultado = builder.by_agent.index_by { |row| row[:id] }

      expect(resultado[agent.id]).to include(name: 'Ana Souza', efetuados: 1, recebidos: 0)
      expect(resultado[nil]).to include(name: nil, recebidos: 1, efetuados: 0)
    end
  end

  describe 'recorte Todos/Humanos/IA' do
    it 'delega para o Reports::ConversationOwnershipFinder, nao duplica o predicado' do
      conduzida_pelo_bot = conversa(inbox: bot_inbox)
      mensagem(conduzida_pelo_bot, tipo: 'incoming')

      com_agente = conversa(inbox: bot_inbox, assignee: agent)
      mensagem(com_agente, tipo: 'incoming')

      bot_builder = described_class.new(account, params.merge(agent_type: 'bot'))
      human_builder = described_class.new(account, params.merge(agent_type: 'human'))

      expect(bot_builder.summary[:total]).to eq(1)
      expect(human_builder.summary[:total]).to eq(1)
    end
  end

  describe 'desempenho' do
    # Achado da fatia 2 (revisao de banco): NOT IN (subquery) nao correlacionado
    # varre o historico inteiro de handoff da conta. Trava que o recorte
    # bot/human aqui usa a mesma forma corrigida do finder (NOT EXISTS), nao
    # uma copia local do predicado antigo.
    it 'usa NOT EXISTS correlacionado para o handoff, nao NOT IN sobre o historico inteiro' do
      conversa(inbox: bot_inbox)

      reporting_events_queries = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        reporting_events_queries << payload[:sql] if payload[:sql].include?('reporting_events') && !payload[:cached]
      end

      described_class.new(account, params.merge(agent_type: 'bot')).summary

      expect(reporting_events_queries).not_to be_empty
      expect(reporting_events_queries).to all(match(/NOT EXISTS/))
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end

    # Achado documentado no plano do port (correcao de agosto): sem o escopo
    # por account_id, o DISTINCT ON de first_message_table varre e ordena a
    # tabela `messages` inteira, de todas as contas.
    it 'escopa first_message_table por account_id' do
      efetuada = conversa
      mensagem(efetuada, tipo: 'outgoing', sender: agent)

      first_message_queries = []
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        first_message_queries << payload[:sql] if payload[:sql].include?('DISTINCT ON (conversation_id)') && !payload[:cached]
      end

      builder.summary

      expect(first_message_queries).not_to be_empty
      expect(first_message_queries).to all(match(/account_id = #{account.id}\b/))
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end

    it 'nunca mistura mensagem de outra conta no first_message_table' do
      outra_conta = create(:account)
      outro_inbox_ac = create(:inbox, account: outra_conta)
      outra_conversa = create(:conversation, account: outra_conta, inbox: outro_inbox_ac,
                                             contact: create(:contact, account: outra_conta))
      create(:message, account: outra_conta, inbox: outro_inbox_ac, conversation: outra_conversa,
                       message_type: 'outgoing', sender: create(:user, account: outra_conta),
                       created_at: outra_conversa.created_at + 1.minute)

      nossa = conversa
      mensagem(nossa, tipo: 'incoming')

      expect(builder.summary[:total]).to eq(1)
      expect(builder.by_origin).to eq([])
    end
  end
end
