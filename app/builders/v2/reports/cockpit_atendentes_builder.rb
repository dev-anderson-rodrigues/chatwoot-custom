# [Onda 5 / fatia 4] Cockpit de Atendentes: uma linha por agente com volume,
# tempos, CSAT, time e presenca, mais os KPIs do topo.
#
# Nao reusa o V2::Reports::AgentSummaryBuilder de proposito. Os dois leem os
# mesmos `reporting_events`, entao o numero nao diverge, mas o cockpit precisa de
# duas coisas que o outro nao faz: contar conversas encerradas no periodo
# (`date_field=resolved`, que e como a operacao olha o dia) e devolver presenca,
# time, CSAT e ranking. Adaptar o builder do upstream para isso mexeria num
# arquivo que o relatorio de agentes tambem usa, e todo sync com o upstream
# pagaria o conflito.
#
# Quando o rollup de relatorios for ligado (ver o TODO em
# Reports::DataSource.for), o AgentSummaryBuilder passa a ler a tabela agregada
# de graca e este builder fica para tras: e a hora de revisitar esta decisao.
class V2::Reports::CockpitAtendentesBuilder
  EVENT_NAMES = %w[conversation_resolved first_response reply_time].freeze

  # Agregacao condicional numa passada so, em vez de uma varredura por metrica.
  # E o padrao que o upstream ja usa em Reports::RawDataSource.
  EVENT_AGGREGATES = <<~SQL.squish
    user_id,
    COUNT(CASE WHEN name = 'conversation_resolved' THEN 1 END),
    AVG(CASE WHEN name = 'conversation_resolved' THEN value END),
    AVG(CASE WHEN name = 'first_response' THEN value END),
    AVG(CASE WHEN name = 'reply_time' THEN value END)
  SQL

  CSAT_AGGREGATES = 'assigned_agent_id, COUNT(*), SUM(rating)'.freeze

  def initialize(account, params = {})
    @account = account
    @params = params
  end

  def metrics
    rows = agent_rows

    { kpis: kpis(rows), agents: rows }
  end

  private

  # Os KPIs saem das linhas ja filtradas: com um time selecionado, o topo tem que
  # falar do time, nao da conta inteira.
  def kpis(rows)
    presence_kpis(rows).merge(volume_kpis(rows)).merge(csat_kpis(rows))
  end

  def presence_kpis(rows)
    {
      agents_total: rows.size,
      agents_online: rows.count { |row| row[:status] != 'offline' },
      agents_busy: rows.count { |row| row[:status] == 'busy' },
      agents_offline: rows.count { |row| row[:status] == 'offline' }
    }
  end

  def volume_kpis(rows)
    {
      conversations_total: rows.sum { |row| row[:conversations] },
      avg_handle_seconds: average_of(rows, :avg_handle_seconds, :conversations)
    }
  end

  # Ponderada pelas respostas, nao media das medias: um agente com uma resposta
  # nao pode pesar igual a um com cinquenta.
  def csat_kpis(rows)
    with_csat = rows.select { |row| row[:csat_responses].positive? }
    total_responses = with_csat.sum { |row| row[:csat_responses] }
    return { avg_csat: 0.0 } if total_responses.zero?

    weighted = with_csat.sum { |row| row[:csat].to_f * row[:csat_responses] }

    { avg_csat: (weighted / total_responses).round(1) }
  end

  # Media ponderada pelo volume, ignorando quem nao tem o dado: a media simples
  # deixaria um agente com uma conversa pesar igual a um com duzentas.
  def average_of(rows, field, weight_field)
    weighted = rows.reject { |row| row[field].to_f.zero? }
    total_weight = weighted.sum { |row| row[weight_field].to_i }
    return 0 if total_weight.zero?

    (weighted.sum { |row| row[field].to_f * row[weight_field].to_i } / total_weight).round
  end

  # Filtrar e ordenar em Ruby e proposital: o conjunto e o quadro de agentes da
  # conta (dezenas), e todo campo da linha vem de hash ja agregado no banco --
  # nao ha query por agente.
  def agent_rows
    rows = @account.users.map { |user| build_row(user) }
    rows = apply_filters(rows)
    rows.sort_by { |row| -row[:conversations] }
        .each_with_index { |row, index| row[:rank] = index + 1 }
  end

  def build_row(user)
    agent_identity(user).merge(agent_metrics(user.id))
  end

  def agent_identity(user)
    {
      id: user.id,
      name: user.name,
      email: user.email,
      team_name: team_by_user[user.id],
      status: agent_status(user.id)
    }
  end

  def agent_metrics(user_id)
    events = event_metrics_by_agent[user_id] || {}
    csat = csat_by_agent[user_id] || { count: 0, sum: 0 }

    {
      conversations: conversations_by_agent[user_id].to_i,
      resolutions_count: events[:resolutions].to_i,
      avg_handle_seconds: events[:handle].to_f.round,
      avg_first_response_seconds: events[:first_response].to_f.round,
      avg_reply_seconds: events[:reply].to_f.round,
      csat: average_csat(csat),
      csat_responses: csat[:count]
    }
  end

  # Sem resposta nao vira zero: zero seria uma nota, e "sem nota" e outra coisa.
  def average_csat(csat)
    return nil unless csat[:count].positive?

    (csat[:sum].to_f / csat[:count]).round(1)
  end

  def apply_filters(rows)
    rows = rows.select { |row| row[:status] == @params[:status] } if @params[:status].present?
    rows = filter_by_team(rows) if @params[:team_id].present?
    rows = filter_by_search(rows) if @params[:search].present?
    rows
  end

  def filter_by_team(rows)
    allowed = team_member_ids(@params[:team_id])
    rows.select { |row| allowed.include?(row[:id]) }
  end

  def filter_by_search(rows)
    term = @params[:search].to_s.downcase
    rows.select do |row|
      row[:name].to_s.downcase.include?(term) || row[:email].to_s.downcase.include?(term)
    end
  end

  # "Quantas entraram" e "quantas fechei" sao perguntas diferentes, e a operacao
  # olha as duas.
  def conversations_by_agent
    @conversations_by_agent ||= resolved_window? ? conversations_resolved_in_window : conversations_opened_in_window
  end

  def resolved_window?
    @params[:date_field].to_s == 'resolved'
  end

  def conversations_opened_in_window
    @account.conversations
            .where(created_at: time_range)
            .where.not(assignee_id: nil)
            .group(:assignee_id)
            .count
  end

  # Encerradas no periodo sai do evento de resolucao, nao de `updated_at`.
  # `updated_at` muda com qualquer edicao da conversa -- etiqueta, nota,
  # reabertura -- e contaria como "encerrada hoje" o que so foi tocado hoje. O
  # evento tambem cai num indice exato (account_id, name, created_at), enquanto
  # (status, updated_at) nao tem indice nenhum.
  #
  # Conta conversa distinta, nao evento: conversa reaberta e resolvida de novo na
  # mesma janela e uma so no volume do agente.
  def conversations_resolved_in_window
    @account.reporting_events
            .where(name: 'conversation_resolved', created_at: time_range)
            .joins(:conversation)
            .where.not(conversations: { assignee_id: nil })
            .group('conversations.assignee_id')
            .distinct
            .count('conversations.id')
  end

  # Resolucoes, tempo de atendimento, primeira resposta e tempo de resposta saem
  # da mesma query. `user_id` nulo e resolucao sem agente humano (bot ou
  # automacao) e nao entra em linha de atendente.
  def event_metrics_by_agent
    @event_metrics_by_agent ||= event_rows.to_h { |row| [row.first, event_row_metrics(row)] }
  end

  def event_rows
    @account.reporting_events
            .where(name: EVENT_NAMES, created_at: time_range)
            .where.not(user_id: nil)
            .group(:user_id)
            .pluck(Arel.sql(EVENT_AGGREGATES))
  end

  def event_row_metrics(row)
    _user_id, resolutions, handle, first_response, reply = row

    { resolutions: resolutions, handle: handle, first_response: first_response, reply: reply }
  end

  def csat_by_agent
    @csat_by_agent ||= @account.csat_survey_responses
                               .where(created_at: time_range)
                               .where.not(assigned_agent_id: nil)
                               .group(:assigned_agent_id)
                               .pluck(Arel.sql(CSAT_AGGREGATES))
                               .to_h { |agent_id, count, sum| [agent_id, { count: count, sum: sum.to_i }] }
  end

  # Um agente pode estar em mais de um time; exibimos o primeiro.
  def team_by_user
    @team_by_user ||= begin
      pairs = TeamMember.joins(:team).where(teams: { account_id: @account.id }).pluck(:user_id, 'teams.name')
      pairs.each_with_object({}) { |(user_id, name), acc| acc[user_id] ||= name }
    end
  end

  def team_member_ids(team_id)
    @team_member_ids ||= {}
    @team_member_ids[team_id] ||= TeamMember.joins(:team)
                                            .where(team_id: team_id, teams: { account_id: @account.id })
                                            .pluck(:user_id)
  end

  def agent_status(user_id)
    available_users[user_id.to_s] || 'offline'
  end

  # Presenca vem do Redis, nao do banco: uma leitura so por requisicao.
  def available_users
    @available_users ||= (::OnlineStatusTracker.get_available_users(@account.id) || {}).transform_keys(&:to_s)
  end

  # Janela explicita em vez do DateRangeHelper do repo: `range` de la devolve nil
  # quando since/until faltam, e aqui a ausencia de janela filtraria por nil e
  # zeraria o relatorio em silencio. A tela sempre manda as duas pontas.
  def time_range
    @time_range ||= Time.zone.at(@params[:since].to_i)..Time.zone.at(@params[:until].to_i)
  end
end
