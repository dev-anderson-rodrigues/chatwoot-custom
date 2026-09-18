class AddAccountConversationCreatedIndexToMessages < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    # V2::Reports::OrigemBuilder#first_message_table (fatia 3, Onda 5) roda
    # `SELECT DISTINCT ON (conversation_id) ... WHERE account_id = X ...
    # ORDER BY conversation_id, created_at, id` a cada chamada do relatorio.
    #
    # Os indices que ja existem em messages nao servem para isto:
    # (account_id, created_at, message_type) tem a ordem de colunas errada
    # para o ORDER BY, e (conversation_id, account_id, message_type, created_at)
    # lidera por conversation_id, entao nao filtra account_id de forma seletiva.
    # Sem um indice no formato certo, o DISTINCT ON obriga um Sort explicito de
    # todo o historico de mensagens nao-activity da conta -- custo que escala
    # com o tempo de vida da conta, nao com a janela pedida no relatorio
    # (achado da revisao de banco da fatia 3).
    add_index :messages, [:account_id, :conversation_id, :created_at],
              name: 'index_messages_on_account_conversation_created',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
