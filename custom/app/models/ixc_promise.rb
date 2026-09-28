class IxcPromise < ApplicationRecord
  belongs_to :account
  belongs_to :contact

  validates :erp_customer_id, presence: true
  validates :promised_date, presence: true

  scope :active, -> { where(deleted_at: nil) }
end
