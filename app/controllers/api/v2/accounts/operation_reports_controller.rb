# [Onda 5] Relatorios de operacao do fork (cockpit, e adiante origem, fila e
# motivos) moram aqui em vez de crescerem o ReportsController do upstream.
#
# Dois motivos. O arquivo do upstream ja batia no limite do Metrics/ClassLength
# antes desta onda -- a primeira acao adicionada estourou o cop --, e ainda
# faltam tres. E deixar o arquivo do upstream intocado tira conflito de todo
# sync futuro, que e a estrategia do fork.
#
# A URL nao muda: as rotas continuam sob /reports/... e apontam para ca.
class Api::V2::Accounts::OperationReportsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :validate_time_window

  def cockpit_atendentes
    builder = V2::Reports::CockpitAtendentesBuilder.new(Current.account, cockpit_atendentes_params)
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
    return if since && until_time && since < until_time

    render_could_not_create_error(I18n.t('errors.reports.invalid_time_window'))
  end

  def cockpit_atendentes_params
    params.permit(:since, :until, :team_id, :status, :search, :date_field).to_h.symbolize_keys
  end
end
