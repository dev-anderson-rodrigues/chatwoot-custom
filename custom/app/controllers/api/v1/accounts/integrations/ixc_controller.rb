class Api::V1::Accounts::Integrations::IxcController < Api::V1::Accounts::Integrations::BaseController
  before_action :fetch_hook
  before_action :validate_contact, only: [:customer]

  # GET /api/v1/accounts/:account_id/integrations/ixc/customer?contact_id=X
  # Retorna dados do cliente no IXC vinculado ao contato: faturas em aberto e contratos.
  def customer
    resolver = Erp::Ixc::ContactResolver.new(hook: @hook, contact: @contact)
    result   = resolver.resolve

    if result[:status] == 'linked'
      client    = Erp::Ixc::Client.new(hook: @hook)
      invoices  = client.get_invoices(result[:erp_customer_id])
      contracts = client.get_contracts(result[:erp_customer_id])

      render json: {
        status:          'linked',
        customer:        result[:customer],
        erp_customer_id: result[:erp_customer_id],
        invoices:        invoices,
        contracts:       contracts
      }
    else
      render json: result.slice(:status, :candidates)
    end
  rescue Erp::Ixc::AuthenticationError
    render json: { error: 'IXC authentication failed. Check the API token.' }, status: :unauthorized
  rescue Erp::Ixc::TimeoutError
    render json: { error: 'IXC API timed out.', status: 'error' }, status: :service_unavailable
  rescue Erp::Ixc::RequestError => e
    render json: { error: e.message, status: 'error' }, status: :bad_gateway
  end

  private

  def fetch_hook
    @hook = Integrations::Hook.find_by!(account: Current.account, app_id: 'ixc')
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'IXC integration not configured.' }, status: :not_found
  end

  def validate_contact
    @contact = Current.account.contacts.find(params[:contact_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Contact not found.' }, status: :not_found
  end
end
