require 'rails_helper'

RSpec.describe V2::Reports::SupervisorBuilder do
  subject(:builder) { described_class.new(account, params) }

  let(:account) { create(:account) }
  let(:bot_inbox) { create(:inbox, account: account) }
  let(:params) { {} }
  let!(:agent) { create(:user, account: account, name: 'Ana Souza') }

  before do
    create(:agent_bot_inbox, agent_bot: create(:agent_bot, account: account), inbox: bot_inbox)
    # Presenca vem do Redis; sem stub o teste dependeria de estado externo.
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ agent.id.to_s => 'online' })
  end

  # `determine_conversation_status` (before_create) forca toda conversa nova
  # numa caixa com bot para `pending` -- e a regra do produto, "conversa em
  # caixa com robo nasce pendente". Por isso o status pedido so pode ser
  # aplicado DEPOIS de criar, num `update!` (que nao passa por esse callback).
  def conversation!(status:, inbox: bot_inbox, assignee: nil, first_reply_created_at: nil)
    conversation = create(:conversation, account: account, inbox: inbox, assignee: assignee,
                                         first_reply_created_at: first_reply_created_at)
    conversation.update!(status: status)
    conversation
  end

  def na_fila(inbox: bot_inbox, status: :open)
    conversation!(status: status, inbox: inbox, assignee: nil)
  end

  def atendendo(inbox: bot_inbox)
    conversation!(status: :open, inbox: inbox, assignee: agent, first_reply_created_at: 1.hour.ago)
  end

  def aguardando_pendente(inbox: bot_inbox)
    conversation!(status: :pending, inbox: inbox, assignee: agent, first_reply_created_at: 1.hour.ago)
  end

  def aguardando_sem_resposta(inbox: bot_inbox)
    conversation!(status: :open, inbox: inbox, assignee: agent, first_reply_created_at: nil)
  end

  def handoff!(conversation)
    ReportingEventListener.instance.conversation_bot_handoff(
      Events::Base.new('conversation.bot_handoff', Time.current, conversation: conversation.reload)
    )
  end

  describe '#metrics — tabela de conversas' do
    it 'separa na_fila, atendendo e aguardando (pendente ou sem resposta)' do
      fila = na_fila
      trabalhando = atendendo
      pendente = aguardando_pendente
      muda = aguardando_sem_resposta

      counts = builder.metrics[:conversations][:counts]
      statuses = builder.metrics[:conversations][:items].to_h { |item| [item[:id], item[:status]] }

      expect(counts).to eq(all: 4, na_fila: 1, atendendo: 1, aguardando: 2)
      expect(statuses[fila.display_id]).to eq('na_fila')
      expect(statuses[trabalhando.display_id]).to eq('atendendo')
      expect(statuses[pendente.display_id]).to eq('aguardando')
      expect(statuses[muda.display_id]).to eq('aguardando')
    end

    it 'filtra a lista pelo status_filter pedido, sem afetar os counts' do
      na_fila
      atendendo

      resultado = described_class.new(account, status_filter: 'na_fila').metrics[:conversations]

      expect(resultado[:items].map { |i| i[:status] }).to eq(['na_fila'])
      expect(resultado[:counts][:all]).to eq(2)
    end

    it 'so enxerga conversas do time pedido' do
      time = create(:team, account: account)
      da_equipe = na_fila
      da_equipe.update!(team: time)
      de_fora = na_fila

      resultado = described_class.new(account, team_id: time.id).metrics[:conversations]

      expect(resultado[:items].map { |i| i[:id] }).to contain_exactly(da_equipe.display_id)
      expect(resultado[:items].map { |i| i[:id] }).not_to include(de_fora.display_id)
    end
  end

  describe '#metrics — paginacao' do
    it 'pagina o resultado e respeita o per_page pedido' do
      4.times { na_fila }

      pagina1 = described_class.new(account, per_page: '2', page: '1').metrics[:conversations]
      pagina2 = described_class.new(account, per_page: '2', page: '2').metrics[:conversations]

      expect(pagina1[:items].size).to eq(2)
      expect(pagina2[:items].size).to eq(2)
      expect(pagina1[:pagination]).to eq(page: 1, per_page: 2, total_count: 4, total_pages: 2)
      expect(pagina1[:items].map { |i| i[:id] } & pagina2[:items].map { |i| i[:id] }).to be_empty
    end

    it 'limita per_page ao teto, mesmo quando pedem mais' do
      resultado = described_class.new(account, per_page: '500').metrics[:conversations]

      expect(resultado[:pagination][:per_page]).to eq(V2::Reports::SupervisorConversationsTable::MAX_PER_PAGE)
    end
  end

  describe '#metrics — recorte Todos/Humanos/IA' do
    it 'todos ve tanto a conduzida pelo bot quanto a com agente' do
      bot_conversation = na_fila
      human_conversation = atendendo

      itens = described_class.new(account, agent_type: 'all').metrics[:conversations][:items]

      expect(itens.map { |i| i[:id] }).to contain_exactly(bot_conversation.display_id, human_conversation.display_id)
    end

    it 'bot so ve a caixa com bot, sem agente e sem handoff' do
      conduzida_pelo_bot = na_fila
      ja_teve_handoff = na_fila
      handoff!(ja_teve_handoff)
      com_agente = atendendo

      itens = described_class.new(account, agent_type: 'bot').metrics[:conversations][:items]

      expect(itens.map { |i| i[:id] }).to contain_exactly(conduzida_pelo_bot.display_id)
      expect(itens.map { |i| i[:id] }).not_to include(ja_teve_handoff.display_id, com_agente.display_id)
    end

    it 'human ve o resto: handoff, agente atribuido ou caixa sem bot' do
      plain_inbox = create(:inbox, account: account)
      sem_bot = na_fila(inbox: plain_inbox)
      com_agente = atendendo
      conduzida_pelo_bot = na_fila

      itens = described_class.new(account, agent_type: 'human').metrics[:conversations][:items]

      expect(itens.map { |i| i[:id] }).to contain_exactly(sem_bot.display_id, com_agente.display_id)
      expect(itens.map { |i| i[:id] }).not_to include(conduzida_pelo_bot.display_id)
    end
  end

  describe '#metrics — kpis' do
    it 'em_atendimento e status aberto com agente; na_fila e sem agente' do
      na_fila
      atendendo
      # Pendente com agente nao entra em nenhum dos dois -- nem "aberta com
      # agente" nem "sem agente" --, o mesmo recorte que a fonte usa.
      aguardando_pendente

      kpis = builder.metrics[:kpis]

      expect(kpis[:in_progress]).to eq(1)
      expect(kpis[:in_queue]).to eq(1)
    end

    it 'ignora conversas mais antigas que a janela de 30 dias no maior tempo de espera' do
      na_fila.update!(created_at: 45.days.ago)
      recente = na_fila
      recente.update!(created_at: 2.hours.ago)

      kpis = builder.metrics[:kpis]

      expect(kpis[:longest_wait_minutes]).to be_within(1).of(120)
      expect(kpis[:longest_wait_window_days]).to eq(described_class::MAX_WAIT_WINDOW_DAYS)
      expect(kpis[:stale_in_queue]).to eq(1)
    end

    it 'conta agentes online e o total da conta' do
      create(:user, account: account, name: 'Offline Silva')

      kpis = builder.metrics[:kpis]

      expect(kpis[:agents_online]).to eq(1)
      expect(kpis[:agents_total]).to eq(2)
    end

    it 'nunca le conversa de outra conta' do
      outra_conta = create(:account)
      outro_inbox = create(:inbox, account: outra_conta)
      create(:conversation, account: outra_conta, inbox: outro_inbox, status: :open, assignee: nil)

      expect(builder.metrics[:kpis][:in_queue]).to eq(0)
    end
  end
end
