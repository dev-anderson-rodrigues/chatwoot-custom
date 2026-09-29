class CreateErpCustomerLinks < ActiveRecord::Migration[7.0]
  def change
    create_table :erp_customer_links do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.string :erp_provider, null: false, default: 'ixc'
      t.string :erp_customer_id
      t.string :document
      t.string :match_method
      t.string :status, null: false, default: 'not_found'
      t.integer :confirmed_by
      t.datetime :confirmed_at
      t.timestamps
    end

    add_index :erp_customer_links, %i[account_id contact_id erp_provider],
              unique: true, name: 'idx_erp_links_account_contact_provider'
    add_index :erp_customer_links, %i[account_id erp_provider erp_customer_id],
              name: 'idx_erp_links_account_provider_customer'
    add_index :erp_customer_links, %i[account_id erp_provider document],
              name: 'idx_erp_links_account_provider_document'
  end
end
