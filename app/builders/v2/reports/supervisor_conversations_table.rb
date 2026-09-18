# [Onda 5 / fatia 2] Monta a secao `conversations` do Monitoramento a partir
# de um escopo ja resolvido (o filtro Todos/Humanos/IA e o de equipe ja foram
# aplicados por quem chama). Responsabilidade unica: filtro de status,
# paginacao e serializacao da linha da tabela -- mesmo padrao do
# V2::Reports::DrilldownRecordSerializer para separar "quem esta na foto" de
# "como a linha vira JSON".
class V2::Reports::SupervisorConversationsTable
  PER_PAGE = 25
  MAX_PER_PAGE = 100

  def initialize(live_conversations, params = {})
    @live_conversations = live_conversations
    @params = params
  end

  def to_h
    total = filtered_conversations.count

    {
      items: paginated_conversations.map { |conv| serialize(conv) },
      counts: status_counts,
      pagination: {
        page: page,
        per_page: per_page,
        total_count: total,
        total_pages: (total.to_f / per_page).ceil
      }
    }
  end

  private

  # Aplica o filtro de status vindo da tela.
  def filtered_conversations
    @filtered_conversations ||= case @params[:status_filter].to_s
                                when 'na_fila' then @live_conversations.where(assignee_id: nil)
                                when 'atendendo' then with_agent_open
                                when 'aguardando' then with_agent_pending
                                else @live_conversations
                                end
  end

  # atendendo = tem agente, esta aberta e ja respondeu.
  def with_agent_open
    @live_conversations.where.not(assignee_id: nil)
                       .where(status: :open)
                       .where.not(first_reply_created_at: nil)
  end

  # aguardando = tem agente mas esta pendente, ou ainda nao respondeu.
  def with_agent_pending
    with_agent = @live_conversations.where.not(assignee_id: nil)

    with_agent.where(status: :pending).or(with_agent.where(first_reply_created_at: nil))
  end

  def paginated_conversations
    filtered_conversations
      .includes(:contact, :inbox, :assignee)
      .offset((page - 1) * per_page)
      .limit(per_page)
  end

  # Contagem por status para os chips de filtro (sempre sobre o total, nao a
  # pagina).
  def status_counts
    with_agent = @live_conversations.where.not(assignee_id: nil)

    na_fila = @live_conversations.where(assignee_id: nil).count
    aguardando = with_agent.where(status: :pending)
                           .or(with_agent.where(first_reply_created_at: nil))
                           .count
    atendendo = with_agent.where(status: :open)
                          .where.not(first_reply_created_at: nil)
                          .count

    {
      all: na_fila + aguardando + atendendo,
      na_fila: na_fila,
      atendendo: atendendo,
      aguardando: aguardando
    }
  end

  def page
    [@params[:page].to_i, 1].max
  end

  def per_page
    requested = @params[:per_page].to_i
    return PER_PAGE if requested <= 0

    [requested, MAX_PER_PAGE].min
  end

  # `contact_name` sem fallback em portugues: quem decide o texto de "sem
  # nome" e a tela (mesmo padrao do CsatContactCell, que renderiza "—" para
  # contato vazio), nao o builder.
  def serialize(conv)
    {
      id: conv.display_id,
      contact_name: conv.contact&.name,
      contact_phone: conv.contact&.phone_number,
      agent_name: conv.assignee&.name,
      labels: labels_for(conv),
      priority: conv.priority,
      duration_minutes: minutes_since(conv.created_at),
      last_message_minutes: minutes_since(conv.last_activity_at),
      status: conversation_status(conv)
    }.merge(inbox_attributes(conv))
  end

  def inbox_attributes(conv)
    { inbox_name: conv.inbox&.name, channel_type: conv.inbox&.channel_type }
  end

  def labels_for(conv)
    conv.cached_label_list.to_s.split(',').map(&:strip).reject(&:blank?)
  end

  # na_fila = sem agente | atendendo = com agente e respondida | aguardando = pendente/sem resposta
  def conversation_status(conv)
    return 'na_fila' if conv.assignee_id.blank?
    return 'aguardando' if conv.status == 'pending' || conv.first_reply_created_at.blank?

    'atendendo'
  end

  def minutes_since(timestamp)
    return 0 if timestamp.blank?

    ((Time.current - timestamp) / 60).round
  end
end
