# == Schema Information
#
# Table name: macros
#
#  id            :bigint           not null, primary key
#  actions       :jsonb            not null
#  input_fields  :jsonb            not null
#  name          :string           not null
#  visibility    :integer          default("personal")
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :bigint
#  updated_by_id :bigint
#
# Indexes
#
#  index_macros_on_account_id  (account_id)
#
class Macro < ApplicationRecord
  include Rails.application.routes.url_helpers

  belongs_to :account
  belongs_to :created_by,
             class_name: :User, optional: true, inverse_of: :macros
  belongs_to :updated_by,
             class_name: :User, optional: true
  has_many :executions, class_name: 'MacroExecution', dependent: :destroy
  has_many_attached :files

  enum visibility: { personal: 0, global: 1 }

  validate :json_actions_format
  validate :input_fields_format

  ACTIONS_ATTRS = %w[send_message add_label assign_team assign_agent mute_conversation change_status remove_label remove_assigned_agent
                     remove_assigned_team resolve_conversation snooze_conversation change_priority send_email_transcript
                     send_attachment add_private_note send_webhook_event].freeze

  # Campos que o agente preenche na hora de executar a macro. O valor entra nos
  # action_params via token {{chave}} (ver Macros::VariableSubstitutor).
  INPUT_FIELD_TYPES = %w[text textarea number email date phone cpf cnpj select lookup].freeze
  INPUT_FIELD_KEY_REGEX = /\A[a-z][a-z0-9_]*\z/

  def set_visibility(user, params)
    self.visibility = params[:visibility]
    self.visibility = :personal if user.agent?
  end

  def self.with_visibility(user, _params)
    records = Current.account.macros.global
    records = records.or(personal.where(created_by_id: user.id, account_id: Current.account.id))
    records.order(:id)
  end

  def self.current_page(params)
    params[:page] || 1
  end

  def file_base_data
    files.map do |file|
      {
        id: file.id,
        macro_id: id,
        file_type: file.content_type,
        account_id: account_id,
        file_url: url_for(file),
        blob_id: file.blob_id,
        filename: file.filename.to_s
      }
    end
  end

  private

  def json_actions_format
    return if actions.blank?

    attributes = actions.map { |obj, _| obj['action_name'] }
    # Variavel local com nome proprio: `actions = ...` sombreava o atributo do
    # model, entao a mensagem de erro listava a lista errada.
    invalid_actions = attributes - ACTIONS_ATTRS

    errors.add(:actions, "Macro execution actions #{invalid_actions.join(',')} not supported.") if invalid_actions.any?
  end

  def input_fields_format
    return if input_fields.blank?

    unless input_fields.is_a?(Array)
      errors.add(:input_fields, 'must be an array')
      return
    end

    keys_seen = Set.new
    input_fields.each_with_index { |field, index| validate_input_field(field, index, keys_seen) }
  end

  def validate_input_field(field, index, keys_seen)
    prefix = "input_fields[#{index}]"

    return errors.add(:input_fields, "#{prefix} must be an object") unless field.is_a?(Hash)

    validate_field_key(field, prefix, keys_seen)
    errors.add(:input_fields, "#{prefix}.label is required") if field['label'].to_s.strip.blank?

    type = field['type'].to_s
    return errors.add(:input_fields, "#{prefix}.type '#{type}' is not supported") unless INPUT_FIELD_TYPES.include?(type)

    validate_select_field(field, prefix) if type == 'select'
    validate_lookup_field(field, prefix) if type == 'lookup'
  end

  def validate_field_key(field, prefix, keys_seen)
    key = field['key'].to_s

    if key.blank?
      errors.add(:input_fields, "#{prefix}.key is required")
    elsif !key.match?(INPUT_FIELD_KEY_REGEX)
      errors.add(:input_fields, "#{prefix}.key must be snake_case (lowercase, digits, underscore)")
    elsif keys_seen.include?(key)
      errors.add(:input_fields, "#{prefix}.key '#{key}' is duplicated")
    else
      keys_seen << key
    end
  end

  def validate_select_field(field, prefix)
    options = field['options']
    return if options.is_a?(Array) && options.present?

    errors.add(:input_fields, "#{prefix}.options is required for select fields")
  end

  def validate_lookup_field(field, prefix)
    lookup_url = field['lookup_url'].to_s.strip

    if lookup_url.blank?
      errors.add(:input_fields, "#{prefix}.lookup_url is required for lookup fields")
    else
      validate_lookup_url(prefix, lookup_url)
    end

    depends_on = field['depends_on']
    return if depends_on.is_a?(Array) && depends_on.present?

    errors.add(:input_fields, "#{prefix}.depends_on must list at least one key")
  end

  def validate_lookup_url(prefix, url)
    uri = URI.parse(url)
    unless %w[http https].include?(uri.scheme) && uri.host.present?
      errors.add(:input_fields, "#{prefix}.lookup_url must be a valid http(s) URL")
      return
    end

    return if Macros::SafeUrl.public_http?(url)

    errors.add(:input_fields, "#{prefix}.lookup_url must point to a public host (no private/loopback IPs)")
  rescue URI::InvalidURIError
    errors.add(:input_fields, "#{prefix}.lookup_url is not a valid URL")
  end
end

Macro.include_mod_with('Audit::Macro')
