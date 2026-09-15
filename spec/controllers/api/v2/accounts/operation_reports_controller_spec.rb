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

  describe 'GET /api/v2/accounts/{account.id}/reports/ownership_summary' do
    let(:path) { "/api/v2/accounts/#{account.id}/reports/ownership_summary" }

    context 'when authenticated as an agent without report permission' do
      it 'returns unauthorized' do
        get path, params: window, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as an administrator' do
      it 'returns the current and the previous window' do
        get path, params: window, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.keys).to contain_exactly('current', 'previous')
        expect(response.parsed_body['current'].keys).to contain_exactly(
          'bot_resolutions', 'human_resolutions', 'bot_avg_resolution_seconds',
          'human_avg_resolution_seconds', 'human_avg_first_response_seconds', 'handoffs'
        )
      end

      it 'refuses a request without a time window' do
        get path, params: {}, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      # Janela aberta numa consulta pesada e convite para estourar o
      # statement_timeout. Este resumo ainda consulta o periodo anterior, entao
      # pesa o dobro do que o intervalo sugere.
      it 'refuses a window longer than six months' do
        get path,
            params: { since: 400.days.ago.to_i.to_s, until: Time.current.to_i.to_s },
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq(I18n.t('errors.reports.date_range_too_long'))
      end

      it 'accepts a window just inside the limit' do
        get path,
            params: { since: 100.days.ago.to_i.to_s, until: Time.current.to_i.to_s },
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'GET /api/v2/accounts/{account.id}/reports/supervisor' do
    let(:path) { "/api/v2/accounts/#{account.id}/reports/supervisor" }

    context 'when authenticated as an agent without report permission' do
      it 'returns unauthorized' do
        get path, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as an administrator' do
      before do
        # Presenca vem do Redis; sem stub o teste dependeria de estado externo.
        allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
      end

      it 'returns the five sections, without needing a time window' do
        get path, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.keys).to contain_exactly(
          'kpis', 'queue_by_team', 'conversations', 'agents', 'alerts'
        )
        expect(response.parsed_body['kpis'].keys).to contain_exactly(
          'in_progress', 'in_queue', 'in_queue_unfiltered', 'longest_wait_minutes',
          'longest_wait_window_days', 'stale_in_queue', 'agents_online', 'agents_total', 'avg_load'
        )
        expect(response.parsed_body['conversations'].keys).to contain_exactly('items', 'counts', 'pagination')
      end

      it 'accepts a team_id parameter' do
        team = create(:team, account: account)
        get path, params: { team_id: team.id }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
      end

      it 'accepts the three values of agent_type' do
        %w[all human bot].each do |agent_type|
          get path, params: { agent_type: agent_type }, headers: admin.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
        end
      end

      it 'ignores an agent_type it does not recognize instead of failing' do
        get path, params: { agent_type: 'alien' }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
      end

      it 'accepts the three values of status_filter' do
        %w[na_fila atendendo aguardando].each do |status_filter|
          get path, params: { status_filter: status_filter }, headers: admin.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
        end
      end

      it 'ignores a status_filter it does not recognize instead of failing' do
        get path, params: { status_filter: 'alien' }, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'GET /api/v2/accounts/{account.id}/reports/origem' do
    let(:path) { "/api/v2/accounts/#{account.id}/reports/origem" }

    context 'when authenticated as an agent without report permission' do
      it 'returns unauthorized' do
        get path, params: window, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as an administrator' do
      it 'returns the six sections' do
        get path, params: window, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.keys).to contain_exactly(
          'summary', 'daily_evolution', 'by_origin', 'by_team', 'by_inbox', 'by_agent'
        )
      end

      it 'refuses a request without a time window' do
        get path, params: {}, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'accepts team_id and agent_type' do
        team = create(:team, account: account)
        get path, params: window.merge(team_id: team.id, agent_type: 'human'),
                  headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
      end

      # `origem` nao esta na lista `except:` de `validate_time_window` -- este
      # teste trava esse fato, para uma futura mudanca na lista nao liberar a
      # acao do limite em silencio, sem nenhum teste denunciando.
      it 'refuses a window longer than six months' do
        get path,
            params: { since: 400.days.ago.to_i.to_s, until: Time.current.to_i.to_s },
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq(I18n.t('errors.reports.date_range_too_long'))
      end

      it 'accepts a window just inside the limit' do
        get path,
            params: { since: 100.days.ago.to_i.to_s, until: Time.current.to_i.to_s },
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'GET /api/v2/accounts/{account.id}/reports/fila_historico' do
    let(:path) { "/api/v2/accounts/#{account.id}/reports/fila_historico" }

    context 'when authenticated as an agent without report permission' do
      it 'returns unauthorized' do
        get path, params: window, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as an administrator' do
      it 'returns the five sections' do
        get path, params: window, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.keys).to contain_exactly(
          'kpis', 'daily_evolution', 'by_team', 'by_agent', 'capacity_vs_demand'
        )
      end

      it 'refuses a request without a time window' do
        get path, params: {}, headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'accepts team_id and agent_type' do
        team = create(:team, account: account)
        get path, params: window.merge(team_id: team.id, agent_type: 'human'),
                  headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
      end

      it 'refuses a window longer than six months' do
        get path,
            params: { since: 400.days.ago.to_i.to_s, until: Time.current.to_i.to_s },
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq(I18n.t('errors.reports.date_range_too_long'))
      end

      it 'accepts a window just inside the limit' do
        get path,
            params: { since: 100.days.ago.to_i.to_s, until: Time.current.to_i.to_s },
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
      end
    end
  end
end
