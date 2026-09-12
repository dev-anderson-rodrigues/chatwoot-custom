require 'rails_helper'

RSpec.describe Api::V2::Accounts::OperationReportsController, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:window) { { since: 7.days.ago.to_i.to_s, until: Time.current.to_i.to_s } }

  describe 'GET /api/v2/accounts/{account.id}/reports/cockpit_atendentes' do
    let(:path) { "/api/v2/accounts/#{account.id}/reports/cockpit_atendentes" }

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get path, params: window

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as an agent without report permission' do
      it 'returns unauthorized' do
        get path, params: window, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      # A autorizacao roda antes da validacao: quem nao pode ver o relatorio nao
      # recebe dica nenhuma sobre o contrato.
      it 'returns unauthorized even with an invalid window' do
        get path, params: {}, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as an administrator' do
      before do
        # Presenca vem do Redis; sem stub o teste dependeria de estado externo.
        allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
      end

      it 'returns the kpis and one row per agent' do
        get path, params: window, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.keys).to contain_exactly('kpis', 'agents')
        expect(response.parsed_body['agents'].pluck('id')).to include(admin.id)
      end

      # Sem janela o builder filtrava 1970..1970 e a tela mostrava "nenhum dado"
      # para o que era um erro de contrato.
      {
        'without since' => ->(w) { w.except(:since) },
        'without until' => ->(w) { w.except(:until) },
        'with a non numeric since' => ->(w) { w.merge(since: 'ontem') },
        'with an empty window' => ->(w) { w.merge(until: w[:since]) },
        'with since after until' => ->(w) { w.merge(since: w[:until], until: w[:since]) }
      }.each do |description, change|
        it "returns unprocessable entity #{description}" do
          get path, params: change.call(window), headers: admin.create_new_auth_token, as: :json

          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body['error']).to eq(I18n.t('errors.reports.invalid_time_window'))
        end
      end
    end
  end
end
