# [Onda 5 / fatia 5] A populacao do relatorio de Motivos: conversas do periodo
# que carregam uma das etiquetas escolhidas, com os filtros da tela aplicados --
# e as resolucoes dessa mesma populacao.
#
# Separado do MotivosBuilder porque sao duas perguntas diferentes: aqui se
# decide QUAIS conversas entram no relatorio, la se decide o que se mede sobre
# elas. O builder so agrega; nenhum `where` de populacao mora nele.
#
# O ponto a nao perder de vista ao mexer aqui: `tagged_resolutions` e sempre
# derivado de `tagged_conversations`, nunca uma leitura solta de
# `reporting_events`. E o que mantem coerentes as duas granularidades que
# Motivos mistura -- volume por conversa, TMA e FCR por resolucao.
class Reports::TaggedConversationFinder
  def initialize(account, params = {})
    @account = account
    @params = params
  end

  def selected_labels
    @selected_labels ||= Array(@params[:labels]).map(&:to_s).reject(&:blank?).uniq
  end

  # Conversas do periodo que carregam alguma das etiquetas escolhidas.
  def tagged_conversations(range)
    conversations_in(range)
      .joins(tag_join_sql('conversations.id'))
      .where(tags: { name: selected_labels })
  end

  # Resolucoes da populacao, ja com a etiqueta disponivel para agrupar.
  #
  # Intersecta por conversa sempre (mesmo ancoramento de
  # FilaHistoricoBuilder#abandoned_scope) e, quando o usuario escolheu datar
  # pelo encerramento, tambem pela janela do evento -- sem isso uma conversa
  # encerrada dentro do periodo traria junto a resolucao anterior, de outro mes,
  # para dentro do TMA.
  def tagged_resolutions(range)
    scope = ownership_finder.resolutions
                            .where(conversation_id: conversations_in(range).select(:id))
                            .joins(tag_join_sql('reporting_events.conversation_id'))
                            .where(tags: { name: selected_labels })
    return scope unless resolved_date_field?

    scope.where(created_at: range)
  end

  # A populacao e as resolucoes dela numa LEITURA SO.
  #
  # Duas consultas separadas (volume numa, resolucao noutra) deixavam uma
  # janela entre elas: bastava um agente etiquetar uma conversa no meio do
  # caminho para ela entrar na contagem de resolvidas sem ter entrado no total,
  # e a linha saía com `resolved_count` maior que `total` -- percentual acima
  # de 100% na tela. Mesma classe do bug que a fatia 3 teve com `recebidos`
  # negativo. Com um LEFT JOIN, as duas metricas saem do mesmo snapshot e
  # `resolved_count <= total` vale por construcao.
  #
  # LEFT JOIN, nao INNER: conversa sem nenhuma resolucao ainda conta no volume
  # do motivo. O alias fica sendo `reporting_events` mesmo (nao renomeado)
  # porque os predicados do ConversationOwnershipFinder referenciam esse nome;
  # as subqueries dentro deles ja usam aliases proprios (twin, human_evidence,
  # other_resolution), entao nao ha ambiguidade.
  def tagged_conversations_with_resolutions(range)
    tagged_conversations(range).joins(<<~SQL.squish)
      LEFT JOIN reporting_events
        ON reporting_events.conversation_id = conversations.id
       AND reporting_events.name = 'conversation_resolved'
       #{resolved_window_clause(range)}
    SQL
  end

  def resolved_date_field?
    @params[:date_field].to_s == 'resolved'
  end

  private

  # Quando o corte e por encerramento, a resolucao tambem precisa ser do
  # periodo -- senao uma conversa encerrada dentro da janela arrastaria a
  # resolucao anterior, de outro mes, para dentro do TMA. Vai na condicao do
  # JOIN, nao no WHERE: no WHERE, o LEFT JOIN degeneraria em INNER e as
  # conversas sem resolucao sumiriam do volume.
  def resolved_window_clause(range)
    return '' unless resolved_date_field?

    upper = range.exclude_end? ? '<' : '<='
    ActiveRecord::Base.sanitize_sql_array(
      ["AND reporting_events.created_at >= ? AND reporting_events.created_at #{upper} ?", range.begin, range.end]
    )
  end

  def conversations_in(range)
    scope = @account.conversations
    scope = if resolved_date_field?
              scope.where(id: resolved_conversation_ids_in(range))
            else
              scope.where(created_at: range)
            end

    apply_filters(scope)
  end

  def apply_filters(scope)
    scope = scope.where(team_id: @params[:team_id]) if @params[:team_id].present?
    scope = scope.where(inbox_id: @params[:inbox_id]) if @params[:inbox_id].present?
    apply_agent_type(scope)
  end

  # "Encerradas no periodo" sai do evento, nao de `conversations.updated_at`.
  #
  # A fonte usava `status: :resolved, updated_at: range`, e a revisao de banco
  # da fatia 4 ja tinha derrubado exatamente esse criterio: `updated_at` muda
  # com qualquer edicao da conversa (etiqueta nova, nota, reabertura), entao
  # contava conversa encerrada meses antes que so foi tocada agora; e
  # `(status, updated_at)` nao tem indice, enquanto o evento cai em
  # `index_reporting_events_on_account_id_and_name_and_created_at`, que ja existe.
  def resolved_conversation_ids_in(range)
    @account.reporting_events
            .where(name: 'conversation_resolved', created_at: range)
            .select(:conversation_id)
  end

  # `tags` e uma tabela GLOBAL no acts_as_taggable -- nao tem account_id, e
  # `index_tags_on_name` e unico no nome inteiro, entao duas contas que usem a
  # etiqueta "Financeiro" compartilham a MESMA linha em `tags`. O isolamento
  # multi-tenant vem inteiro de `conversations`, por onde todo escopo daqui
  # comeca (`@account.conversations`). Quem reusar este join fora desse ponto de
  # partida precisa saber disso.
  def tag_join_sql(taggable_id_column)
    <<~SQL.squish
      JOIN taggings ON taggings.taggable_id = #{taggable_id_column}
                   AND taggings.taggable_type = 'Conversation'
                   AND taggings.context = 'labels'
      JOIN tags ON tags.id = taggings.tag_id
    SQL
  end

  def apply_agent_type(scope)
    case @params[:agent_type].to_s
    when 'bot' then ownership_finder.bot_conducted(scope)
    when 'human' then ownership_finder.human_conducted(scope)
    else scope
    end
  end

  def ownership_finder
    @ownership_finder ||= Reports::ConversationOwnershipFinder.new(@account)
  end
end
