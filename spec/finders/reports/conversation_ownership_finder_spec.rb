require 'rails_helper'

RSpec.describe Reports::ConversationOwnershipFinder do
  subject(:finder) { described_class.new(account) }

  let(:account) { create(:account) }
  let(:listener) { ReportingEventListener.instance }
  let(:agent) { create(:user, account: account) }
  let(:bot_inbox) { create(:inbox, account: account) }
  let(:plain_inbox) { create(:inbox, account: account) }

  before do
    create(:agent_bot_inbox, agent_bot: create(:agent_bot, account: account), inbox: bot_inbox)
  end

  # Os eventos saem do listener real, nao da factory: e ele que decide se o
  # gemeo `conversation_bot_resolved` sai, e e exatamente esse contrato que o
  # classificador aposta. Factory aqui testaria a nossa suposicao sobre o
  # upstream, nao o upstream.
  def resolve!(conversation, at: Time.current)
    listener.conversation_resolved(Events::Base.new('conversation.resolved', at, conversation: conversation.reload))
  end

  def open!(conversation, at: Time.current)
    listener.conversation_opened(Events::Base.new('conversation.opened', at, conversation: conversation.reload))
  end

  def handoff!(conversation, at: Time.current)
    listener.conversation_bot_handoff(Events::Base.new('conversation.bot_handoff', at, conversation: conversation.reload))
  end

  def first_reply!(message)
    listener.first_reply_created(Events::Base.new('first.reply.created', message.created_at, message: message))
  end

  def bot_conversation(assignee: nil)
    create(:conversation, account: account, inbox: bot_inbox, assignee: assignee)
  end

  # Uma etiqueta por resolucao, na ordem em que aconteceram.
  def classification_of(conversation)
    bot_ids = finder.resolutions('bot').where(conversation_id: conversation.id).pluck(:id)
    finder.resolutions.where(conversation_id: conversation.id).order(:event_end_time, :id).map do |event|
      bot_ids.include?(event.id) ? 'bot' : 'human'
    end
  end

  describe 'a conversa que so o robo tocou' do
    it 'e do robo quando nasce pendente e o robo resolve sozinha' do
      conversation = bot_conversation
      resolve!(conversation)

      expect(classification_of(conversation)).to eq(['bot'])
    end

    it 'continua do robo mesmo com mensagem enviada pelo proprio robo' do
      conversation = bot_conversation
      create(:message, message_type: 'outgoing', sender: bot_inbox.agent_bot,
                       account: account, inbox: bot_inbox, conversation: conversation)
      resolve!(conversation)

      expect(classification_of(conversation)).to eq(['bot'])
    end
  end

  describe 'evidencia de que um humano entrou' do
    it 'e humana quando alguem abriu a conversa antes de resolver' do
      conversation = bot_conversation
      open!(conversation, at: 2.hours.ago)
      resolve!(conversation, at: 1.hour.ago)

      expect(classification_of(conversation)).to eq(['human'])
    end

    # Este e o caso que so a condicao de abertura pega: sem mensagem nenhuma, o
    # gemeo do bot sai normalmente e o evento nao tem assignee.
    it 'e humana quando alguem abriu, ficou calado e resolveu' do
      conversation = bot_conversation
      open!(conversation, at: 2.hours.ago)
      resolve!(conversation, at: 1.hour.ago)

      expect(account.reporting_events.where(name: 'conversation_bot_resolved').count).to eq(1)
      expect(classification_of(conversation)).to eq(['human'])
    end

    it 'e humana quando um agente respondeu, mesmo sem se atribuir' do
      conversation = bot_conversation
      create(:message, message_type: 'outgoing', sender: agent,
                       account: account, inbox: bot_inbox, conversation: conversation)
      resolve!(conversation)

      expect(classification_of(conversation)).to eq(['human'])
    end

    # Coexistencia do WhatsApp: a resposta dada pelo celular entra como outgoing
    # sem remetente, entao nao barra o gemeo do bot. O que a denuncia e o
    # `first_response`, que o Chatwoot grava para ela.
    it 'e humana quando a resposta veio pelo celular, sem remetente na mensagem' do
      conversation = bot_conversation
      echo = create(:message, :bot_message, account: account, inbox: bot_inbox,
                                            conversation: conversation, created_at: 2.hours.ago)
      first_reply!(echo)
      resolve!(conversation, at: 1.hour.ago)

      expect(account.reporting_events.where(name: 'conversation_bot_resolved').count).to eq(1)
      expect(classification_of(conversation)).to eq(['human'])
    end

    it 'e humana quando houve handoff do robo para gente' do
      conversation = bot_conversation
      handoff!(conversation, at: 2.hours.ago)
      resolve!(conversation, at: 1.hour.ago)

      expect(classification_of(conversation)).to eq(['human'])
    end

    # Historico anterior a v4.5.0, quando `conversation_opened` ainda nao existia:
    # o handoff e a unica pista, e ela precisa continuar valendo.
    it 'ignora o handoff que aconteceu depois daquela resolucao' do
      conversation = bot_conversation
      resolve!(conversation, at: 2.hours.ago)
      handoff!(conversation, at: 1.hour.ago)

      expect(classification_of(conversation)).to eq(['bot'])
    end
  end

  describe 'atribuicao' do
    it 'e humana quando a pendente estava atribuida na hora de resolver' do
      # E o caso da auto-atribuicao por equipe, que atribui sem abrir.
      conversation = bot_conversation(assignee: agent)
      resolve!(conversation)

      expect(classification_of(conversation)).to eq(['human'])
    end

    # Lacuna aceita e documentada: atribuicao nao deixa rastro imutavel no 4.17,
    # entao atribuir e desatribuir em silencio nao aparece. Nao ha trabalho
    # humano para creditar nesse caso.
    it 'conta como robo quando a atribuicao foi desfeita antes de resolver' do
      conversation = bot_conversation(assignee: agent)
      conversation.update!(assignee: nil)
      resolve!(conversation)

      expect(classification_of(conversation)).to eq(['bot'])
    end

    it 'nao muda a classificacao de um periodo fechado quando alguem atribui depois' do
      conversation = bot_conversation
      resolve!(conversation, at: 30.days.ago)
      expect(classification_of(conversation)).to eq(['bot'])

      conversation.update!(assignee: agent)

      expect(classification_of(conversation)).to eq(['bot'])
    end
  end

  describe 'caixa sem robo' do
    it 'e humana, porque nao existe gemeo de resolucao do bot' do
      conversation = create(:conversation, account: account, inbox: plain_inbox)
      resolve!(conversation)

      expect(classification_of(conversation)).to eq(['human'])
    end

    # Divergencia conhecida: pela regra literal seria do robo, mas desligar o
    # robo depois nao pode reescrever o passado, e o gemeo e a unica prova
    # imutavel de que havia robo na hora.
    it 'e humana quando o robo foi desligado antes da resolucao' do
      conversation = bot_conversation
      bot_inbox.agent_bot_inbox.destroy!
      resolve!(conversation)

      expect(classification_of(conversation)).to eq(['human'])
    end
  end

  describe 'conversa reaberta' do
    it 'classifica cada resolucao por si: robo primeiro, humano depois' do
      conversation = bot_conversation
      resolve!(conversation, at: 3.hours.ago)
      handoff!(conversation, at: 2.hours.ago)
      conversation.update!(assignee: agent)
      resolve!(conversation, at: 1.hour.ago)

      expect(classification_of(conversation)).to eq(%w[bot human])
    end
  end

  describe 'bordas dos dados' do
    it 'trata resolucao sem event_end_time como humana, sem furar a particao' do
      conversation = bot_conversation
      %w[conversation_resolved conversation_bot_resolved].each do |name|
        create(:reporting_event, account: account, inbox: bot_inbox, conversation: conversation,
                                 name: name, user: nil, event_end_time: nil)
      end

      expect(classification_of(conversation)).to eq(['human'])
      expect(finder.resolutions('bot').count + finder.resolutions('human').count).to eq(finder.resolutions.count)
    end

    # O proprio listener avisa que um retry do Sidekiq pode inserir o evento de
    # novo. Duplicata nao pode mudar o lado, so a contagem.
    it 'mantem as duas copias de um evento duplicado no mesmo lado' do
      conversation = bot_conversation
      resolve!(conversation, at: 1.hour.ago)
      resolve!(conversation, at: 1.hour.ago)

      expect(classification_of(conversation)).to eq(%w[bot bot])
    end

    it 'nunca enxerga evento de outra conta' do
      other_account = create(:account)
      other_inbox = create(:inbox, account: other_account)
      create(:agent_bot_inbox, agent_bot: create(:agent_bot, account: other_account), inbox: other_inbox)
      other_conversation = create(:conversation, account: other_account, inbox: other_inbox)
      resolve!(other_conversation)

      expect(finder.resolutions.count).to eq(0)
      expect(described_class.new(other_account).resolutions('bot').count).to eq(1)
    end
  end

  describe '#resolutions' do
    it 'devolve todas as resolucoes quando nao pedem um dono' do
      resolve!(bot_conversation)
      resolve!(bot_conversation(assignee: agent))

      expect(finder.resolutions.count).to eq(2)
    end

    it 'recusa um dono que nao existe em vez de devolver escopo errado' do
      expect { finder.resolutions('ia') }.to raise_error(ArgumentError, /unknown owner/)
    end

    it 'particiona: robo mais humano fecha o total, em qualquer combinacao' do
      resolve!(bot_conversation)
      resolve!(bot_conversation(assignee: agent))
      resolve!(create(:conversation, account: account, inbox: plain_inbox))
      com_abertura = bot_conversation
      open!(com_abertura, at: 2.hours.ago)
      resolve!(com_abertura, at: 1.hour.ago)

      bot = finder.resolutions('bot').count
      human = finder.resolutions('human').count

      expect(bot).to eq(1)
      expect(bot + human).to eq(finder.resolutions.count)
    end
  end
end
