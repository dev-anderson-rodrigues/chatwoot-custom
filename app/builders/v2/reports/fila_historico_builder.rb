# [Onda 5 / fatia 4] Fila -- Historico: tempo de espera, volume e abandono ao
# longo do tempo, com KPIs comparados ao periodo anterior de mesma duracao.
#
# Definicoes:
#   TME       = tempo ate a primeira resposta do agente (evento first_response).
#   Abandono  = resolucao classificada como HUMANA (Reports::ConversationOwnershipFinder,
#               fato historico -- ver o comentario do finder) em que nenhum
#               agente respondeu antes de resolver. Resolucao do robo sem
#               first_response NAO e abandono: e o fluxo automatizado
#               funcionando, nao uma falha de atendimento.
#   Carga     = participacao do agente no total de atendimentos do periodo.
#
# O recorte Todos/Humanos/IA delega para
# Reports::ConversationOwnershipFinder#bot_conducted/#human_conducted, o mesmo
# predicado por ESTADO ATUAL que as fatias 2 e 3 usam -- nao duplicado aqui.
class V2::Reports::FilaHistoricoBuilder
  def initialize(account, params = {})
    @account = account
    @params = params
  end

  def metrics
    {
      kpis: { current: kpis_for(current_range), previous: kpis_for(previous_range) },
      daily_evolution: daily_evolution,
      by_team: by_team,
      by_agent: by_agent,
      capacity_vs_demand: capacity_vs_demand
    }
  end

  # ---------- KPIs ----------

  def kpis_for(range)
    total = conversations_in(range).count
    avg_wait, max_wait = first_response_events(range).pick(Arel.sql('AVG(value), MAX(value)'))
    abandoned = abandoned_count(range)

    {
      total: total,
      avg_wait_seconds: avg_wait.to_f.round,
      max_wait_seconds: max_wait.to_f.round,
      abandon_rate: total.positive? ? (abandoned.to_f / total * 100).round(1) : 0.0,
      abandoned_count: abandoned
    }
  end

  # ---------- Evolucao diaria ----------

  # As duas series agrupam pela MESMA expressao de data
  # (`conversations.created_at`, nunca `reporting_events.created_at`) -- e a
  # correcao do bug de eixo misto da fonte: volume contava conversa CRIADA no
  # periodo, TME contava resposta OCORRIDA no periodo, dois conjuntos
  # diferentes de conversa no mesmo grafico.
  def daily_evolution
    volume = conversations_in(current_range).group(Arel.sql('DATE(conversations.created_at)')).count

    waits = first_response_events(current_range)
            .joins(:conversation)
            .group(Arel.sql('DATE(conversations.created_at)'))
            .average(:value)

    keys = (volume.keys + waits.keys).uniq.sort

    keys.map do |date|
      {
        date: date.to_s,
        volume: volume[date].to_i,
        avg_wait_minutes: (waits[date].to_f / 60).round(1)
      }
    end
  end

  # ---------- Por equipe ----------

  # Enumera TODAS as equipes da conta (nao so as que aparecem no GROUP BY de
  # conversas do periodo) -- mesmo padrao de `supervisor_builder#queue_by_team`
  # nesta onda: uma equipe configurada e ociosa no periodo e informacao de
  # gestao (sem demanda), nao deve desaparecer da tela.
  # Memoizado: `capacity_vs_demand` chama `by_team` de novo por cima, e sem
  # cache isso dobraria as 4 consultas a cada `metrics`.
  def by_team
    @by_team ||= begin
      totals = conversations_in(current_range).group(:team_id).count
      wait_by_team = wait_stats_by('conversations.team_id')
      abandoned_by_team = abandoned_scope(current_range)
                          .joins(:conversation)
                          .group('conversations.team_id')
                          .distinct.count(:conversation_id)

      rows = @account.teams.order(:name).map do |team|
        team_row(team.id, team.name, totals, wait_by_team, abandoned_by_team)
      end
      rows << team_row(nil, nil, totals, wait_by_team, abandoned_by_team) if totals.key?(nil)

      rows.sort_by { |row| -row[:total] }
    end
  end

  # ---------- Por agente ----------

  # So agentes com conversa atribuida no periodo aparecem -- nem todo usuario
  # da conta e agente de fila, diferente de equipe (que e sempre configuracao
  # relevante).
  def by_agent
    totals = conversations_in(current_range).where.not(assignee_id: nil).group(:assignee_id).count
    grand_total = totals.values.sum
    wait_by_agent = wait_stats_by('conversations.assignee_id')
    user_names = @account.users.pluck(:id, :name).to_h

    rows = totals.map do |user_id, total|
      avg_wait, max_wait = wait_by_agent[user_id] || [0, 0]
      {
        id: user_id,
        name: user_names[user_id],
        total: total,
        avg_wait_seconds: avg_wait,
        max_wait_seconds: max_wait,
        load_pct: grand_total.positive? ? (total.to_f / grand_total * 100).round(1) : 0.0
      }
    end
    rows.sort_by { |row| -row[:total] }
  end

  # ---------- Capacidade vs demanda ----------
  #
  # Sem capacidade configurada por equipe, usamos o numero de agentes do time
  # multiplicado por uma referencia de atendimentos por agente no periodo.
  def capacity_vs_demand
    reference = reference_per_agent

    rows = by_team.map do |team|
      agents = team[:id] ? team_member_counts[team[:id]].to_i : 0
      capacity = agents * reference

      {
        id: team[:id],
        name: team[:name],
        demand: team[:total],
        agents: agents,
        capacity: capacity,
        usage_pct: capacity.positive? ? [(team[:total].to_f / capacity * 100).round, 100].min : 100
      }
    end
    rows.sort_by { |row| -row[:usage_pct] }
  end

  private

  def team_row(id, name, totals, wait_by_team, abandoned_by_team)
    avg_wait, max_wait = wait_by_team[id] || [0, 0]
    {
      id: id,
      name: name,
      total: totals[id].to_i,
      avg_wait_seconds: avg_wait,
      max_wait_seconds: max_wait,
      abandoned: abandoned_by_team[id].to_i
    }
  end

  # AVG e MAX saem de uma unica query (nao duas chamadas separadas) -- mesma
  # tabela, mesmo filtro, sem razao para rodar duas vezes.
  def wait_stats_by(group_expression)
    first_response_events(current_range)
      .joins(:conversation)
      .group(Arel.sql(group_expression))
      .pluck(Arel.sql("#{group_expression}, AVG(reporting_events.value), MAX(reporting_events.value)"))
      .to_h { |id, avg, max| [id, [avg.to_f.round, max.to_f.round]] }
  end

  # Media de atendimentos por agente no periodo, usada como referencia de capacidade.
  def reference_per_agent
    total_agents = @account.users.count
    return 1 if total_agents.zero?

    [(conversations_in(current_range).count.to_f / total_agents).round, 1].max
  end

  def team_member_counts
    @team_member_counts ||= @account.teams.left_joins(:team_members)
                                    .group(:id)
                                    .count('team_members.id')
  end

  # ---------- Escopos ----------

  def conversations_in(range)
    scope = @account.conversations.where(created_at: range)
    scope = scope.where(team_id: @params[:team_id]) if @params[:team_id].present?
    apply_agent_type(scope)
  end

  # Sempre intersecta `conversations_in(range)` por subquery, sem excecao para
  # "Todos" -- correcao do bug de eixo misto: a fonte so restringia por
  # conversa quando o recorte era bot/human, entao "Todos" misturava resposta
  # ocorrida no periodo com conversa criada fora dele.
  def first_response_events(range)
    @account.reporting_events
            .where(name: 'first_response')
            .where(conversation_id: conversations_in(range).select(:id))
  end

  # ---------- Recorte IA / Humano ----------

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

  # Resolucao humana (fato historico, nao `conversations.status` mutavel) sem
  # nenhum `first_response` antes dela -- ver o comentario do metodo no finder.
  def abandoned_scope(range)
    ownership_finder.resolutions('human')
                    .where(conversation_id: conversations_in(range).select(:id))
                    .where(ownership_finder.never_first_responded_condition)
  end

  # DISTINCT: uma conversa reaberta e resolvida duas vezes gera duas linhas de
  # conversation_resolved -- sem isso, abandono contaria a mesma conversa
  # duas vezes. Mesma tecnica de
  # OwnershipSummaryBuilder#other_metrics (COUNT DISTINCT conversation_id).
  def abandoned_count(range)
    abandoned_scope(range).distinct.count(:conversation_id)
  end

  # ---------- Periodos ----------

  def current_range
    @current_range ||= epoch_param(:since)..epoch_param(:until)
  end

  # Mesma duracao, imediatamente antes do periodo atual. Aberto no fim (`...`)
  # de proposito -- fechado nos dois lados contaria o instante exato da
  # fronteira duas vezes (mesma correcao de OwnershipSummaryBuilder#previous_range).
  def previous_range
    @previous_range ||= begin
      duration = current_range.end - current_range.begin
      (current_range.begin - duration)...current_range.begin
    end
  end

  def epoch_param(key)
    Time.zone.at(Integer(@params.fetch(key).to_s, 10))
  end
end
