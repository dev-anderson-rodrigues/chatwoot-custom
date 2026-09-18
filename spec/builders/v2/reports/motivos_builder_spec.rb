require 'rails_helper'

RSpec.describe V2::Reports::MotivosBuilder do
  subject(:builder) { described_class.new(account, params) }

  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:bot_inbox) { create(:inbox, account: account) }
  let!(:agent) { create(:user, account: account, name: 'Ana Souza') }
  let(:listener) { ReportingEventListener.instance }
  let(:params) { { since: 7.days.ago.to_i.to_s, until: Time.current.to_i.to_s, labels: %w[financeiro suporte] } }

  before do
    create(:agent_bot_inbox, agent_bot: create(:agent_bot, account: account), inbox: bot_inbox)
    create(:label, account: account, title: 'financeiro', color: '#1f93ff')
  end

  # `inbox: inbox()` (com parenteses): sem eles o parametro se autorreferencia
  # e devolve nil em vez do inbox compartilhado (Lint/CircularArgumentReference).
  def conversa(motivo:, inbox: inbox(), assignee: nil, created_at: 2.days.ago) # rubocop:disable Style/MethodCallWithoutArgsParentheses
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact,
                                         assignee: assignee, created_at: created_at)
    conversation.update!(label_list: Array(motivo))
    conversation
  end

  # Eventos saem do listener real, nao de factory -- e ele que decide se o
  # gemeo `conversation_bot_resolved` sai (mesma tecnica de
  # conversation_ownership_finder_spec.rb). `travel_to` porque o relatorio
  # filtra por `reporting_events.created_at`, a hora em que a linha foi
  # inserida, nao por `event_end_time`.
  def resolve!(conversation, at: Time.current)
    travel_to(at) do
      conversation.update!(status: :resolved)
      listener.conversation_resolved(Events::Base.new('conversation.resolved', at, conversation: conversation.reload))
    end
  end

  def reabrir!(conversation, at: Time.current)
    travel_to(at) { conversation.update!(status: :open) }
  end

  def responder!(conversation, sender: agent, at: Time.current)
    travel_to(at) do
      message = create(:message, message_type: 'outgoing', sender: sender, account: account,
                                 inbox: conversation.inbox, conversation: conversation, created_at: at)
      listener.first_reply_created(Events::Base.new('first.reply.created', at, message: message))
    end
  end

  def reason(metrics, name)
    metrics[:reasons].find { |row| row[:name] == name }
  end

  describe '#metrics' do
    it 'devolve as tres secoes' do
      expect(builder.metrics.keys).to contain_exactly(:kpis, :reasons, :weekly_evolution)
    end

    it 'devolve estrutura vazia sem consultar quando nenhuma etiqueta foi escolhida' do
      conversa(motivo: 'financeiro')

      metrics = described_class.new(account, params.except(:labels)).metrics

      expect(metrics).to eq(described_class::EMPTY_METRICS)
    end

    it 'ignora etiqueta em branco na selecao' do
      conversa(motivo: 'financeiro')

      metrics = described_class.new(account, params.merge(labels: ['financeiro', '', nil])).metrics

      expect(metrics[:kpis][:conversations_total]).to eq(1)
    end
  end

  describe 'volume por motivo' do
    it 'conta conversas do periodo por etiqueta e calcula a participacao' do
      2.times { conversa(motivo: 'financeiro') }
      conversa(motivo: 'suporte')

      metrics = builder.metrics

      expect(reason(metrics, 'financeiro')).to include(total: 2, pct: 66.7)
      expect(reason(metrics, 'suporte')).to include(total: 1, pct: 33.3)
    end

    it 'conta so as etiquetas escolhidas' do
      conversa(motivo: 'financeiro')
      conversa(motivo: 'cobranca')

      expect(builder.metrics[:kpis][:conversations_total]).to eq(1)
    end

    it 'nao conta conversa de outra conta que usa a mesma etiqueta' do
      conversa(motivo: 'financeiro')

      outra_conta = create(:account)
      outra = create(:conversation, account: outra_conta, inbox: create(:inbox, account: outra_conta),
                                    contact: create(:contact, account: outra_conta), created_at: 2.days.ago)
      outra.update!(label_list: ['financeiro'])

      expect(builder.metrics[:kpis][:conversations_total]).to eq(1)
    end

    it 'traz a cor configurada na conta e nil para etiqueta sem label' do
      conversa(motivo: 'financeiro')
      conversa(motivo: 'suporte')

      metrics = builder.metrics

      expect(reason(metrics, 'financeiro')[:color]).to eq('#1f93ff')
      expect(reason(metrics, 'suporte')[:color]).to be_nil
    end
  end

  describe 'periodo anterior' do
    it 'mantem na tabela o motivo que zerou, com o volume anterior cru' do
      conversa(motivo: 'financeiro', created_at: 2.days.ago)
      conversa(motivo: 'suporte', created_at: 10.days.ago)

      linha = reason(builder.metrics, 'suporte')

      expect(linha).to include(total: 0, previous_total: 1)
    end

    it 'nao deixa um motivo zerado virar o destaque dos KPIs' do
      conversa(motivo: 'financeiro', created_at: 2.days.ago)
      conversa(motivo: 'suporte', created_at: 10.days.ago)

      kpis = builder.metrics[:kpis]

      expect(kpis[:reasons_count]).to eq(1)
      expect(kpis[:top_reason]).to include(name: 'financeiro')
      expect(kpis[:slowest_reason]).to be_nil.or include(name: 'financeiro')
    end
  end

  describe 'FCR' do
    it 'conta como resolvida de primeira a conversa resolvida uma unica vez' do
      c = conversa(motivo: 'financeiro')
      resolve!(c, at: 1.day.ago)

      expect(reason(builder.metrics, 'financeiro')).to include(resolved_count: 1, fcr_count: 1, fcr_pct: 100.0)
    end

    it 'nao conta como resolvida de primeira a conversa reaberta e resolvida de novo' do
      c = conversa(motivo: 'financeiro')
      resolve!(c, at: 3.days.ago)
      reabrir!(c, at: 2.days.ago)
      resolve!(c, at: 1.day.ago)

      expect(reason(builder.metrics, 'financeiro')).to include(resolved_count: 1, fcr_count: 0, fcr_pct: 0.0)
    end

    # O criterio da fonte (`HAVING COUNT(*) = 1` dentro da janela) daria FCR
    # aqui, porque so a segunda resolucao cai no periodo olhado. Reabertura e
    # fato do historico da conversa, nao do recorte.
    it 'nao chama de primeira resolucao quando a reabertura ficou fora da janela' do
      c = conversa(motivo: 'financeiro', created_at: 30.days.ago)
      resolve!(c, at: 25.days.ago)
      reabrir!(c, at: 3.days.ago)
      resolve!(c, at: 1.day.ago)

      metrics = described_class.new(account, params.merge(date_field: 'resolved')).metrics

      expect(reason(metrics, 'financeiro')).to include(resolved_count: 1, fcr_count: 0)
    end

    it 'deixa fcr_pct nulo quando nao houve resolucao, em vez de fingir zero' do
      conversa(motivo: 'financeiro')

      expect(reason(builder.metrics, 'financeiro')[:fcr_pct]).to be_nil
    end
  end

  describe 'TMA' do
    # Instantes capturados em variavel antes do `travel_to` de `resolve!`:
    # reavaliar `3.days.ago` dentro do bloco mede a partir do relogio ja movido.
    it 'usa o tempo entre criacao e resolucao' do
      criada_em = 3.days.ago
      c = conversa(motivo: 'financeiro', created_at: criada_em)
      resolve!(c, at: criada_em + 10.minutes)

      expect(reason(builder.metrics, 'financeiro')[:avg_handle_seconds]).to eq(600)
    end

    it 'faz media entre as resolucoes do motivo' do
      primeira = conversa(motivo: 'financeiro', created_at: 3.days.ago)
      resolve!(primeira, at: primeira.created_at + 10.minutes)
      segunda = conversa(motivo: 'financeiro', created_at: 2.days.ago)
      resolve!(segunda, at: segunda.created_at + 30.minutes)

      expect(reason(builder.metrics, 'financeiro')[:avg_handle_seconds]).to eq(1200)
    end
  end

  describe 'date_field' do
    # A fonte usava `status: resolved, updated_at: range`, e qualquer edicao da
    # conversa mexe em `updated_at`. Aqui a conversa foi encerrada fora da
    # janela e so tocada dentro dela: pelo criterio antigo entraria.
    it 'datando pelo encerramento, sai do evento e nao de updated_at' do
      c = conversa(motivo: 'financeiro', created_at: 30.days.ago)
      resolve!(c, at: 20.days.ago)
      c.update!(updated_at: Time.current)

      metrics = described_class.new(account, params.merge(date_field: 'resolved')).metrics

      expect(metrics[:kpis][:conversations_total]).to eq(0)
    end

    it 'datando pelo encerramento, inclui conversa criada antes e resolvida dentro' do
      c = conversa(motivo: 'financeiro', created_at: 30.days.ago)
      resolve!(c, at: 1.day.ago)

      metrics = described_class.new(account, params.merge(date_field: 'resolved')).metrics

      expect(metrics[:kpis][:conversations_total]).to eq(1)
    end
  end

  describe 'participacao do robo' do
    it 'conta resolucao do robo pelo classificador, nao pelo evento solto' do
      c = conversa(motivo: 'financeiro', inbox: bot_inbox)
      resolve!(c, at: 1.day.ago)

      expect(reason(builder.metrics, 'financeiro')[:bot_resolved_pct]).to eq(100.0)
    end

    it 'nao credita ao robo a conversa que um humano respondeu antes de resolver' do
      c = conversa(motivo: 'financeiro', inbox: bot_inbox)
      responder!(c, at: 2.days.ago)
      resolve!(c, at: 1.day.ago)

      expect(reason(builder.metrics, 'financeiro')[:bot_resolved_pct]).to eq(0.0)
    end

    # Denominador e o total de RESOLVIDAS, nao o de conversas: um motivo com
    # muita conversa ainda aberta mostraria participacao do robo baixa mesmo
    # quando o robo fechou tudo que fechou.
    it 'mede participacao do robo sobre as resolvidas, nao sobre o total' do
      resolvida = conversa(motivo: 'financeiro', inbox: bot_inbox)
      resolve!(resolvida, at: 1.day.ago)
      2.times { conversa(motivo: 'financeiro', inbox: bot_inbox) }

      linha = reason(builder.metrics, 'financeiro')

      expect(linha).to include(total: 3, resolved_count: 1, bot_resolved_pct: 100.0)
    end

    # A mesma populacao alimenta volume e resolucao (leitura unica no finder),
    # entao resolvida nunca pode passar o total -- era o que abria caminho para
    # percentual acima de 100% quando as duas saiam de consultas separadas.
    it 'nunca conta mais resolvidas do que conversas do motivo' do
      3.times do |i|
        c = conversa(motivo: 'financeiro', created_at: (i + 1).days.ago)
        resolve!(c, at: c.created_at + 1.hour)
        # Reabre e resolve de novo: duas linhas de conversation_resolved para a
        # mesma conversa.
        reabrir!(c, at: c.created_at + 2.hours)
        resolve!(c, at: c.created_at + 3.hours)
      end

      linha = reason(builder.metrics, 'financeiro')

      expect(linha[:resolved_count]).to be <= linha[:total]
      expect(linha[:bot_resolved_pct]).to be <= 100.0
    end

    it 'mede transferencia separado de quem resolveu' do
      c = conversa(motivo: 'financeiro', inbox: bot_inbox, assignee: agent)
      create(:reporting_event, account_id: account.id, conversation_id: c.id, inbox_id: c.inbox_id,
                               name: 'conversation_bot_handoff', value: 60)
      resolve!(c, at: 1.day.ago)

      linha = reason(builder.metrics, 'financeiro')

      expect(linha[:bot_handoff_pct]).to eq(100.0)
      expect(linha[:bot_resolved_pct]).to eq(0.0)
    end
  end

  describe 'recorte Todos/Humanos/IA' do
    it 'IA traz so conversa conduzida pelo robo' do
      conversa(motivo: 'financeiro', inbox: bot_inbox)
      conversa(motivo: 'financeiro', inbox: inbox, assignee: agent)

      metrics = described_class.new(account, params.merge(agent_type: 'bot')).metrics

      expect(metrics[:kpis][:conversations_total]).to eq(1)
    end

    it 'IA e Humanos somam o total sem recorte' do
      conversa(motivo: 'financeiro', inbox: bot_inbox)
      conversa(motivo: 'financeiro', inbox: inbox, assignee: agent)
      conversa(motivo: 'suporte', inbox: inbox)

      todos = builder.metrics[:kpis][:conversations_total]
      bot = described_class.new(account, params.merge(agent_type: 'bot')).metrics[:kpis][:conversations_total]
      humano = described_class.new(account, params.merge(agent_type: 'human')).metrics[:kpis][:conversations_total]

      expect(bot + humano).to eq(todos)
    end
  end

  describe 'evolucao semanal' do
    it 'devolve uma serie por motivo com ocorrencia, limitada ao topo' do
      3.times { conversa(motivo: 'financeiro') }
      conversa(motivo: 'suporte')

      evolucao = builder.metrics[:weekly_evolution]

      expect(evolucao[:series].map { |serie| serie[:name] }).to eq(%w[financeiro suporte])
      expect(evolucao[:series].first[:data].sum).to eq(3)
    end

    it 'nao cria serie para motivo que zerou no periodo' do
      conversa(motivo: 'financeiro', created_at: 2.days.ago)
      conversa(motivo: 'suporte', created_at: 10.days.ago)

      expect(builder.metrics[:weekly_evolution][:series].map { |serie| serie[:name] }).to eq(['financeiro'])
    end

    it 'devolve vazio quando nao ha nenhum motivo no periodo' do
      expect(builder.metrics[:weekly_evolution]).to eq(labels: [], series: [])
    end
  end
end
