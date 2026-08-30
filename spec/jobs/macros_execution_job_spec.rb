require 'rails_helper'

RSpec.describe MacrosExecutionJob do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:macro) { create(:macro, account: account, visibility: :global, actions: []) }

  let(:my_inbox) { create(:inbox, account: account) }
  let(:other_inbox) { create(:inbox, account: account) }
  let!(:mine) { create(:conversation, account: account, inbox: my_inbox) }
  let!(:not_mine) { create(:conversation, account: account, inbox: other_inbox) }

  before { create(:inbox_member, user: agent, inbox: my_inbox) }

  def run(user, conversations)
    described_class.perform_now(macro, conversation_ids: conversations.map(&:display_id), user: user)
  end

  describe 'escopo das conversas' do
    # O endpoint de execute autoriza a MACRO, nao as conversas. Como macro
    # global e executavel por qualquer agente e pode disparar
    # send_webhook_event, mandar um display_id de outra inbox exfiltraria o
    # webhook_data dessa conversa.
    it 'skips conversations outside the agent inbox and team' do
      expect(Macros::ExecutionService).to receive(:new)
        .with(macro, mine, agent, {}).once.and_return(instance_double(Macros::ExecutionService, perform: true))

      run(agent, [mine, not_mine])
    end

    it 'includes a conversation reachable through the agent team' do
      team = create(:team, account: account)
      create(:team_member, team: team, user: agent)
      not_mine.update!(team: team)

      received = []
      allow(Macros::ExecutionService).to receive(:new) do |_m, conversation, _u, _i|
        received << conversation
        instance_double(Macros::ExecutionService, perform: true)
      end

      run(agent, [mine, not_mine])

      expect(received).to contain_exactly(mine, not_mine)
    end

    it 'lets an administrator run against every conversation in the account' do
      received = []
      allow(Macros::ExecutionService).to receive(:new) do |_m, conversation, _u, _i|
        received << conversation
        instance_double(Macros::ExecutionService, perform: true)
      end

      run(administrator, [mine, not_mine])

      expect(received).to contain_exactly(mine, not_mine)
    end

    it 'does nothing when no conversation is permitted' do
      expect(Macros::ExecutionService).not_to receive(:new)

      run(agent, [not_mine])
    end
  end

  describe 'isolamento de falha por conversa' do
    # Sem isolar, o job inteiro levanta, o Sidekiq reenfileira e as conversas
    # ja processadas rodam de novo -- reenviando mensagem e webhook.
    it 'keeps going when one conversation blows up, and does not re-raise' do
      other = create(:conversation, account: account, inbox: my_inbox)
      calls = 0

      allow(Macros::ExecutionService).to receive(:new) do
        calls += 1
        failing = calls == 1
        instance_double(Macros::ExecutionService).tap do |service|
          if failing
            allow(service).to receive(:perform).and_raise(StandardError, 'boom')
          else
            allow(service).to receive(:perform)
          end
        end
      end

      expect { run(agent, [mine, other]) }.not_to raise_error
      expect(calls).to eq(2)
    end
  end
end
