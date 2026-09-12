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
  EVENT_NAMES = %w[conversation_resolved first_response conversation_bot_handoff].freeze

  def initialize(account, params = {})
    @account = account
    @params = params
  end

  def metrics
    { current: summary(time_range), previous: summary(previous_range) }
  end

  private

  # Uma passada por periodo, com agregacao condicional: o mesmo padrao do
  # cockpit e do Reports::RawDataSource do upstream. A alternativa seria uma
  # varredura por metrica, e o predicado do classificador roda em cada uma.
  def summary(range)
    row = @account.reporting_events
                  .where(name: EVENT_NAMES, created_at: range)
                  .pick(Arel.sql(aggregates))

    {
      bot_resolutions: row[0].to_i,
      human_resolutions: row[1].to_i,
      bot_avg_resolution_seconds: row[2].to_f.round,
      human_avg_resolution_seconds: row[3].to_f.round,
      human_avg_first_response_seconds: row[4].to_f.round,
      handoffs: row[5].to_i
    }
  end

  def aggregates
    resolved = "name = 'conversation_resolved'"
    bot = ownership_finder.bot_resolution_condition

    <<~SQL.squish
      COUNT(*) FILTER (WHERE #{resolved} AND #{bot}),
      COUNT(*) FILTER (WHERE #{resolved} AND NOT #{bot}),
      AVG(value) FILTER (WHERE #{resolved} AND #{bot}),
      AVG(value) FILTER (WHERE #{resolved} AND NOT #{bot}),
      AVG(value) FILTER (WHERE name = 'first_response'),
      COUNT(DISTINCT conversation_id) FILTER (WHERE name = 'conversation_bot_handoff')
    SQL
  end

  def ownership_finder
    @ownership_finder ||= Reports::ConversationOwnershipFinder.new(@account)
  end

  # Periodo anterior de mesmo tamanho, colado no inicio do atual: e o que faz a
  # variacao significar alguma coisa.
  def previous_range
    duracao = time_range.end - time_range.begin

    (time_range.begin - duracao)..time_range.begin
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
