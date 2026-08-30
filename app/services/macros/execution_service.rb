class Macros::ExecutionService < ActionService
  def initialize(macro, conversation, user, inputs = {})
    super(conversation)
    @macro = macro
    @account = macro.account
    @user = user
    @inputs = (inputs || {}).transform_keys(&:to_s)
    @substitutor = Macros::VariableSubstitutor.new(@inputs)
    Current.user = user
  end

  def perform
    execution = build_execution
    failures = []

    @macro.actions.each do |action|
      action = action.with_indifferent_access
      action_params = @substitutor.substitute_params(action[:action_params])
      begin
        send(action[:action_name], action_params)
        execution.actions_run += 1
      rescue StandardError => e
        failures << "#{action[:action_name]}: #{e.message}"
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
      end
    end

    finalize_execution(execution, failures)
  ensure
    Current.reset
  end

  private

  def build_execution
    MacroExecution.create!(
      account: @account,
      macro: @macro,
      conversation: @conversation,
      user: @user,
      inputs: @inputs,
      status: :pending,
      actions_total: @macro.actions.size
    )
  end

  # Sucesso parcial existe de proposito: cada action e executada num begin/rescue
  # proprio, entao uma falhar nao impede as outras. Registrar 'partial' deixa
  # isso visivel no historico em vez de virar sucesso silencioso.
  def finalize_execution(execution, failures)
    status = if failures.empty?
               :success
             elsif execution.actions_run.zero?
               :failed
             else
               :partial
             end

    execution.update!(status: status, error_message: failures.join(' | ').presence)
  end

  def assign_agent(agent_ids)
    agent_ids = agent_ids.map { |id| id == 'self' ? @user.id : id }
    super(agent_ids)
  end

  def add_private_note(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: true }

    # Added reload here to ensure conversation us persistent with the latest updates
    mb = Messages::MessageBuilder.new(@user, @conversation.reload, params)
    mb.perform
  end

  def send_message(message)
    return if conversation_a_tweet?

    params = { content: message[0], private: false }

    # Added reload here to ensure conversation us persistent with the latest updates
    mb = Messages::MessageBuilder.new(@user, @conversation.reload, params)
    mb.perform
  end

  def send_attachment(blob_ids)
    return if conversation_a_tweet?

    return unless @macro.files.attached?

    blobs = ActiveStorage::Blob.where(id: blob_ids)

    return if blobs.blank?

    params = { content: nil, private: false, attachments: blobs }

    # Added reload here to ensure conversation us persistent with the latest updates
    mb = Messages::MessageBuilder.new(@user, @conversation.reload, params)
    mb.perform
  end

  def send_webhook_event(webhook_url)
    url = webhook_url.first
    # A URL vem do corpo da macro, escrita por um agente. Sem esta guarda ela
    # pode apontar para a rede interna da instalacao (ver Macros::SafeUrl).
    raise ArgumentError, "Unsafe webhook URL: #{url}" unless Macros::SafeUrl.public_http?(url)

    payload = @conversation.webhook_data.merge(
      event: 'macro.executed',
      macro: { id: @macro.id, name: @macro.name },
      macro_inputs: @inputs
    )
    WebhookJob.perform_later(url, payload)
  end
end

Macros::ExecutionService.include_mod_with('Macros::ExecutionService')
