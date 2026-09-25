class Api::V1::Accounts::Integrations::IxcController < Api::V1::Accounts::Integrations::BaseController
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
