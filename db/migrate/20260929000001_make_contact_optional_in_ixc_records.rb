class MakeContactOptionalInIxcRecords < ActiveRecord::Migration[7.0]
  def change
    change_column_null :ixc_promises, :contact_id, true
    change_column_null :ixc_attendances, :contact_id, true
  end
end
