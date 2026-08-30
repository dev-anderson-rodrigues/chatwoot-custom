class CreateMacroExecutions < ActiveRecord::Migration[7.1]
  def change
    create_table :macro_executions do |t|
      # index: false em account e macro porque os indices compostos criados
      # abaixo comecam por essas colunas -- um B-tree composto atende igualmente
      # bem os filtros que usam so a coluna lider, inclusive a varredura que o
      # ON DELETE CASCADE faz. Manter os indices soltos so somaria amplificacao
      # de escrita: o job grava 1 INSERT + 1 UPDATE por conversa em lote.
      t.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :macro, null: false, index: false, foreign_key: { on_delete: :cascade }
      # user_id mantem o indice solto: nenhum composto comeca por ele, e o
      # ON DELETE SET NULL precisa achar as linhas do usuario apagado sem
      # varrer a tabela inteira.
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
