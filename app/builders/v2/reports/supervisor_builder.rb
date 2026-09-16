# [Onda 5 / fatia 2] Monitoramento em tempo real: KPIs do topo, fila por
# equipe, tabela de conversas ativas, painel de agentes e alertas de espera.
#
# Diferente dos outros builders da onda, este nao tem janela de tempo -- e uma
# foto do agora, por isso o controller pula o `validate_time_window` para esta
# acao.
#
# O recorte Todos/Humanos/IA usa o predicado por ESTADO ATUAL do
# Reports::ConversationOwnershipFinder (`#bot_conducted`/`#human_conducted`),
# que e diferente do classificador por RESOLUCAO que as fatias 0 e 1 usam:
# aqui a conversa ainda esta aberta, entao nao ha `conversation_resolved` para
# classificar. O predicado mora no finder porque o filtro e transversal as
# fatias 3, 4 e 5 -- ver o comentario dele antes de copiar a logica de novo.
class V2::Reports::SupervisorBuilder
  # Espera acima deste limite (minutos) gera alerta.
  ALERT_WAIT_MINUTES = 15
  ALERT_SCAN_LIMIT = 200
  # Conversas mais antigas que isso sao ignoradas no calculo de espera, para
  # que casos esquecidos nao distorcam a metrica.
  MAX_WAIT_WINDOW_DAYS = 30

  def initialize(account, params = {})
    @account = account
    @params = params
  end

  def metrics
    {
      kpis: kpis,
      queue_by_team: queue_by_team,
      conversations: conversations,
      agents: agents,
      alerts: alerts
    }
  end

  private

  # ---------- Conversas em tempo real ----------

  # Filtro de status, paginacao e serializacao ficam na tabela: aqui so entra
  # o escopo ja resolvido (Todos/Humanos/IA e equipe ja aplicados).
  def conversations
    V2::Reports::SupervisorConversationsTable.new(live_conversations, @params).to_h
  end

  # Base: conversas ativas, ordenadas pelas que esperam ha mais tempo.
  def live_conversations
    @live_conversations ||= apply_agent_type(active_scope)
                            .order(waiting_since: :asc, last_activity_at: :desc)
  end

  # ---------- Agentes ----------

  def agents
    load_by_agent = in_progress_scope.group(:assignee_id).count
    rows = @account.users.order(:name).map do |user|
      {
        id: user.id,
        name: user.name,
        status: agent_status(user.id),
        load: load_by_agent[user.id].to_i
      }
    end

    rows.sort_by { |a| [a[:status] == 'offline' ? 1 : 0, -a[:load], a[:name]] }
  end

  def agent_status(user_id)
    available_users[user_id.to_s] || 'offline'
  end

  # Presenca vem do Redis, nao do banco: uma leitura so por requisicao.
  def available_users
    @available_users ||= (::OnlineStatusTracker.get_available_users(@account.id) || {})
                         .transform_keys(&:to_s)
  end

  # ---------- Alertas ----------

  # Independente da paginacao: sempre as conversas sem agente esperando ha
  # mais tempo.
  def alerts
    live_conversations
      .where(assignee_id: nil)
      .where('conversations.created_at <= ?', ALERT_WAIT_MINUTES.minutes.ago)
      .includes(:contact, :inbox)
      .reorder(created_at: :asc)
      .limit(ALERT_SCAN_LIMIT)
      .map do |conv|
        {
          id: conv.display_id,
          contact_name: conv.contact&.name,
          minutes: minutes_since(conv.created_at),
          inbox_name: conv.inbox&.name,
          labels: conv.cached_label_list.to_s.split(',').map(&:strip).reject(&:blank?)
        }
      end
  end

  def minutes_since(timestamp)
    return 0 if timestamp.blank?

    ((Time.current - timestamp) / 60).round
  end

  # ---------- KPIs do topo ----------

  def kpis
    {
      in_progress: in_progress_count,
      in_queue: in_queue_scope.count,
      # Fila sem o recorte Humanos/IA: no modo IA a fila filtrada apenas
      # repetiria "em atendimento", entao a tela mostra a fila real (quem esta
      # esperando um humano assumir).
      in_queue_unfiltered: active_scope.where(assignee_id: nil).count,
      longest_wait_minutes: longest_wait_minutes,
      longest_wait_window_days: MAX_WAIT_WINDOW_DAYS,
      stale_in_queue: stale_in_queue_count,
      agents_online: online_user_ids.size,
      agents_total: account_user_ids.size,
      avg_load: avg_load
    }
  end

  # Conversas ativas em atendimento.
  # Com filtro de IA, "em atendimento" passa a significar todas as conversas
  # ativas conduzidas pelo bot -- nao existe "fila esperando agente" nesse
  # recorte, ja que a IA ja esta atendendo. Por isso usamos open + pending, o
  # mesmo conjunto da tabela de conversas em tempo real.
  def in_progress_scope
    @in_progress_scope ||= if agent_type == 'bot'
                             ownership_finder.bot_conducted(active_scope)
                           else
                             base_scope.open.where.not(assignee_id: nil)
                           end
  end

  # `kpis` e `avg_load` fazem a mesma pergunta; sem isto era a mesma contagem
  # disparada duas vezes.
  def in_progress_count
    @in_progress_count ||= in_progress_scope.count
  end

  # Conversas ativas ainda sem agente.
  # Usa open + pending para bater com a contagem "Na fila" da tabela.
  def in_queue_scope
    @in_queue_scope ||= apply_agent_type(active_scope.where(assignee_id: nil))
  end

  # Conversas consideradas ativas na tela (mesmo criterio da tabela).
  def active_scope
    base_scope.where(status: %i[open pending])
  end

  # Fila dentro da janela considerada para o calculo de espera.
  def recent_in_queue_scope
    in_queue_scope.where('conversations.created_at >= ?', MAX_WAIT_WINDOW_DAYS.days.ago)
  end

  # Maior tempo de espera (em minutos), ignorando conversas fora da janela.
  def longest_wait_minutes
    oldest = recent_in_queue_scope.minimum(:created_at)
    return 0 if oldest.blank?

    ((Time.current - oldest) / 60).round
  end

  # Quantas conversas da fila ficaram de fora do calculo por serem antigas.
  def stale_in_queue_count
    in_queue_scope.where('conversations.created_at < ?', MAX_WAIT_WINDOW_DAYS.days.ago).count
  end

  # Media de conversas ativas por agente online.
  def avg_load
    online = online_user_ids.size
    return 0.0 if online.zero?

    (in_progress_count.to_f / online).round(1)
  end

  # ---------- Fila por equipe ----------

  # So as equipes que `team_id` permite -- a conta inteira com filtro ativo
  # mostraria "0" pra equipe fora do filtro, igual a "sem fila agora".
  def queue_by_team
    rows = teams_scope.order(:name).map { |team| team_queue_row(team) }
    rows << unassigned_queue_row if unassigned_queue_row[:in_queue].positive? || unassigned_queue_row[:in_progress].positive?

    rows
  end

  def team_queue_row(team)
    {
      id: team.id,
      name: team.name,
      in_queue: in_queue_by_team[team.id].to_i,
      in_progress: in_progress_by_team[team.id].to_i,
      agents_online: online_agents_by_team[team.id].to_i
    }
  end

  # Conversas de time nenhum, so aparece na lista quando ha alguma.
  def unassigned_queue_row
    @unassigned_queue_row ||= {
      id: nil,
      name: nil,
      in_queue: in_queue_by_team[nil].to_i,
      in_progress: in_progress_by_team[nil].to_i,
      agents_online: 0
    }
  end

  def in_queue_by_team
    @in_queue_by_team ||= in_queue_scope.unscope(:order).group(:team_id).count
  end

  def in_progress_by_team
    @in_progress_by_team ||= in_progress_scope.unscope(:order).group(:team_id).count
  end

  # Uma query so para todas as equipes, nao uma por equipe dentro do
  # `.map` de `queue_by_team` -- achado pela revisao de backend: era o mesmo
  # N+1 que este builder existe para eliminar, so que por numero de equipes em
  # vez de por conversa.
  def online_agents_by_team
    @online_agents_by_team ||= TeamMember.joins(:team)
                                         .where(teams: { account_id: @account.id })
                                         .pluck(:team_id, :user_id)
                                         .group_by(&:first)
                                         .transform_values { |pairs| (pairs.map { |(_id, user_id)| user_id.to_s } & online_user_ids).size }
  end

  # ---------- Helpers ----------

  def base_scope
    @base_scope ||= @params[:team_id].present? ? @account.conversations.where(team_id: @params[:team_id]) : @account.conversations
  end

  def teams_scope
    @params[:team_id].present? ? @account.teams.where(id: @params[:team_id]) : @account.teams
  end

  def agent_type
    @agent_type ||= @params[:agent_type].to_s
  end

  def apply_agent_type(scope)
    case agent_type
    when 'bot' then ownership_finder.bot_conducted(scope)
    when 'human' then ownership_finder.human_conducted(scope)
    else scope
    end
  end

  def ownership_finder
    @ownership_finder ||= Reports::ConversationOwnershipFinder.new(@account)
  end

  def account_user_ids
    @account_user_ids ||= @account.users.pluck(:id).map(&:to_s)
  end

  # IDs (string) dos usuarios presentes e com status diferente de offline.
  def online_user_ids
    @online_user_ids ||= available_users
                         .reject { |_id, status| status.to_s == 'offline' }
                         .keys
  end
end
