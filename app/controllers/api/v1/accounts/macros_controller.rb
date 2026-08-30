class Api::V1::Accounts::MacrosController < Api::V1::Accounts::BaseController
  include AttachmentConcern

  before_action :fetch_macro, only: [:show, :update, :destroy, :execute]
  before_action :check_authorization, only: [:show, :update, :destroy, :execute]

  def index
    @macros = Macro.with_visibility(current_user, params)
  end

  def show
    head :not_found if @macro.nil?
  end

  def create
    blobs, actions, error = validate_and_prepare_attachments(params[:actions])
    return render_could_not_create_error(error) if error

    @macro = Current.account.macros.new(macros_with_user.merge(created_by_id: current_user.id))
    @macro.set_visibility(current_user, permitted_params)
    @macro.actions = actions

    return render_could_not_create_error(@macro.errors.messages) unless @macro.valid?

    @macro.save!
    blobs.each { |blob| @macro.files.attach(blob) }
  end

  def update
    blobs, actions, error = validate_and_prepare_attachments(params[:actions], @macro)
    return render_could_not_create_error(error) if error

    ActiveRecord::Base.transaction do
      @macro.assign_attributes(macros_with_user)
      @macro.set_visibility(current_user, permitted_params)
      @macro.actions = actions if params[:actions]
      @macro.save!
      blobs.each { |blob| @macro.files.attach(blob) }
    rescue StandardError => e
      Rails.logger.error e
      render_could_not_create_error(@macro.errors.messages)
    end
  end

  def destroy
    @macro.destroy!
    head :ok
  end

  def execute
    ::MacrosExecutionJob.perform_later(
      @macro,
      conversation_ids: params[:conversation_ids],
      user: Current.user,
      inputs: inputs_param
    )

    head :ok
  end

  def stats
    macros = Macro.with_visibility(current_user, params).select(:id, :name)
    macro_ids = macros.map(&:id)
    counts = execution_counts(macro_ids)
    last_runs = last_execution_times(macro_ids)

    @stats = macros.map { |macro| macro_stats(macro, counts, last_runs) }
  end

  private

  def execution_counts(macro_ids)
    MacroExecution.where(account_id: Current.account.id, macro_id: macro_ids)
                  .where(created_at: stats_range)
                  .group(:macro_id, :status)
                  .count
  end

  def last_execution_times(macro_ids)
    MacroExecution.where(account_id: Current.account.id, macro_id: macro_ids)
                  .group(:macro_id)
                  .maximum(:created_at)
  end

  def macro_stats(macro, rows, last_runs)
    # group(:macro_id, :status).count devolve a chave do enum ja convertida para
    # o nome ("success"), nao para o inteiro. Aceitamos as duas formas para nao
    # depender desse detalhe do Rails -- indexar so por inteiro fazia todo
    # contador voltar zero, em silencio.
    counts = MacroExecution.statuses.to_h do |name, value|
      [name.to_sym, rows[[macro.id, name]] || rows[[macro.id, value]] || 0]
    end
    # Pendente nao entra na taxa: a execucao ainda nao terminou, contar como
    # fracasso faria o numero despencar durante um lote grande.
    finished = counts[:success] + counts[:partial] + counts[:failed]

    {
      macro_id: macro.id,
      macro_name: macro.name,
      total: counts.values.sum,
      counts: counts,
      success_rate: finished.zero? ? nil : (counts[:success].to_f / finished * 100).round(1),
      last_executed_at: last_runs[macro.id]&.to_i
    }
  end

  def stats_range
    from = params[:from].presence && parse_time(params[:from])
    to = params[:to].presence && parse_time(params[:to])
    (from || 30.days.ago)..(to || Time.current)
  end

  def parse_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def inputs_param
    raw = params[:inputs]
    return {} if raw.blank?

    raw.respond_to?(:permit!) ? raw.permit!.to_h : raw.to_h
  end

  def permitted_params
    params.permit(
      :name, :visibility,
      actions: [:action_name, { action_params: [] }],
      input_fields: [
        :key, :label, :type, :required, :placeholder, :default_value, :context_source,
        :lookup_url, :value_key, :label_key, :multi,
        { options: [:value, :label] },
        { depends_on: [] }
      ]
    )
  end

  def macros_with_user
    permitted_params.merge(updated_by_id: current_user.id)
  end

  def fetch_macro
    @macro = Current.account.macros.find_by(id: params[:id])
  end

  def check_authorization
    authorize(@macro) if @macro.present?
  end
end
