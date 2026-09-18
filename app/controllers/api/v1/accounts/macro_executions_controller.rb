class Api::V1::Accounts::MacroExecutionsController < Api::V1::Accounts::BaseController
  MAX_LIMIT = 50
  DEFAULT_LIMIT = 20

  before_action :fetch_macro
  before_action :check_authorization
  before_action :fetch_execution, only: [:show]

  def index
    scope = apply_filters(visible_executions)
    @total_count = scope.count
    @executions = scope.limit(limit).offset(offset)
  end

  def show; end

  private

  # A autorizacao do endpoint e feita sobre a MACRO, e macro global e visivel
  # por qualquer agente da conta. Sem este recorte, o historico expunha os
  # `inputs` (que podem conter CPF/CNPJ digitado por um colega) e o
  # conversation_display_id de conversas fora do escopo de inbox/time do agente
  # -- justamente a fronteira que a ConversationPolicy protege no resto do app.
  #
  # Execucao sem conversa continua visivel: nao ha conversa cuja permissao
  # checar, e o registro nao carrega dado de atendimento de terceiro.
  def visible_executions
    scope = @macro.executions.includes(:user, :conversation).recent
    return scope if Current.account_user&.administrator?

    scope.where(conversation_id: nil).or(scope.where(conversation_id: visible_conversation_ids))
  end

  def visible_conversation_ids
    inbox_ids = Current.user.inboxes.where(account_id: Current.account.id).select(:id)
    team_ids = Current.user.teams.where(account_id: Current.account.id).select(:id)

    Current.account.conversations
           .where(inbox_id: inbox_ids)
           .or(Current.account.conversations.where(team_id: team_ids))
           .select(:id)
  end

  # find (e nao find_by) de proposito: id inexistente vira 404 pelo
  # rescue_from do BaseController, em vez de NoMethodError mais adiante.
  def fetch_macro
    @macro = Current.account.macros.find(params[:macro_id])
  end

  def check_authorization
    authorize(@macro, :show?)
  end

  def fetch_execution
    @execution = visible_executions.find(params[:id])
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
