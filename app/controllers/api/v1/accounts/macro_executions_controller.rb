class Api::V1::Accounts::MacroExecutionsController < Api::V1::Accounts::BaseController
  MAX_LIMIT = 50
  DEFAULT_LIMIT = 20

  before_action :fetch_macro
  before_action :check_authorization
  before_action :fetch_execution, only: [:show]

  def index
    scope = apply_filters(@macro.executions.includes(:user, :conversation).recent)
    @total_count = scope.count
    @executions = scope.limit(limit).offset(offset)
  end

  def show; end

  private

  # find (e nao find_by) de proposito: id inexistente vira 404 pelo
  # rescue_from do BaseController, em vez de NoMethodError mais adiante.
  def fetch_macro
    @macro = Current.account.macros.find(params[:macro_id])
  end

  def check_authorization
    authorize(@macro, :show?)
  end

  def fetch_execution
    @execution = @macro.executions.find(params[:id])
  end

  def apply_filters(scope)
    scope = scope.where(status: MacroExecution.statuses[params[:status]]) if MacroExecution.statuses.key?(params[:status])
    scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?

    # Data invalida devolve nil no parse; aplicar o filtro assim mesmo geraria um
    # range degenerado e devolveria a lista errada em silencio. Melhor ignorar.
    from = parse_time(params[:from])
    to = parse_time(params[:to])
    scope = scope.where(created_at: from..) if from
    scope = scope.where(created_at: ..to) if to
    scope
  end

  def parse_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def limit
    requested = params[:limit].to_i
    return DEFAULT_LIMIT unless requested.positive?

    [requested, MAX_LIMIT].min
  end

  def offset
    params[:offset].to_i
  end
end
