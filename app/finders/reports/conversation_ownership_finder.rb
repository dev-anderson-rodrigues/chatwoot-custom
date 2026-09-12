# [Onda 5 / fatia 0] Quem atendeu: robo ou humano.
#
# A regra e do dono do produto: conversa em caixa com robo nasce pendente, e
# conversa finalizada sem NUNCA ter sido aberta nem atribuida e do robo. "Nunca"
# e historico. `conversations.status` e `conversations.assignee_id` sao estado
# atual e nao servem: atribuir hoje uma conversa resolvida em agosto mudaria o
# numero de agosto.
#
# Por isso a classificacao e por RESOLUCAO e le so fatos gravados uma vez, em
# `reporting_events`:
#
#   1. `user_id IS NULL` na propria linha da resolucao. O listener grava ali quem
#      estava atribuido naquele instante (reporting_event_listener.rb:16).
#   2. Existe o gemeo `conversation_bot_resolved` com o mesmo `event_end_time`.
#      O listener so o grava quando a caixa tinha robo ativo na hora
#      (`create_bot_resolved_event`), e essa e a unica prova imutavel disso:
#      `Inbox#active_bot?` e estado atual, entao desligar o robo depois
#      reescreveria o passado.
#   3. Nao ha evidencia humana ate a resolucao.
#
# `first_response` entra na evidencia humana por causa da coexistencia do
# WhatsApp: resposta dada pelo celular chega como outgoing sem remetente, nao
# barra o gemeo, mas o proprio Chatwoot a trata como resposta humana
# (Message#human_response?). De quebra pega resposta publica via API sem abrir a
# conversa.
#
# Humano e a negacao exata do predicado. Como `IS NULL` e `EXISTS` nunca devolvem
# NULL, robo + humano = todas as resolucoes, sem furo no meio -- inclusive quando
# `event_end_time` e nulo.
#
# Divergencias conhecidas da regra literal, registradas em
# docs-fork/plano-port-coraxy.md: nota privada de humano antes de resolver cai em
# humano (o gemeo exige ausencia de outgoing de User); robo desligado antes da
# resolucao cai em humano; e pendente atribuida e desatribuida em silencio cai em
# robo, porque atribuicao nao deixa rastro imutavel no 4.17.
class Reports::ConversationOwnershipFinder
  OWNERS = %w[bot human].freeze

  # Qualquer um destes prova que um humano tocou a conversa antes da resolucao.
  HUMAN_EVIDENCE_EVENTS = %w[conversation_opened conversation_bot_handoff first_response].freeze

  def initialize(account)
    @account = account
  end

  # Eventos `conversation_resolved` da conta, opcionalmente so os de um dono.
  #
  # Devolve relation, nao array: o chamador compoe janela, caixa, equipe e
  # agregacao por cima. `pluck` + `NOT IN` e o que estourou o statement_timeout
  # em producao, e um NULL na lista zeraria o resultado.
  def resolutions(owner = nil)
    scope = @account.reporting_events.where(name: 'conversation_resolved')

    case owner
    when nil then scope
    when 'bot' then scope.where(bot_resolution_condition)
    when 'human' then scope.where.not(bot_resolution_condition)
    else raise ArgumentError, "unknown owner #{owner.inspect}, expected one of #{OWNERS.join(', ')} or nil"
    end
  end

  # [Onda 5 / fatia 2] Recorte ao vivo, para o Monitoramento (Todos/Humanos/IA).
  #
  # Isto NAO e o classificador acima, e de proposito nao reusa o predicado por
  # RESOLUCAO: a tela de Monitoramento mostra conversas ainda abertas, que nao
  # tem `conversation_resolved` nenhum para classificar. Aqui a pergunta e
  # outra -- "quem esta conduzindo agora" --, respondida por ESTADO ATUAL, e
  # so vale para a foto ao vivo. Ela pode mudar a qualquer segundo (um agente
  # se atribui, um handoff acontece) e isso e o esperado; o classificador por
  # resolucao acima e o unico valido para serie historica, porque aquele nao
  # pode ser reescrito pelo estado de agora.
  #
  # bot   = so a IA esta conduzindo: caixa com bot ativo, sem agente atribuido
  #         e sem handoff registrado.
  # human = todo o resto (houve handoff, ha agente atribuido, ou a caixa nao
  #         tem bot).
  def bot_conducted(scope)
    scope.where(inbox_id: bot_inbox_ids)
         .where(assignee_id: nil)
         .where.not(id: handed_off_conversation_ids)
  end

  def human_conducted(scope)
    scope.where.not(id: bot_conducted(scope).select(:id))
  end

  # A mesma condicao como booleano cru, para quem precisa dela dentro de uma
  # agregacao -- `COUNT(*) FILTER (WHERE ...)` numa passada so -- em vez de dois
  # escopos e duas varreduras.
  def bot_resolution_condition
    Arel.sql(<<~SQL.squish)
      (reporting_events.user_id IS NULL
       AND EXISTS (
         SELECT 1 FROM reporting_events twin
         WHERE twin.conversation_id = reporting_events.conversation_id
           AND twin.name = 'conversation_bot_resolved'
           AND twin.event_end_time = reporting_events.event_end_time)
       AND NOT EXISTS (
         SELECT 1 FROM reporting_events human_evidence
         WHERE human_evidence.conversation_id = reporting_events.conversation_id
           AND human_evidence.name IN (#{quoted_human_evidence_events})
           AND human_evidence.event_end_time <= reporting_events.event_end_time))
    SQL
  end

  private

  def quoted_human_evidence_events
    HUMAN_EVIDENCE_EVENTS.map { |name| ActiveRecord::Base.connection.quote(name) }.join(', ')
  end

  def bot_inbox_ids
    @bot_inbox_ids ||= @account.agent_bot_inboxes.pluck(:inbox_id)
  end

  # Subquery (nao array Ruby): numa conta com muito handoff de bot, um `pluck`
  # aqui vira um `NOT IN` gigante e pode estourar o statement_timeout -- e o
  # que ja aconteceu em producao (docs-fork/plano-port-coraxy.md).
  def handed_off_conversation_ids
    @handed_off_conversation_ids ||= @account.reporting_events
                                             .where(name: 'conversation_bot_handoff')
                                             .select(:conversation_id)
  end
end
