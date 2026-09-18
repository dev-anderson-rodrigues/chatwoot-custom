# [Onda 5 / fatia 1] Resumo de atendimento separado por robo e humano.
#
# Primeiro consumidor do Reports::ConversationOwnershipFinder. Responde "quanto
# o robo resolveu sozinho, quanto sobrou para gente, e quanto cada lado demorou",
# no periodo e no periodo anterior de mesmo tamanho.
#
# Nao reusa o `bot_summary` do upstream (V2::Reports::Conversations::MetricBuilder)
# de proposito: ele conta resolucao do bot por um criterio diferente do nosso --
# o evento `conversation_bot_resolved` sozinho, sem olhar se a conversa foi aberta
# ou atribuida antes. Mexer nele mudaria o numero da tela de Robos do upstream e
# pagaria conflito em todo sync. As duas telas convivem, e o tooltip da nossa
# explica o criterio.
#
# Nao existe "TME do robo": o `first_response` so e gravado para resposta humana
# (ver Message#human_response?), entao por construcao ele e sempre do humano.
class V2::Reports::OwnershipSummaryBuilder
  def initialize(account, params = {})
    @account = account
    @params = params
  end

  def metrics
    { current: summary(time_range), previous: summary(previous_range) }
  end

  private

  def summary(range)
    por_dono = resolutions_by_owner(range)
    demais = other_metrics(range)

    {
      bot_resolutions: por_dono.dig(true, :count).to_i,
      human_resolutions: por_dono.dig(false, :count).to_i,
      bot_avg_resolution_seconds: por_dono.dig(true, :avg).to_f.round,
      human_avg_resolution_seconds: por_dono.dig(false, :avg).to_f.round,
      human_avg_first_response_seconds: demais[0].to_f.round,
      handoffs: demais[1].to_i
    }
  end

  # Agrupa pelo proprio predicado em vez de repeti-lo dentro de varios FILTER.
  #
  # O motivo e medido, nao estetico: o Postgres NAO reaproveita subexpressao
  # comum entre FILTERs diferentes, mesmo sendo o mesmo texto SQL. A versao
  # anterior repetia o predicado quatro vezes e o plano saia com OITO
  # subconsultas correlacionadas por linha -- 1,7s para 150 mil resolucoes de uma
  # conta, e `metrics` chama isto duas vezes (periodo atual e anterior). No
  # GROUP BY o predicado vira chave de agrupamento e e avaliado uma vez por
  # linha: duas sondas em vez de oito.
  def resolutions_by_owner(range)
    condicao = ownership_finder.bot_resolution_condition

    @account.reporting_events
            .where(name: 'conversation_resolved', created_at: range)
            .group(condicao)
            .pluck(condicao, Arel.sql('COUNT(*)'), Arel.sql('AVG(value)'))
            .to_h { |is_bot, count, avg| [is_bot, { count: count, avg: avg }] }
  end

  # Estas duas nao dependem de quem atendeu, entao ficam fora do escopo do
  # classificador: assim o predicado nao roda nas linhas de `first_response` e de
  # handoff, que antes tambem o pagavam.
  def other_metrics(range)
    @account.reporting_events
            .where(name: %w[first_response conversation_bot_handoff], created_at: range)
            .pick(Arel.sql(<<~SQL.squish))
              AVG(value) FILTER (WHERE name = 'first_response'),
              COUNT(DISTINCT conversation_id) FILTER (WHERE name = 'conversation_bot_handoff')
            SQL
  end

  def ownership_finder
    @ownership_finder ||= Reports::ConversationOwnershipFinder.new(@account)
  end

  # Periodo anterior de mesmo tamanho, colado no inicio do atual: e o que faz a
  # variacao significar alguma coisa.
  #
  # Intervalo aberto no fim (`...`) de proposito: o atual comeca em
  # `time_range.begin` e o inclui, entao fechar os dois contaria um evento no
  # instante exato da fronteira duas vezes.
  def previous_range
    duracao = time_range.end - time_range.begin

    (time_range.begin - duracao)...time_range.begin
  end

  # A janela chega validada pelo controller (422 sem as duas pontas). O parse
  # aqui e estrito para quem chamar o builder por fora nao receber um relatorio
  # de 1970 em silencio.
  def time_range
    @time_range ||= epoch_param(:since)..epoch_param(:until)
  end

  def epoch_param(key)
    Time.zone.at(Integer(@params.fetch(key).to_s, 10))
  end
end
