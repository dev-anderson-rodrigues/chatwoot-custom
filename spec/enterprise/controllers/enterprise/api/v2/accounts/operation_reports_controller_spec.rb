# frozen_string_literal: true

require 'rails_helper'

# O OperationReportsController reusa `authorize :report, :view?`, e e o
# Enterprise::ReportPolicy que abre o relatorio para papel customizado com
# report_manage. Este spec trava que a tela do cockpit segue essa regra e nao
# vira coisa so de administrador.
RSpec.describe 'Enterprise operation reports API', type: :request do
  let(:account) { create(:account) }
  let(:path) { "/api/v2/accounts/#{account.id}/reports/cockpit_atendentes" }
  let(:window) { { since: 7.days.ago.to_i.to_s, until: Time.current.to_i.to_s } }

  def agent_with_permissions(permissions)
    role = create(:custom_role, account: account, permissions: permissions)
    create(:user).tap do |user|
      create(:account_user, user: user, account: account, role: :agent, custom_role: role)
    end
  end

  before do
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
  end

  describe 'GET /api/v2/accounts/:account_id/reports/cockpit_atendentes' do
    it 'lets an agent whose custom role grants report_manage read the cockpit' do
      user = agent_with_permissions(['report_manage'])

      get path, params: window, headers: user.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'keeps out an agent whose custom role does not grant report_manage' do
      user = agent_with_permissions(['conversation_manage'])

      get path, params: window, headers: user.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
