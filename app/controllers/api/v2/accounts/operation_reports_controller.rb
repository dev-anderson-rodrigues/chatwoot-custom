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

  def cockpit_atendentes
    builder = V2::Reports::CockpitAtendentesBuilder.new(Current.account, cockpit_atendentes_params)
    render json: builder.metrics
  end

  private

  # Mesma autorizacao do ReportsController: relatorio e coisa de administrador.
  def check_authorization
    authorize :report, :view?
  end

  def cockpit_atendentes_params
    params.permit(:since, :until, :team_id, :status, :search, :date_field).to_h.symbolize_keys
  end
end
