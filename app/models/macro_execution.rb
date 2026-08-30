# == Schema Information
#
# Table name: macro_executions
#
#  id              :bigint           not null, primary key
#  actions_run     :integer          default(0), not null
#  actions_total   :integer          default(0), not null
#  error_message   :string
#  inputs          :jsonb            not null
#  status          :integer          default("pending"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint
#  macro_id        :bigint           not null
#  user_id         :bigint
#
# Indexes
#
#  index_macro_executions_on_account_id                 (account_id)
#  index_macro_executions_on_account_id_and_created_at  (account_id,created_at DESC)
#  index_macro_executions_on_conversation_id            (conversation_id)
#  index_macro_executions_on_macro_id                   (macro_id)
#  index_macro_executions_on_macro_id_and_created_at    (macro_id,created_at DESC)
#  index_macro_executions_on_user_id                    (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (macro_id => macros.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
class MacroExecution < ApplicationRecord
  belongs_to :account
  belongs_to :macro
  belongs_to :user, optional: true
  # Sem FK no banco (ver a migration); a conversa pode ter sido apagada depois.
  belongs_to :conversation, optional: true

  enum status: { pending: 0, success: 1, partial: 2, failed: 3 }

  scope :recent, -> { order(created_at: :desc) }

  # `inputs` e jsonb not null default {} -- o banco ja garante a presenca.
  # Um hash vazio e valido (macro sem input_fields), entao NAO cabe
  # `presence: true` aqui: `{}.blank?` e true no Rails e isso quebraria toda
  # macro sem campos customizados. Validamos so que e um Hash.
  validate :inputs_must_be_hash

  private

  def inputs_must_be_hash
    errors.add(:inputs, 'must be a hash') unless inputs.is_a?(Hash)
  end
end
