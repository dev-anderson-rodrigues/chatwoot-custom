class AddFieldsToIxcContactRecords < ActiveRecord::Migration[7.0]
  def change
    add_column :ixc_promises, :observacao, :text
    add_column :ixc_promises, :deleted_at, :datetime
    add_column :ixc_promises, :deleted_by, :integer

    add_column :ixc_attendances, :deleted_at, :datetime
    add_column :ixc_attendances, :deleted_by, :integer
  end
end
