class RemoveEmailUniquenessFromContacts < ActiveRecord::Migration[7.2]
  # [FORK] Permite múltiplos contatos com o mesmo e-mail na mesma conta.
  # Caso de uso: membros da mesma família em provedores de internet compartilham e-mail.
  # A validação Rails também foi removida em app/models/contact.rb.
  def change
    remove_index :contacts, name: :uniq_email_per_account_contact
  end
end
