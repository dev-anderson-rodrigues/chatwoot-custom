# [Onda 5] Relatorios de operacao do fork (cockpit, monitoramento, origem,
# fila, e adiante motivos) moram aqui em vez de crescerem o ReportsController
# do upstream.
#
# Dois motivos. O arquivo do upstream ja batia no limite do Metrics/ClassLength
# antes desta onda -- a primeira acao adicionada estourou o cop --, e ainda
# falta uma. E deixar o arquivo do upstream intocado tira conflito de todo
# sync futuro, que e a estrategia do fork.
#
# A URL nao muda: as rotas continuam sob /reports/... e apontam para ca.
class Api::V2::Accounts::OperationReportsController < Api::V1::Accounts::BaseController
  # Mesmo teto que o upstream aplica no summary de canais, e pela mesma razao:
  # consulta pesada com janela aberta e convite para estourar o statement_timeout
  # de 14s. Aqui pesa o dobro, porque o resumo tambem consulta o periodo
  # anterior. As telas oferecem no maximo 90 dias; o teto so barra intervalo
  # livre absurdo ou chamada direta na API.
  MAX_WINDOW = 6.months

  before_action :check_authorization
  # `except:`, nao `only:`, de proposito: a maioria das acoes futuras da onda
  # (fatias 3 a 5) tem janela, e esquecer de inclui-la aqui falharia alto (422
  # obvio no primeiro teste manual). O contrario -- esquecer de EXCLUIR uma
  # acao sem janela -- tambem falha alto, mas so nela, e so quem editar o
  # `supervisor` precisa saber disso.
  before_action :validate_time_window, except: %i[supervisor]

  def cockpit_atendentes
    builder = V2::Reports::CockpitAtendentesBuilder.new(Current.account, cockpit_atendentes_params)
    render json: builder.metrics
  end

  def ownership_summary
    builder = V2::Reports::OwnershipSummaryBuilder.new(Current.account, ownership_summary_params)
    render json: builder.metrics
  end

  def supervisor
    builder = V2::Reports::SupervisorBuilder.new(Current.account, supervisor_params)
    render json: builder.metrics
  end

  def origem
    builder = V2::Reports::OrigemBuilder.new(Current.account, origem_params)
    render json: builder.metrics
  end

  def fila_historico
    builder = V2::Reports::FilaHistoricoBuilder.new(Current.account, fila_historico_params)
    render json: builder.metrics
  end

  def motivos
    builder = V2::Reports::MotivosBuilder.new(Current.account, motivos_params)
    render json: builder.metrics
  end

  private

  # Mesma autorizacao do ReportsController: relatorio e coisa de administrador.
  def check_authorization
    authorize :report, :view?
  end

  # Todo relatorio daqui e sobre um periodo. Sem as duas pontas, o builder
  # filtrava 1970..1970 e a tela mostrava "nenhum dado" para o que era um erro de
  # contrato. Este e o unico ponto que valida a janela; os builders so fazem o
  # parse estrito. Base 10 explicita: sem ela o Integer aceita "0x1A" e le "010"
  # como octal.
  def validate_time_window
    since = Integer(params[:since].to_s, 10, exception: false)
    until_time = Integer(params[:until].to_s, 10, exception: false)
    return render_could_not_create_error(I18n.t('errors.reports.invalid_time_window')) unless
      since && until_time && since < until_time

    return unless until_time - since > MAX_WINDOW

    render_could_not_create_error(I18n.t('errors.reports.date_range_too_long'))
  end

  def cockpit_atendentes_params
    params.permit(:since, :until, :team_id, :status, :search, :date_field).to_h.symbolize_keys
  end

  def ownership_summary_params
    params.permit(:since, :until).to_h.symbolize_keys
  end

  def supervisor_params
    params.permit(:team_id, :agent_type, :status_filter, :page, :per_page).to_h.symbolize_keys
  end

  def origem_params
    params.permit(:since, :until, :team_id, :agent_type).to_h.symbolize_keys
  end

  def fila_historico_params
    params.permit(:since, :until, :team_id, :agent_type).to_h.symbolize_keys
  end

  # A unica acao da onda com filtro de lista (`labels`), e a unica que oferece
  # caixa -- Motivos e a tela de analise, nao de acompanhamento. `labels: []` por
  # ultimo porque `permit` exige os escalares antes do hash de colecao.
  #
  # A fonte tambem filtrava por atendente e por status, e os dois foram
  # deixados de fora: nenhuma tela os envia, e `status` invalido cairia num
  # `where` que devolve zero em silencio -- estado inconsistente sem aviso, que
  # e justamente o que o backend.mdc manda nao fazer. O endpoint nasceu nesta
  # onda e nao tem consumidor externo, entao nao ha compatibilidade a preservar:
  # quando alguma tela precisar de um dos dois, ele volta com validacao.
  def motivos_params
    params.permit(:since, :until, :team_id, :inbox_id, :date_field, :agent_type, labels: [])
          .to_h.symbolize_keys
  end
end
