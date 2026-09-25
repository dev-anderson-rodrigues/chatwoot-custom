class Erp::Ixc::CustomerSyncService
  PER_PAGE = 100

  def initialize(hook:)
    @hook      = hook
    @account   = hook.account
    @client    = Erp::Ixc::Client.new(hook: hook)
    @filial_id = hook.settings['filial_id'].to_s.presence
  end

  # Importa clientes do IXC que ainda não têm vínculo neste account/hook.
  # Cada ID único do IXC gera um contato independente no Chatwoot.
  def sync_missing
    page = 1
    loop do
      result = @client.customers_page(page: page, per_page: PER_PAGE)
      process_page(result[:records])
      break if result[:records].empty? || (page * PER_PAGE) >= result[:total]

      page += 1
    end
  end

  private

  def process_page(customers)
    customers.each { |c| sync_customer(c) }
  end

  def sync_customer(customer)
    ixc_id = customer['id'].to_s
    return if ErpCustomerLink.exists?(account: @account, erp_provider: 'ixc', erp_customer_id: ixc_id)

    contact = build_contact(customer)
    return unless contact.save

    ErpCustomerLink.create!(
      account: @account,
      contact: contact,
      erp_provider: 'ixc',
      erp_customer_id: ixc_id,
      document: normalize_doc(customer['cnpj_cpf']),
      status: 'linked',
      match_method: 'manual'
    )
  rescue StandardError => e
    Rails.logger.error("[IXC sync] customer #{customer['id']}: #{e.message}")
  end

  def build_contact(customer)
    phone = normalize_phone(customer['telefone_celular'].presence || customer['fone'])
    email = customer['email'].presence

    @account.contacts.new(
      name: customer['razao'].presence || customer['nome'].presence || "IXC ##{customer['id']}",
      phone_number: phone,
      email: email,
      custom_attributes: build_custom_attrs(customer)
    )
  end

  def build_custom_attrs(customer)
    attrs = {}
    doc = normalize_doc(customer['cnpj_cpf'])
    attrs['cpf_cnpj']  = doc if doc.present?
    attrs['filial_id'] = @filial_id if @filial_id.present?
    attrs
  end

  def normalize_phone(phone)
    return nil if phone.blank?

    digits = phone.to_s.gsub(/\D/, '')
    return nil if digits.length < 8

    "+55#{digits.last(11)}"
  end

  def normalize_doc(doc)
    cleaned = doc.to_s.gsub(/\D/, '')
    cleaned.presence
  end
end
