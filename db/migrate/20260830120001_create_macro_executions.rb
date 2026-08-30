class CreateMacroExecutions < ActiveRecord::Migration[7.1]
  def change
    create_table :macro_executions do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :macro, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: true, foreign_key: { on_delete: :nullify }

      # Sem foreign_key para conversations de proposito: nao existe nenhuma FK para
      # essa tabela no schema, e a PK dela e serial (integer), nao bigint. Alem
      # disso, foreign_key: true no Rails gera NO ACTION -- apagar uma conversa que
      # tem execucao registrada passaria a estourar erro. O registro de auditoria
      # sobrevive a conversa; o serializer ja trata conversation nula.
      t.bigint :conversation_id, null: true

      t.jsonb :inputs, null: false, default: {}
      t.integer :status, null: false, default: 0
      t.string :error_message
      t.integer :actions_run, null: false, default: 0
      t.integer :actions_total, null: false, default: 0

      t.timestamps
    end

    add_index :macro_executions, :conversation_id
    add_index :macro_executions, [:macro_id, :created_at], order: { created_at: :desc }
    add_index :macro_executions, [:account_id, :created_at], order: { created_at: :desc }
  end
end
