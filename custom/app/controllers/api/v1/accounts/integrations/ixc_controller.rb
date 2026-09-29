class Api::V1::Accounts::Integrations::IxcController < Api::V1::Accounts::Integrations::BaseController
  # GET /api/v1/accounts/:account_id/integrations/ixc/overdue_customers
  def overdue_customers
    hook = Integrations::Hook.find_by(account: Current.account, app_id: 'ixc')
    return render json: { error: 'IXC integration not configured.' }, status: :not_found unless hook

    client   = Erp::Ixc::Client.new(hook: hook)
    invoices = client.current_month_overdue_invoices

    customer_ids    = invoices.map { |i| i['id_cliente'] }.uniq
    customers_by_id = fetch_customers_map(client, customer_ids)
    records         = build_overdue_records(invoices, customers_by_id)

    render json: { records: records, total: records.size }
  rescue Erp::Ixc::AuthenticationError
    render json: { error: 'IXC authentication failed.' }, status: :unauthorized
  rescue Erp::Ixc::TimeoutError
    render json: { error: 'IXC API timed out.' }, status: :service_unavailable
  rescue Erp::Ixc::RequestError => e
    render json: { error: e.message }, status: :bad_gateway
  end

  # GET /api/v1/accounts/:account_id/integrations/ixc/customer_details?erp_customer_id=X
  def customer_details
    hook = Integrations::Hook.find_by(account: Current.account, app_id: 'ixc')
    return render json: { error: 'IXC integration not configured.' }, status: :not_found unless hook

    erp_id = params[:erp_customer_id].to_s
    return render json: { error: 'erp_customer_id required.' }, status: :unprocessable_entity if erp_id.blank?

    client   = Erp::Ixc::Client.new(hook: hook)
    customer = client.get_customer(erp_id)
    invoices = client.get_invoices(erp_id, status: 'A')

    render json: { customer: customer, invoices: invoices }
  rescue Erp::Ixc::AuthenticationError
    render json: { error: 'IXC authentication failed.' }, status: :unauthorized
  rescue Erp::Ixc::TimeoutError
    render json: { error: 'IXC API timed out.' }, status: :service_unavailable
  rescue Erp::Ixc::RequestError => e
    render json: { error: e.message }, status: :bad_gateway
  end

  # GET /api/v1/accounts/:account_id/integrations/ixc/promises?erp_customer_id=Y[&contact_id=X]
  def promises
    scope = IxcPromise.active.where(account: Current.account, erp_customer_id: params[:erp_customer_id])
    scope = scope.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    render json: scope.order(created_at: :desc).map { |p| serialize_promise(p) }
  end

  # POST /api/v1/accounts/:account_id/integrations/ixc/promises
  def create_promise
    contact_id = resolve_contact_id
    promise = IxcPromise.create!(
      account: Current.account,
      contact_id: contact_id,
      erp_customer_id: params[:erp_customer_id],
      promised_date: params[:promised_date],
      amount: params[:amount].presence,
      observacao: params[:observacao].presence,
      created_by: current_user.id
    )
    render json: serialize_promise(promise), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # DELETE /api/v1/accounts/:account_id/integrations/ixc/promises/:id
  def destroy_promise
    promise = IxcPromise.active.find_by!(account: Current.account, id: params[:id])
    unless promise.created_by == current_user.id
      return render json: { error: 'Você só pode excluir registros criados por você.' }, status: :forbidden
    end

    promise.update!(deleted_at: Time.current, deleted_by: current_user.id)
    render json: { ok: true }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Record not found.' }, status: :not_found
  end

  # GET /api/v1/accounts/:account_id/integrations/ixc/attendances?erp_customer_id=Y[&contact_id=X]
  def attendances
    scope = IxcAttendance.active.where(account: Current.account, erp_customer_id: params[:erp_customer_id])
    scope = scope.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    render json: scope.order(created_at: :desc).map { |a| serialize_attendance(a) }
  end

  # POST /api/v1/accounts/:account_id/integrations/ixc/attendances
  def create_attendance
    contact_id = resolve_contact_id
    attendance = IxcAttendance.create!(
      account: Current.account,
      contact_id: contact_id,
      erp_customer_id: params[:erp_customer_id],
      canal: params[:canal],
      resultado: params[:resultado],
      descricao: params[:descricao],
      created_by: current_user.id
    )
    render json: serialize_attendance(attendance), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # DELETE /api/v1/accounts/:account_id/integrations/ixc/attendances/:id
  def destroy_attendance
    attendance = IxcAttendance.active.find_by!(account: Current.account, id: params[:id])
    unless attendance.created_by == current_user.id
      return render json: { error: 'Você só pode excluir registros criados por você.' }, status: :forbidden
    end

    attendance.update!(deleted_at: Time.current, deleted_by: current_user.id)
    render json: { ok: true }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Record not found.' }, status: :not_found
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

  def resolve_contact_id
    id = params[:contact_id].presence
    return nil unless id

    Current.account.contacts.find(id).id
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def serialize_promise(p)
    {
      id: p.id,
      promised_date: p.promised_date,
      amount: p.amount,
      observacao: p.observacao,
      created_at: p.created_at,
      created_by_name: user_name(p.created_by)
    }
  end

  def serialize_attendance(a)
    {
      id: a.id,
      canal: a.canal,
      resultado: a.resultado,
      descricao: a.descricao,
      created_at: a.created_at,
      created_by_name: user_name(a.created_by)
    }
  end

  def user_name(user_id)
    return nil if user_id.blank?

    User.find_by(id: user_id)&.name
  end

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
    client.get_customers_by_ids(customer_ids)
  end

  def build_overdue_records(invoices, customers_by_id)
    today = Date.today
    grouped = invoices.group_by { |i| i['id_cliente'].to_s }
    grouped.map do |customer_id, inv_list|
      customer = customers_by_id[customer_id]
      next unless customer

      total_debt = inv_list.sum { |i| i['valor'].to_f }
      max_overdue = inv_list.map do |i|
        due = Date.parse(i['data_vencimento']) rescue nil
        due ? (today - due).to_i : 0
      end.max

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
