class MacrosExecutionJob < ApplicationJob
  queue_as :medium

  def perform(macro, conversation_ids:, user:, inputs: {})
    account = macro.account
    conversations = permitted_conversations(account, user, conversation_ids)

    return if conversations.blank?

    conversations.each do |conversation|
      execute_for(macro, conversation, user, inputs)
    end
  end

  private

  # O endpoint de execute so autoriza a MACRO (MacroPolicy#execute?), e a lista
  # de conversation_ids chegava aqui filtrada apenas por account_id. Como uma
  # macro global e executavel por qualquer agente e pode disparar
  # send_webhook_event, isso permitia mandar o webhook_data de uma conversa de
  # uma inbox que o agente nao acessa para uma URL externa.
  #
  # O criterio abaixo espelha ConversationPolicy#agent_can_view_conversation?
  # (acesso por inbox OU por time). Nao da para usar user.assigned_inboxes aqui:
  # ele depende de Current.account, que nao esta setado dentro do job.
  def permitted_conversations(account, user, conversation_ids)
    scope = account.conversations.where(display_id: conversation_ids.to_a)
    return scope if account.account_users.find_by(user_id: user.id)&.administrator?

    inbox_ids = user.inboxes.where(account_id: account.id).select(:id)
    team_ids = user.teams.where(account_id: account.id).select(:id)

    scope.where(inbox_id: inbox_ids).or(scope.where(team_id: team_ids))
  end

  # Isolamento por conversa: sem isso, uma falha fora do rescue interno do
  # ExecutionService derruba o job inteiro, o Sidekiq reenfileira e as conversas
  # que ja rodaram com sucesso sao reprocessadas -- reenviando mensagens e
  # webhooks. As acoes nao sao idempotentes.
  def execute_for(macro, conversation, user, inputs)
    ::Macros::ExecutionService.new(macro, conversation, user, inputs).perform
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: macro.account).capture_exception
  end
end
