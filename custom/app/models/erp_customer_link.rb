class ErpCustomerLink < ApplicationRecord
  belongs_to :account
  belongs_to :contact

  PROVIDERS = %w[ixc].freeze
  STATUSES = %w[linked ambiguous not_found].freeze
  MATCH_METHODS = %w[document phone manual].freeze

  validates :erp_provider, inclusion: { in: PROVIDERS }
  validates :status, inclusion: { in: STATUSES }
  validates :match_method, inclusion: { in: MATCH_METHODS }, allow_nil: true
  validates :account_id, uniqueness: { scope: %i[contact_id erp_provider] }

  scope :by_provider, ->(p) { where(erp_provider: p) }
  scope :linked, -> { where(status: 'linked') }
  scope :ambiguous, -> { where(status: 'ambiguous') }
end
