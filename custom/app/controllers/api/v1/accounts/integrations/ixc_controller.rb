class Api::V1::Accounts::Integrations::IxcController < Api::V1::Accounts::Integrations::BaseController
  # GET /api/v1/accounts/:account_id/integrations/ixc/overdue_customers?page=1&per_page=50
  def overdue_customers
    hook = Integrations::Hook.find_by(account: Current.account, app_id: 'ixc')
    return render json: { error: 'IXC integration not configured.' }, status: :not_found unless hook

    client  = Erp::Ixc::Client.new(hook: hook)
    page    = (params[:page] || 1).to_i
    per_page = [(params[:per_page] || 50).to_i, 200].min

    result  = client.overdue_invoices_page(page: page, per_page: per_page)
    invoices = result[:records]

    customer_ids = invoices.map { |i| i['id_cliente'] }.uniq
    customers_by_id = fetch_customers_map(client, customer_ids)

    records = build_overdue_records(invoices, customers_by_id)

    render json: { records: records, total: result[:total], page: page, per_page: per_page }
  rescue Erp::Ixc::AuthenticationError
    render json: { error: 'IXC authentication failed.' }, status: :unauthorized
  rescue Erp::Ixc::TimeoutError
    render json: { error: 'IXC API timed out.' }, status: :service_unavailable
  rescue Erp::Ixc::RequestError => e
    render json: { error: e.message }, status: :bad_gateway
  end

  # GET /api/v1/accounts/:account_id/integrations/ixc/customer?contact_id=X[&inbox_id=Y]
  def customer
    contact = Current.account.contacts.find(params[:contact_id])
    hook    = resolve_hook(contact)
    return render json: { error: 'IXC integration not configured.' }, status: :not_found unless hook

    result = Erp::Ixc::ContactResolver.new(hook: hook, contact: contact).resolve
    result[:status] == 'linked' ? render_linked(result, hook) : render(json: result.slice(:status, :candidates))
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Contact not found.' }, status: :not_found
  rescue Erp::Ixc::AuthenticationError
    render json: { error: 'IXC authentication failed. Check the API token.' }, status: :unauthorized
  rescue Erp::Ixc::TimeoutError
    render json: { error: 'IXC API timed out.', status: 'error' }, status: :service_unavailable
  rescue Erp::Ixc::RequestError => e
    render json: { error: e.message, status: 'error' }, status: :bad_gateway
  end

  private

  def resolve_hook(contact)
    hooks = Integrations::Hook.where(account: Current.account, app_id: 'ixc')
    return nil if hooks.empty?

    hook_by_contact_filial(hooks, contact) ||
      hook_by_inbox_param(hooks) ||
      hooks.first
  end

  def hook_by_contact_filial(hooks, contact)
    filial_id = contact.custom_attributes&.dig('filial_id').to_s
    return nil if filial_id.blank?

    hooks.find { |h| h.settings['filial_id'].to_s == filial_id }
  end

  def hook_by_inbox_param(hooks)
    inbox_id = params[:inbox_id].to_s
    return nil if inbox_id.blank?

    id_match  = hooks.find { |h| h.settings['inbox_ids'].to_s.split(',').map(&:strip).include?(inbox_id) }
    id_match || hooks.find { |h| h.settings['inbox_ids'].blank? }
  end

  def fetch_customers_map(client, customer_ids)
    customer_ids.each_with_object({}) do |id, map|
      map[id.to_s] = client.get_customer(id) rescue nil
    end
  end

  def build_overdue_records(invoices, customers_by_id)
    grouped = invoices.group_by { |i| i['id_cliente'].to_s }
    grouped.map do |customer_id, inv_list|
      customer = customers_by_id[customer_id]
      next unless customer

      total_debt = inv_list.sum { |i| i['valor'].to_f }
      max_overdue = inv_list.map { |i| i['atraso'].to_i }.max

      {
        customer_id: customer_id,
        name: customer['razao'].presence || customer['nome'],
        cpf_cnpj: customer['cnpj_cpf'],
        phone: customer['telefone_celular'].presence || customer['fone'],
        email: customer['email'],
        max_overdue_days: max_overdue,
        open_invoices_count: inv_list.size,
        total_debt: total_debt.round(2),
        oldest_due_date: inv_list.map { |i| i['data_vencimento'] }.compact.sort.first
      }
    end.compact.sort_by { |r| -r[:max_overdue_days] }
  end

  def render_linked(result, hook)
    client = Erp::Ixc::Client.new(hook: hook)
    render json: {
      status: 'linked',
      customer: result[:customer],
      erp_customer_id: result[:erp_customer_id],
      invoices: client.get_invoices(result[:erp_customer_id]),
      contracts: client.get_contracts(result[:erp_customer_id])
    }
  end
end
