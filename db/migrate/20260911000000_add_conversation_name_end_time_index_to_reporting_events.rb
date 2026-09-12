class AddConversationNameEndTimeIndexToReportingEvents < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    # O classificador robo x humano (Reports::ConversationOwnershipFinder)
    # pergunta, para cada resolucao: existe o gemeo `conversation_bot_resolved`
    # no mesmo instante, e existe evidencia humana ate ali? Sao duas sondas por
    # (conversation_id, name) com comparacao em event_end_time.
    #
    # O unico indice que existe hoje e (conversation_id): cada sonda leria da
    # heap todos os eventos da conversa, e uma conversa longa de WhatsApp acumula
    # centenas de `reply_time`. Com o indice as tres colunas saem do proprio
    # indice.
    #
    # Aproveita tambem consultas que o upstream ja faz por conversa e nome:
    # `last_non_human_activity` (reporting_event_helper.rb) e a busca do
    # handoff/ultima resolucao no ReportingEventListener.
    add_index :reporting_events, [:conversation_id, :name, :event_end_time],
              name: 'index_reporting_events_on_conversation_name_end_time',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
