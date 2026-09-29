class CreateIxcContactRecords < ActiveRecord::Migration[7.0]
  def change
    create_table :ixc_promises do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.string :erp_customer_id, null: false
      t.date :promised_date, null: false
      t.decimal :amount, precision: 10, scale: 2
      t.integer :created_by
      t.timestamps
    end

    add_index :ixc_promises, %i[account_id contact_id erp_customer_id],
              name: 'idx_ixc_promises_account_contact_customer'

    create_table :ixc_attendances do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.string :erp_customer_id, null: false
      t.string :canal
      t.string :resultado
      t.text :descricao
      t.integer :created_by
      t.timestamps
    end

    add_index :ixc_attendances, %i[account_id contact_id erp_customer_id],
              name: 'idx_ixc_attendances_account_contact_customer'
  end
end
