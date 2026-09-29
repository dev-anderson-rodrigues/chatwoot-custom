class IxcAttendance < ApplicationRecord
  belongs_to :account
  belongs_to :contact, optional: true

  validates :erp_customer_id, presence: true

  scope :active, -> { where(deleted_at: nil) }
end
