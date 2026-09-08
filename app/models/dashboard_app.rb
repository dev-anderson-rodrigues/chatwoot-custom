# == Schema Information
#
# Table name: dashboard_apps
#
#  id              :bigint           not null, primary key
#  content         :jsonb
#  pin_to_sidebar  :boolean          default(FALSE), not null
#  show_in_sidebar :boolean          default(FALSE), not null
#  title           :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  user_id         :bigint
#
# Indexes
#
#  index_dashboard_apps_on_account_id  (account_id)
#  index_dashboard_apps_on_user_id     (user_id)
#
class DashboardApp < ApplicationRecord
  # Fora do metodo para nao remontar o hash a cada validacao -- e porque, com a
  # checagem de userinfo, `validate_content` passava do limite de linhas.
  CONTENT_SCHEMA = {
    'type' => 'array',
    'items' => {
      'type' => 'object',
      'required' => %w[url type],
      'properties' => {
        'type' => { 'enum': ['frame'] },
        'url' => { '$ref' => '#/definitions/saneUrl' }
      }
    },
    'definitions' => {
      'saneUrl' => { 'format' => 'uri', 'pattern' => '^https?://' }
    },
    'additionalProperties' => false,
    'minItems' => 1
  }.freeze

  belongs_to :user
  belongs_to :account
  validate :validate_content

  private

  def validate_content
    has_invalid_data = self[:content].blank? || !self[:content].is_a?(Array)
    self[:content] = [] if has_invalid_data

    unless JSONSchemer.schema(CONTENT_SCHEMA.to_json).valid?(self[:content])
      errors.add(:content, ': Invalid data')
      return
    end

    validate_urls_without_userinfo
  end

  # O `format: uri` + `pattern: ^https?://` do schema aceitam userinfo, e
  # "https://host-confiavel.com@host-do-atacante/" passa limpo -- o host real e o
  # segundo, mas a string comeca pelo primeiro. A lista de apps mostra a URL
  # truncada no fim (DashboardAppsRow), entao o host real e justamente a parte
  # que some, e quem audita depois ve so o prefixo confiavel.
  #
  # Nao e sobre limitar o admin, que ja pode cadastrar o host que quiser: e sobre
  # a URL nao poder mentir sobre qual host ela e. Pesa mais desde que o
  # `{user_token}` passou a viajar nessa URL (ver dashboardAppHelper.js).
  def validate_urls_without_userinfo
    self[:content].each do |item|
      uri = begin
        URI.parse(item['url'].to_s)
      rescue URI::InvalidURIError
        nil
      end

      errors.add(:content, ': URL must not contain userinfo') if uri&.userinfo.present?
    end
  end
end
