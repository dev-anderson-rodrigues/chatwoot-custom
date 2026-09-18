class AddAccountCreatedAgentIndexToCsatSurveyResponses < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    # O cockpit agrega CSAT por agente numa janela de datas. A tabela so tinha
    # indices de coluna unica (account_id, assigned_agent_id, ...), entao o par
    # conta + periodo nao era servido por nenhum.
    add_index :csat_survey_responses, [:account_id, :created_at, :assigned_agent_id],
              name: 'index_csat_survey_responses_on_account_created_agent',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
