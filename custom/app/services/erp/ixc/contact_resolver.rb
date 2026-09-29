class Erp::Ixc::ContactResolver
  def initialize(hook:, contact:)
    @hook    = hook
    @contact = contact
    @client  = Erp::Ixc::Client.new(hook: hook)
  end

  # Retorna hash com :status ('linked' | 'ambiguous' | 'not_found') e dados relevantes.
  def resolve
    link = existing_link
    return cached_result(link) if link&.status == 'linked'

    customers = find_candidates
    persist_link(customers)
    build_result(customers)
  end

  private

  def existing_link
    ErpCustomerLink.find_by(
      account: @hook.account,
      contact: @contact,
      erp_provider: 'ixc'
    )
  end

  def cached_result(link)
    customer = @client.get_customer(link.erp_customer_id)
    { status: 'linked', customer: customer, erp_customer_id: link.erp_customer_id }
  end

  def find_candidates
    doc = contact_document
    if doc.present?
      results = @client.search_by_document(doc)
      return results if results.any?
    end

    phone = @contact.phone_number.presence
    return [] if phone.blank?

    @client.search_by_phone(phone)
  end

  def contact_document
    attrs = (@contact.custom_attributes || {}).with_indifferent_access
    (attrs[:cpf_cnpj] || attrs[:cnpj_cpf] || attrs[:cpf] || attrs[:cnpj]).to_s.presence
  end

  def persist_link(customers)
    link = ErpCustomerLink.find_or_initialize_by(
      account_id: @hook.account_id,
      contact_id: @contact.id,
      erp_provider: 'ixc'
    )
    apply_link_status(link, customers)
    link.save
  end

  def apply_link_status(link, customers)
    if customers.size == 1
      assign_linked(link, customers.first)
    elsif customers.size > 1
      link.assign_attributes(status: 'ambiguous', erp_customer_id: nil, match_method: nil)
    else
      link.assign_attributes(status: 'not_found', erp_customer_id: nil, match_method: nil)
    end
  end

  def assign_linked(link, customer)
    link.status          = 'linked'
    link.erp_customer_id = customer['id'].to_s
    link.document        = customer['cnpj_cpf'].to_s.gsub(/\D/, '').presence
    link.match_method    = contact_document.present? ? 'document' : 'phone'
  end

  def build_result(customers)
    case customers.size
    when 1
      c = customers.first
      { status: 'linked', customer: c, erp_customer_id: c['id'].to_s }
    when 0
      { status: 'not_found' }
    else
      { status: 'ambiguous', candidates: customers }
    end
  end
end
