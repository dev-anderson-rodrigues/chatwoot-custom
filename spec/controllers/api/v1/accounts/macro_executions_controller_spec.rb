require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::MacroExecutionsController', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:macro) { create(:macro, account: account, created_by: administrator, updated_by: administrator, visibility: :global) }

  describe 'GET /api/v1/accounts/{account.id}/macros/{macro.id}/executions' do
    let!(:executions) do
      [
        create(:macro_execution, account: account, macro: macro, user: agent, status: :success, created_at: 3.days.ago),
        create(:macro_execution, account: account, macro: macro, user: administrator, status: :failed, created_at: 2.days.ago),
        create(:macro_execution, account: account, macro: macro, user: agent, status: :partial, created_at: 1.day.ago)
      ]
    end

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/macros/#{macro.id}/executions"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns the executions newest first with a total' do
        get "/api/v1/accounts/#{account.id}/macros/#{macro.id}/executions",
            headers: administrator.create_new_auth_token

        expect(response).to have_http_status(:success)
        body = response.parsed_body

        expect(body['meta']['total']).to eq(3)
        expect(body['payload'].map { |e| e['id'] }).to eq(executions.reverse.map(&:id))
      end

      it 'exposes the audit fields' do
        get "/api/v1/accounts/#{account.id}/macros/#{macro.id}/executions",
            headers: administrator.create_new_auth_token

        entry = response.parsed_body['payload'].last
        expect(entry).to include('status' => 'success', 'actions_run' => 0, 'actions_total' => 0)
        expect(entry['user']['id']).to eq(agent.id)
      end

      it 'filters by status' do
        get "/api/v1/accounts/#{account.id}/macros/#{macro.id}/executions",
            params: { status: 'failed' }, headers: administrator.create_new_auth_token

        payload = response.parsed_body['payload']
        expect(payload.length).to eq(1)
        expect(payload.first['status']).to eq('failed')
      end

      it 'filters by user' do
        get "/api/v1/accounts/#{account.id}/macros/#{macro.id}/executions",
            params: { user_id: agent.id }, headers: administrator.create_new_auth_token

        expect(response.parsed_body['payload'].length).to eq(2)
      end

      it 'filters by date range' do
        get "/api/v1/accounts/#{account.id}/macros/#{macro.id}/executions",
            params: { from: 36.hours.ago.iso8601 }, headers: administrator.create_new_auth_token

        expect(response.parsed_body['payload'].length).to eq(1)
      end

      # Data invalida nao pode virar filtro degenerado e devolver lista errada.
      it 'ignores an unparseable date instead of returning the wrong list' do
        get "/api/v1/accounts/#{account.id}/macros/#{macro.id}/executions",
            params: { from: 'ontem de manha' }, headers: administrator.create_new_auth_token

        expect(response.parsed_body['payload'].length).to eq(3)
      end

      it 'paginates and caps the page size' do
        get "/api/v1/accounts/#{account.id}/macros/#{macro.id}/executions",
            params: { limit: 2, offset: 1 }, headers: administrator.create_new_auth_token

        body = response.parsed_body
        expect(body['payload'].length).to eq(2)
        # total ignora a paginacao
        expect(body['meta']['total']).to eq(3)
      end

      it 'does not let limit exceed the maximum' do
        create_list(:macro_execution, 60, account: account, macro: macro)

        get "/api/v1/accounts/#{account.id}/macros/#{macro.id}/executions",
            params: { limit: 500 }, headers: administrator.create_new_auth_token

        expect(response.parsed_body['payload'].length).to eq(50)
      end
    end

    context 'when the macro belongs to another account' do
      let(:foreign_macro) { create(:macro, account: other_account, visibility: :global) }

      it 'returns not found' do
        get "/api/v1/accounts/#{account.id}/macros/#{foreign_macro.id}/executions",
            headers: administrator.create_new_auth_token

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when the macro is personal and belongs to someone else' do
      let(:private_macro) { create(:macro, account: account, created_by: administrator, updated_by: administrator, visibility: :personal) }

      it 'is denied to another agent' do
        get "/api/v1/accounts/#{account.id}/macros/#{private_macro.id}/executions",
            headers: agent.create_new_auth_token

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # Macro global e visivel por qualquer agente, mas o historico dela carrega os
  # inputs (CPF/CNPJ digitado por colegas) e o display_id da conversa. Isso nao
  # pode furar a fronteira de inbox/time que a ConversationPolicy protege no
  # resto do app.
  describe 'escopo de visibilidade do historico' do
    let(:my_inbox) { create(:inbox, account: account) }
    let(:other_inbox) { create(:inbox, account: account) }
    let(:mine) { create(:conversation, account: account, inbox: my_inbox) }
    let(:not_mine) { create(:conversation, account: account, inbox: other_inbox) }

    before do
      create(:inbox_member, user: agent, inbox: my_inbox)
      create(:macro_execution, account: account, macro: macro, conversation: mine, inputs: { 'cpf' => 'meu' })
      create(:macro_execution, account: account, macro: macro, conversation: not_mine, inputs: { 'cpf' => 'alheio' })
    end

    def cpfs_for(user)
      get "/api/v1/accounts/#{account.id}/macros/#{macro.id}/executions", headers: user.create_new_auth_token
      response.parsed_body['payload'].map { |e| e['inputs']['cpf'] }
    end

    it 'hides the execution from an inbox the agent cannot access' do
      expect(cpfs_for(agent)).to contain_exactly('meu')
      expect(response.parsed_body['meta']['total']).to eq(1)
    end

    it 'returns 404 when fetching that execution directly' do
      hidden = MacroExecution.find_by(conversation: not_mine)

      get "/api/v1/accounts/#{account.id}/macros/#{macro.id}/executions/#{hidden.id}",
          headers: agent.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end

    it 'keeps executions with no conversation visible' do
      create(:macro_execution, account: account, macro: macro, conversation: nil, inputs: { 'cpf' => 'sem conversa' })

      expect(cpfs_for(agent)).to contain_exactly('meu', 'sem conversa')
    end

    it 'reaches a conversation through the agent team' do
      team = create(:team, account: account)
      create(:team_member, team: team, user: agent)
      not_mine.update!(team: team)

      expect(cpfs_for(agent)).to contain_exactly('meu', 'alheio')
    end

    it 'shows everything to an administrator' do
      expect(cpfs_for(administrator)).to contain_exactly('meu', 'alheio')
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/macros/{macro.id}/executions/{id}' do
    let(:execution) { create(:macro_execution, account: account, macro: macro, user: agent, inputs: { 'cpf' => '123' }) }

    it 'returns the execution' do
      get "/api/v1/accounts/#{account.id}/macros/#{macro.id}/executions/#{execution.id}",
          headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('id' => execution.id, 'inputs' => { 'cpf' => '123' })
    end

    it 'does not leak an execution from another macro' do
      other_macro = create(:macro, account: account, created_by: administrator, updated_by: administrator, visibility: :global)

      get "/api/v1/accounts/#{account.id}/macros/#{other_macro.id}/executions/#{execution.id}",
          headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end
  end
end
