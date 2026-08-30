class AddInputFieldsToMacros < ActiveRecord::Migration[7.1]
  def change
    add_column :macros, :input_fields, :jsonb, default: [], null: false
  end
end
