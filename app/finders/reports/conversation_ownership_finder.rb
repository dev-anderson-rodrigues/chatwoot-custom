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
         .where(never_handed_off_condition)
  end

  # Ao contrario de `bot_conducted`, esta nao tem trava de conta propria --
  # `bot_inbox_ids`/`handed_off_conversation_ids` sao de `@account`, mas a
  # negacao herda o multi-tenant so do `scope` que o chamador passar. Todo
  # chamador de hoje comeca de `@account.conversations`; quem reusar isto
  # (fatias 3 a 5 tambem vao precisar do recorte) precisa continuar assim.
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

  # [Onda 5 / fatia 4] Abandono da fila: nenhum agente respondeu antes desta
  # resolucao. Diferente de `bot_resolution_condition` (que decide quem
  # resolveu), este predicado so faz sentido dentro de `resolutions('human')`
  # -- uma resolucao do robo sem `first_response` nao e abandono, e sucesso do
  # fluxo automatizado. `NOT EXISTS` correlacionado, mesmo indice que as
  # subqueries "twin"/`human_evidence` acima ja usam
  # (`index_reporting_events_on_conversation_name_end_time`).
  #
  # `event_end_time IS NOT NULL` explicito: sem isso, uma resolucao com
  # `event_end_time` nulo (dado legado -- o listener atual sempre grava um
  # valor real) faz `fr.event_end_time <= NULL` avaliar UNKNOWN para toda
  # candidata, e o NOT EXISTS vira verdadeiro por vacuidade -- contando
  # abandono mesmo quando houve first_response real antes. Mesmo cuidado que
  # `bot_resolution_condition` ja tem com esse dado ambiguo, so que do lado
  # conservador oposto (aqui, nao provar a ordem exclui do abandono em vez de
  # incluir).
  def never_first_responded_condition
    Arel.sql(<<~SQL.squish)
      reporting_events.event_end_time IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM reporting_events fr
        WHERE fr.conversation_id = reporting_events.conversation_id
          AND fr.name = 'first_response'
          AND fr.event_end_time <= reporting_events.event_end_time)
    SQL
  end

  # [Onda 5 / fatia 5] Houve transferencia do robo para humano nesta conversa.
  #
  # NAO e classificacao de dono, e de proposito: uma conversa transferida pode
  # voltar e ser resolvida pelo robo, e continua tendo havido transferencia. Por
  # isso Motivos a usa como metrica propria ("quanto o robo passou adiante"), ao
  # lado da participacao do robo, que essa sim sai de `bot_resolution_condition`.
  #
  # Alias proprio (`handoff`), diferente do `never_handed_off_condition` abaixo,
  # que referencia `reporting_events` sem alias. Aquele so pode ser usado sobre
  # um escopo de `conversations`; este entra dentro de um FILTER de agregacao
  # sobre `reporting_events`, onde o nome sem alias seria ambiguo.
  def handed_off_condition
    Arel.sql(<<~SQL.squish)
      EXISTS (
        SELECT 1 FROM reporting_events handoff
        WHERE handoff.conversation_id = conversations.id
          AND handoff.name = 'conversation_bot_handoff')
    SQL
  end

  # [Onda 5 / fatia 5] Esta conversa foi resolvida uma unica vez em todo o seu
  # historico -- nunca reaberta e resolvida de novo (FCR).
  #
  # Correlacionado por `conversation_id` e sem recorte de janela de proposito: a
  # fonte agrupava por conversa com `HAVING COUNT(*) = 1` DENTRO do periodo, o
  # que contava como "primeira resolucao" uma conversa resolvida em janeiro,
  # reaberta, e resolvida de novo em fevereiro -- olhando so fevereiro ela
  # parecia resolvida de primeira. Reabertura e fato do historico da conversa,
  # nao do recorte que se esta olhando.
  def single_resolution_condition
    Arel.sql(<<~SQL.squish)
      NOT EXISTS (
        SELECT 1 FROM reporting_events other_resolution
        WHERE other_resolution.conversation_id = reporting_events.conversation_id
          AND other_resolution.name = 'conversation_resolved'
          AND other_resolution.id <> reporting_events.id)
    SQL
  end

  private

  def quoted_human_evidence_events
    HUMAN_EVIDENCE_EVENTS.map { |name| ActiveRecord::Base.connection.quote(name) }.join(', ')
  end

  def bot_inbox_ids
    @bot_inbox_ids ||= @account.agent_bot_inboxes.pluck(:inbox_id)
  end

  # `NOT EXISTS` correlacionado, nao `NOT IN (subquery)`. A subquery de
  # `NOT IN` nao e correlacionada -- o Postgres precisa materializar TODO o
  # historico de `conversation_bot_handoff` da conta antes de poder negar
  # qualquer linha (medido pela revisao de banco: 271ms lendo 100 mil linhas
  # via heap fetch, numa conta com handoff antigo, e repetido 3 a 10 vezes por
  # requisicao porque `kpis`/`queue_by_team`/a tabela chamam este predicado
  # varias vezes). O `NOT IN` gigante que o comentario antigo citava (estourou
  # `statement_timeout` em producao) era de um `pluck` em array Ruby, mas o
  # substituto por subquery ActiveRecord tinha o mesmo problema de fundo, so
  # que dentro do banco em vez de na aplicacao.
  #
  # `NOT EXISTS` correlacionado por `conversation_id` usa o indice que ja
  # existe, `index_reporting_events_on_conversation_name_end_time
  # (conversation_id, name, event_end_time)`, como um lookup por candidata --
  # dezenas de conversas ativas, nao centenas de milhares de linhas
  # historicas. So correlaciona por `conversation_id`: nao precisa repetir
  # `account_id` aqui porque so pode combinar com a linha de `conversations`
  # que tem o mesmo id, e id e unico entre contas -- mesmo raciocinio que
  # `bot_resolution_condition` ja usa nas subqueries "twin"/`human_evidence`
  # acima.
  def never_handed_off_condition
    Arel.sql(<<~SQL.squish)
      NOT EXISTS (
        SELECT 1 FROM reporting_events
        WHERE reporting_events.conversation_id = conversations.id
          AND reporting_events.name = 'conversation_bot_handoff')
    SQL
  end
end
