class Erp::Ixc::CustomerSyncService
  PER_PAGE = 100

  def initialize(hook:)
    @hook      = hook
    @account   = hook.account
    @client    = Erp::Ixc::Client.new(hook: hook)
    @filial_id = hook.settings['filial_id'].to_s.presence
  end

  # Importa clientes do IXC que ainda não têm vínculo neste account.
  # Cada ID único do IXC gera um contato independente no Chatwoot.
  def sync_missing
    page = 1
    loop do
      result = @client.customers_page(page: page, per_page: PER_PAGE)
      records = Array(result[:records])
      process_page(records)
      break if records.empty? || (page * PER_PAGE) >= result[:total]

      page += 1
    end
  end

  private

  def process_page(customers)
    customers.each { |c| sync_customer(c) }
  end

  def sync_customer(customer)
    ixc_id = customer['id'].to_s.presence
    return if ixc_id.nil?
    return if ErpCustomerLink.exists?(account: @account, erp_provider: 'ixc', erp_customer_id: ixc_id)

    create_contact_with_link(ixc_id, customer)
  rescue Erp::Ixc::Error => e
    Rails.logger.error("[IXC sync] account=#{@account.id} customer=#{ixc_id}: IXC error: #{e.message}")
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[IXC sync] account=#{@account.id} customer=#{ixc_id}: validation: #{e.message}")
  rescue ActiveRecord::RecordNotUnique
    # race condition: outro job criou o link entre o exists? e o create! — ignorar
    Rails.logger.info("[IXC sync] account=#{@account.id} customer=#{ixc_id}: duplicate skipped (race condition)")
  rescue StandardError => e
    Rails.logger.error("[IXC sync] account=#{@account.id} customer=#{ixc_id}: #{e.class} #{e.message}")
  end

  def create_contact_with_link(ixc_id, customer)
    ActiveRecord::Base.transaction do
      contact = build_contact(customer)
      contact.save!
      ErpCustomerLink.create!(
        account: @account,
        contact: contact,
        erp_provider: 'ixc',
        erp_customer_id: ixc_id,
        document: normalize_doc(customer['cnpj_cpf']),
        status: 'linked',
        match_method: 'manual'
      )
    end
  end

  def build_contact(customer)
    @account.contacts.new(
      name: customer['razao'].presence || customer['nome'].presence || "IXC ##{customer['id']}",
      phone_number: normalize_phone(customer['telefone_celular'].presence || customer['fone']),
      email: customer['email'].presence,
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
