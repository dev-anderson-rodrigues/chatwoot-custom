# [Onda 5 / fatia 3] Recebidos e Efetuados: quanto o cliente abriu (recebido)
# contra quanto a empresa abriu (efetuado), com evolucao diaria, origem do
# primeiro contato e quebra por equipe, caixa e atendente.
#
# "Efetuado" = a primeira mensagem nao-activity da conversa e outgoing/template
# (a empresa falou primeiro). "Recebido" = o resto (o cliente falou primeiro,
# ou a conversa nao tem mensagem nao-activity nenhuma).
#
# O recorte Todos/Humanos/IA delega para
# Reports::ConversationOwnershipFinder#bot_conducted/#human_conducted, o mesmo
# predicado por ESTADO ATUAL que a fatia 2 (Monitoramento) usa -- nao
# duplicado aqui. Ver o comentario do finder antes de copiar a logica de novo
# nas fatias 4 e 5.
class V2::Reports::OrigemBuilder
  # Mensagens outgoing e template: a empresa iniciou.
  OUTGOING_TYPES = %w[outgoing template].freeze

  def initialize(account, params = {})
    @account = account
    @params = params
  end

  def metrics
    {
      summary: summary,
      daily_evolution: daily_evolution,
      by_origin: by_origin,
      by_team: by_team,
      by_inbox: by_inbox,
      by_agent: by_agent
    }
  end

  def summary
    counts = efetuado_split_counts(base_scope)
    total = counts.values.sum
    efetuados = counts[true].to_i
    recebidos = total - efetuados

    {
      total: total,
      recebidos: recebidos,
      efetuados: efetuados,
      recebidos_pct: pct(recebidos, total),
      efetuados_pct: pct(efetuados, total)
    }
  end

  def daily_evolution
    rows = base_scope
           .joins(first_message_join_sql)
           .group(Arel.sql('DATE(conversations.created_at)'), efetuado_predicate_sql)
           .count

    by_date = rows.each_with_object({}) do |((date, efetuado), count), acc|
      acc[date] ||= { recebidos: 0, efetuados: 0 }
      acc[date][efetuado ? :efetuados : :recebidos] += count
    end

    by_date.map { |date, day| { date: date.to_s, **day } }.sort_by { |row| row[:date] }
  end

  # Origem de cada atendimento efetuado: campanha, bot, template ou atendente.
  # Chave estavel, nao texto pronto -- quem traduz para o usuario e a tela.
  def by_origin
    rows = base_scope
           .merge(efetuado_scope)
           .pluck(Arel.sql(origin_case_sql))
           .tally

    total = rows.values.sum.to_f
    return [] if total.zero?

    origins = rows.map do |key, count|
      {
        key: key,
        kind: AUTOMATION_ORIGINS.include?(key) ? 'automation' : 'human',
        count: count,
        pct: (count / total * 100).round(1)
      }
    end

    origins.sort_by { |row| -row[:count] }
  end

  # `name` sai nulo quando nao ha equipe -- e a tela que decide o rotulo
  # traduzido de "sem equipe" (mesmo padrao do `unassigned_queue_row` da
  # fatia 2), nao o backend gerando texto de UI.
  def by_team
    breakdown('LEFT JOIN teams ON teams.id = conversations.team_id', 'teams.id', 'teams.name')
  end

  def by_inbox
    breakdown('JOIN inboxes ON inboxes.id = conversations.inbox_id', 'inboxes.id', 'inboxes.name')
  end

  # `name` sai nulo quando nao ha atendente atribuido -- mesmo raciocinio do
  # `by_team` acima.
  def by_agent
    breakdown('LEFT JOIN users ON users.id = conversations.assignee_id', 'users.id', 'users.name')
  end

  private

  AUTOMATION_ORIGINS = %w[campaign bot].freeze

  # Metodo, nao constante congelada no load da classe: le
  # `Message.message_types['template']` em vez do numero magico 3, para nao
  # quebrar em silencio se a ordem do enum mudar um dia.
  def origin_case_sql
    <<~SQL.squish
      CASE
        WHEN fm.additional_attributes -> 'campaign_id' IS NOT NULL THEN 'campaign'
        WHEN fm.sender_type = 'AgentBot' THEN 'bot'
        WHEN fm.message_type = #{Message.message_types['template']} THEN 'template'
        WHEN fm.sender_type = 'User' THEN 'agent_direct'
        ELSE 'other'
      END
    SQL
  end

  def pct(part, total)
    return 0 unless total.positive?

    (part.to_f / total * 100).round(1)
  end

  def base_scope
    @base_scope ||= begin
      scope = @account.conversations.where(created_at: time_range)
      scope = scope.where(team_id: @params[:team_id]) if @params[:team_id].present?
      apply_agent_type(scope)
    end
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

  # Subquery (nao array Ruby, nao JOIN direto): a primeira mensagem nao-activity
  # de cada conversa. Escopada por account_id -- sem isso o DISTINCT ON varre e
  # ordena a tabela `messages` inteira (todas as contas), o que ja estourou o
  # statement_timeout em producao (correcao de agosto, docs-fork/plano-port-coraxy.md).
  def first_message_table
    <<~SQL.squish
      (
        SELECT DISTINCT ON (conversation_id)
          conversation_id, message_type, sender_type, additional_attributes
        FROM messages
        WHERE account_id = #{@account.id.to_i} AND message_type <> #{Message.message_types['activity']}
        ORDER BY conversation_id, created_at, id
      )
    SQL
  end

  # Conversas iniciadas pela empresa. `Conversation` (nao `base_scope`): o join
  # com a subquery de mensagens e por conta, e quem filtra por periodo/equipe/
  # agent_type e sempre `base_scope.merge(...)`, nunca este escopo sozinho.
  def efetuado_scope
    Conversation
      .joins("JOIN #{first_message_table} fm ON fm.conversation_id = conversations.id")
      .where(fm: { message_type: message_type_values(OUTGOING_TYPES) })
  end

  def message_type_values(names)
    names.map { |name| Message.message_types[name] }
  end

  # LEFT JOIN (nao INNER): uma conversa sem nenhuma mensagem nao-activity
  # ainda precisa aparecer na contagem total, como "recebido" (mesmo criterio
  # do `efetuado_scope`, que so acha conversas COM primeira mensagem).
  # DISTINCT ON garante no maximo uma linha de `fm` por conversa -- o LEFT
  # JOIN nunca duplica linha de `conversations`.
  def first_message_join_sql
    "LEFT JOIN #{first_message_table} fm ON fm.conversation_id = conversations.id"
  end

  # Agrupar pelo predicado (nao repeti-lo em FILTERs separados) e o mesmo
  # motivo, medido, do `OwnershipSummaryBuilder#resolutions_by_owner`: uma
  # unica consulta, uma raspada nas linhas, sem a janela de tempo entre duas
  # consultas separadas que deixava `efetuados` passar `total` (contagem
  # negativa) se uma conversa fosse criada entre as duas.
  # COALESCE fecha o `NULL` de conversa sem `fm` como "nao efetuado".
  def efetuado_predicate_sql
    Arel.sql("COALESCE(fm.message_type IN (#{message_type_values(OUTGOING_TYPES).join(',')}), false)")
  end

  def efetuado_split_counts(scope)
    scope.joins(first_message_join_sql).group(efetuado_predicate_sql).count
  end

  def breakdown(join_sql, id_expression, name_expression)
    rows = base_scope
           .joins(join_sql)
           .joins(first_message_join_sql)
           .group(Arel.sql(id_expression), Arel.sql(name_expression), efetuado_predicate_sql)
           .count

    breakdown_rows = group_breakdown_rows(rows)
    breakdown_rows.sort_by { |row| -row[:total] }
  end

  def group_breakdown_rows(rows)
    totals = Hash.new { |hash, key| hash[key] = { total: 0, efetuados: 0 } }

    rows.each do |(id, name, efetuado), count|
      row = totals[[id, name]]
      row[:total] += count
      row[:efetuados] += count if efetuado
    end

    totals.map do |(id, name), row|
      { id: id, name: name, total: row[:total], efetuados: row[:efetuados], recebidos: row[:total] - row[:efetuados] }
    end
  end

  # A janela chega validada pelo controller (422 sem as duas pontas), como as
  # outras acoes desta onda. O parse aqui e estrito por proposito.
  def time_range
    @time_range ||= epoch_param(:since)..epoch_param(:until)
  end

  def epoch_param(key)
    Time.zone.at(Integer(@params.fetch(key).to_s, 10))
  end
end
