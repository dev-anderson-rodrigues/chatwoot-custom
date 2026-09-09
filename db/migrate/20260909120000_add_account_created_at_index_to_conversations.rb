class AddAccountCreatedAtIndexToConversations < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    # O cockpit conta conversas por agente numa janela de datas, sem filtrar
    # status. O indice existente (account_id, status, created_at) nao serve: sem
    # igualdade em `status`, o created_at nao esta ordenado dentro do prefixo, e
    # o plano degenera para varrer todas as linhas da conta.
    add_index :conversations, [:account_id, :created_at],
              name: 'index_conversations_on_account_id_created_at',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
