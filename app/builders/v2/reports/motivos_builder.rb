# [Onda 5 / fatia 5] Motivos: volume, tempo e resolucao por etiqueta de contato.
#
# Definicoes:
#   Motivo = etiqueta que o usuario escolheu como motivo de contato. A escolha e
#            obrigatoria: sem ela nao ha relatorio (ver `metrics`).
#   TMA    = tempo medio ate a resolucao (valor do evento conversation_resolved).
#   FCR    = conversa resolvida uma unica vez em todo o seu historico, isto e,
#            nunca reaberta e resolvida de novo.
#
# Esta e a unica fatia da onda que mistura as duas granularidades: volume e
# tendencia sao POR CONVERSA, enquanto TMA, FCR e participacao do robo sao POR
# RESOLUCAO. As duas nao brigam porque `Reports::TaggedConversationFinder`
# deriva as resolucoes da mesma populacao de conversas -- a populacao manda, o
# evento so informa sobre ela. E a razao de esta fatia ter ficado por ultimo.
#
# Quem decide QUAIS conversas entram e o finder; este arquivo so agrega e
# apresenta. O recorte Todos/Humanos/IA delega para
# Reports::ConversationOwnershipFinder atraves dele, como nas fatias 2, 3 e 4.
class V2::Reports::MotivosBuilder
  # Quantos motivos entram no grafico de evolucao semanal. Mais que isso vira
  # espaguete de linhas na tela, e o grafico existe para comparar os campeoes.
  TOP_TREND_LIMIT = 3

  EMPTY_METRICS = {
    kpis: { reasons_count: 0, conversations_total: 0, top_reason: nil, slowest_reason: nil, avg_fcr: 0.0 },
    reasons: [],
    weekly_evolution: { labels: [], series: [] }
  }.freeze

  def initialize(account, params = {})
    @account = account
    @params = params
  end

  # Sem etiqueta escolhida nao ha relatorio, e nenhuma consulta e feita.
  #
  # A decisao de produto e que motivo e uma escolha explicita: a conta usa
  # etiqueta para muita coisa que nao e motivo de contato (prioridade, canal,
  # campanha), e somar tudo produziria um "top motivos" que nao responde a
  # pergunta da tela. A tela nem dispara a busca sem selecao -- esta guarda e
  # para a chamada direta na API, onde a alternativa seria varrer as conversas
  # da conta inteira para devolver um numero sem significado.
  def metrics
    return EMPTY_METRICS if finder.selected_labels.empty?

    rows = reason_rows

    {
      kpis: kpis(rows),
      reasons: rows,
      # So motivos com ocorrencia: uma serie reta em zero nao diz nada e ainda
      # ocupa uma cor da legenda.
      weekly_evolution: weekly_evolution(rows.select { |row| row[:total].positive? }.first(TOP_TREND_LIMIT))
    }
  end

  private

  # ---------- KPIs ----------
  #
  # Calculados em Ruby sobre as linhas ja agregadas no banco: o conjunto e a
  # lista de motivos escolhidos (dezenas, nao milhares), e toda parcela ja veio
  # somada. Mesmo criterio do CockpitAtendentesBuilder para o quadro de agentes.
  # `rows` tambem carrega os motivos que zeraram no periodo (ver `reason_rows`),
  # e nenhum KPI pode eleger um deles: "motivo mais comum: X (0 conversas)" e
  # pior que nao mostrar cartao nenhum. Todos os destaques saem de `active`.
  def kpis(rows)
    active = rows.select { |row| row[:total].positive? }

    {
      reasons_count: active.size,
      conversations_total: active.sum { |row| row[:total] },
      top_reason: top_reason(active),
      slowest_reason: slowest_reason(active),
      avg_fcr: pct(active.sum { |row| row[:fcr_count] }, active.sum { |row| row[:resolved_count] })
    }
  end

  # `active` ja vem ordenado por volume desc (`reason_rows`).
  def top_reason(active)
    top = active.first
    top && { name: top[:name], total: top[:total], pct: top[:pct] }
  end

  def slowest_reason(active)
    slowest = active.max_by { |row| row[:avg_handle_seconds] }
    slowest && { name: slowest[:name], avg_handle_seconds: slowest[:avg_handle_seconds] }
  end

  # ---------- Linhas por motivo ----------

  # `previous_total` vai cru, sem `trend_pct` pre-calculada em Ruby: mesmo
  # precedente de OwnershipSummaryBuilder (fatia 1) e FilaHistoricoBuilder
  # (fatia 4). Variacao contra periodo anterior e apresentacao -- quem decide
  # como mostrar "sem base de comparacao" (periodo anterior zerado) e a tela,
  # que tem o contexto para diferenciar isso de "cresceu 100%".
  # Enumera a uniao dos dois periodos, nao so o atual: um motivo que existia
  # antes e zerou agora e o achado mais valioso desta tela -- some da tabela se
  # a iteracao for so sobre o periodo atual, e "caiu para zero" fica
  # indistinguivel de "nunca existiu". Mesma correcao que a fatia 4 fez em
  # `by_team` (equipe ociosa aparece com 0%, nao desaparece).
  #
  # Nao enumera toda etiqueta selecionada, e ai diverge de `by_team` de
  # proposito: etiqueta sem nenhuma ocorrencia nos DOIS periodos nao e
  # informacao de gestao, e so empurraria linhas zeradas para dentro da tabela
  # (a selecao pode ter dezenas de etiquetas).
  def reason_rows
    current = reason_facts(current_range)
    previous = previous_volume_by_reason
    total = current.sum { |_name, facts| facts[:total] }

    rows = (current.keys | previous.keys).map do |name|
      build_row(name, current[name] || EMPTY_FACTS, total, previous[name].to_i)
    end

    rows.sort_by { |row| -row[:total] }
  end

  EMPTY_FACTS = {
    total: 0, handed_off: 0, resolved_count: 0,
    avg_handle_seconds: nil, fcr_count: 0, bot_resolved_count: 0
  }.freeze

  # `bot_resolved_pct` e `fcr_pct` dividem pelas RESOLVIDAS, nao pelo total:
  # as duas respondem "das que fecharam, quantas...", e um motivo com muita
  # conversa ainda aberta mostraria participacao do robo artificialmente baixa.
  # `bot_handoff_pct` divide pelo total de proposito -- transferencia acontece
  # em conversa aberta tambem, entao a populacao dela e outra. Os denominadores
  # diferentes estao escritos na nota de criterio da tela.
  def build_row(name, facts, total, previous_total)
    resolved = facts[:resolved_count]

    {
      name: name,
      color: label_colors[name],
      total: facts[:total],
      previous_total: previous_total,
      pct: pct(facts[:total], total),
      avg_handle_seconds: facts[:avg_handle_seconds].to_f.round,
      resolved_count: resolved,
      fcr_count: facts[:fcr_count],
      fcr_pct: resolved.positive? ? pct(facts[:fcr_count], resolved) : nil,
      bot_resolved_pct: pct(facts[:bot_resolved_count], resolved),
      bot_handoff_pct: pct(facts[:handed_off], facts[:total])
    }
  end

  def pct(part, total)
    return 0.0 unless total.positive?

    (part.to_f / total * 100).round(1)
  end

  # ---------- Volume e resolucao, numa leitura so ----------

  # Seis metricas numa varredura, com agregacao condicional sobre o LEFT JOIN
  # que o finder monta -- o padrao que a fatia 4 (Cockpit) adotou depois da
  # revisao de banco, e que o upstream ja usa em Reports::RawDataSource. A fonte
  # fazia uma consulta por metrica, e a de FCR ainda materializava um `pluck` de
  # conversation_id em array Ruby.
  #
  # Ler volume e resolucao juntos nao e so economia: e o que impede
  # `resolved_count` de passar `total` quando alguem etiqueta uma conversa no
  # meio da requisicao (ver o comentario do finder).
  #
  # `COUNT(DISTINCT conversations.id)` em vez de `count`: o join com `taggings`
  # multiplica linha por etiqueta, e o LEFT JOIN das resolucoes multiplica de
  # novo por resolucao. `AVG(value)` fica sobre as linhas mesmo (nao por
  # conversa distinta) de proposito: o TMA e a media do tempo que cada resolucao
  # levou, e uma conversa reaberta teve de fato dois tempos de atendimento.
  def reason_facts(range)
    finder.tagged_conversations_with_resolutions(range)
          .group('tags.name')
          .pluck(Arel.sql(reason_facts_sql))
          .to_h { |row| [row.first, fact_row(row)] }
  end

  def reason_facts_sql
    <<~SQL.squish
      tags.name,
      COUNT(DISTINCT conversations.id),
      COUNT(DISTINCT conversations.id) FILTER (WHERE #{ownership_finder.handed_off_condition}),
      COUNT(DISTINCT reporting_events.conversation_id),
      AVG(reporting_events.value),
      COUNT(DISTINCT reporting_events.conversation_id) FILTER (WHERE #{ownership_finder.single_resolution_condition}),
      COUNT(DISTINCT reporting_events.conversation_id) FILTER (WHERE #{ownership_finder.bot_resolution_condition})
    SQL
  end

  def fact_row(row)
    _name, total, handed_off, resolved, avg_value, fcr, bot_resolved = row
    {
      total: total,
      handed_off: handed_off,
      resolved_count: resolved,
      avg_handle_seconds: avg_value,
      fcr_count: fcr,
      bot_resolved_count: bot_resolved
    }
  end

  # Do periodo anterior so o total interessa -- a tela so compara volume, entao
  # pagar o LEFT JOIN e os FILTER de novo seria trabalho sem consumidor.
  def previous_volume_by_reason
    finder.tagged_conversations(previous_range).group('tags.name').distinct.count('conversations.id')
  end

  # ---------- Evolucao semanal ----------

  def weekly_evolution(top_rows)
    return { labels: [], series: [] } if top_rows.empty?

    counts = weekly_counts(top_rows.pluck(:name))
    weeks = counts.keys.map(&:last).uniq.sort

    {
      labels: weeks.map { |week| week.to_date.to_s },
      series: top_rows.map { |row| weekly_series(row, weeks, counts) }
    }
  end

  def weekly_series(row, weeks, counts)
    {
      name: row[:name],
      color: row[:color],
      data: weeks.map { |week| counts[[row[:name], week]].to_i }
    }
  end

  # A barra da semana agrupa pela MESMA dimensao temporal que define a
  # populacao: datar a conversa pela criacao e empilhar as barras pelo
  # encerramento (ou vice-versa) daria um grafico que nao soma o total da tabela
  # ao lado. E a mesma correcao de eixo misto que a fatia 4 fez em
  # `daily_evolution`, so que aqui o eixo troca conforme o filtro da tela.
  def weekly_counts(names)
    return weekly_counts_by_resolution(names) if finder.resolved_date_field?

    finder.tagged_conversations(current_range)
          .where(tags: { name: names })
          .group('tags.name', Arel.sql("DATE_TRUNC('week', conversations.created_at)"))
          .distinct
          .count('conversations.id')
  end

  def weekly_counts_by_resolution(names)
    finder.tagged_resolutions(current_range)
          .where(tags: { name: names })
          .group('tags.name', Arel.sql("DATE_TRUNC('week', reporting_events.created_at)"))
          .distinct
          .count('reporting_events.conversation_id')
  end

  # ---------- Apoio ----------

  def finder
    @finder ||= Reports::TaggedConversationFinder.new(@account, @params)
  end

  def ownership_finder
    @ownership_finder ||= Reports::ConversationOwnershipFinder.new(@account)
  end

  # Cor sai de `labels` (configuracao da conta), enquanto o agrupamento sai de
  # `tags` (o registro do acts_as_taggable). Sao tabelas diferentes e casam pelo
  # texto: `labels.title` == `tags.name`. Uma conversa etiquetada com um label
  # que foi apagado depois continua no relatorio, com cor nula -- a tela decide
  # a cor neutra, o backend nao inventa uma.
  def label_colors
    @label_colors ||= @account.labels.where(title: finder.selected_labels).pluck(:title, :color).to_h
  end

  # ---------- Periodos ----------

  # A janela chega validada pelo controller (422 sem as duas pontas e acima do
  # teto), como as outras acoes desta onda. O parse aqui e estrito de proposito.
  def current_range
    @current_range ||= epoch_param(:since)..epoch_param(:until)
  end

  # Mesma duracao, imediatamente antes. Aberto no fim (`...`) -- fechado nos
  # dois lados contaria o instante da fronteira nos dois periodos (mesma
  # correcao de OwnershipSummaryBuilder#previous_range).
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
