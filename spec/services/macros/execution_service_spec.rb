require 'rails_helper'

RSpec.describe Macros::ExecutionService, type: :service do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:user) { create(:user, account: account) }
  let(:macro) { create(:macro, account: account) }
  let(:service) { described_class.new(macro, conversation, user) }

  before do
    create(:inbox_member, user: user, inbox: conversation.inbox)
    # send_webhook_event agora passa pelo guarda de SSRF, que resolve DNS de
    # verdade. Stubado aqui para o teste nao depender de rede -- a politica do
    # guarda em si e coberta em spec/services/macros/safe_url_spec.rb.
    allow(Macros::SafeUrl).to receive(:public_http?).and_return(true)
  end

  describe '#perform' do
    context 'when actions are present' do
      before do
        allow(macro).to receive(:actions).and_return([
                                                       { action_name: 'assign_agent', action_params: ['self'] },
                                                       { action_name: 'add_private_note', action_params: ['Test note'] },
                                                       { action_name: 'send_message', action_params: ['Test message'] },
                                                       { action_name: 'send_attachment', action_params: [1, 2] },
                                                       { action_name: 'send_webhook_event', action_params: ['https://example.com/webhook'] }
                                                     ])
      end

      it 'executes the actions' do
        expect(service).to receive(:assign_agent).with(['self']).and_call_original
        expect(service).to receive(:add_private_note).with(['Test note']).and_call_original
        expect(service).to receive(:send_message).with(['Test message']).and_call_original
        expect(service).to receive(:send_attachment).with([1, 2]).and_call_original

        service.perform
      end

      context 'when an action raises an error' do
        let(:exception_tracker) { instance_spy(ChatwootExceptionTracker) }

        before do
          allow(ChatwootExceptionTracker).to receive(:new).and_return(exception_tracker)
        end

        it 'captures the exception' do
          allow(service).to receive(:assign_agent).and_raise(StandardError.new('Random error'))
          expect(exception_tracker).to receive(:capture_exception)

          service.perform
        end
      end
    end
  end

  describe '#assign_team' do
    let(:team) { create(:team, account: account, allow_auto_assign: false) }

    context 'when team_id is nil' do
      it 'unassigns the team from the conversation' do
        conversation.update!(team_id: team.id)
        service.send(:assign_team, ['nil'])
        expect(conversation.reload.team).to be_nil
      end
    end
  end

  describe '#assign_agent' do
    context 'when agent_ids contains self' do
      it 'updates the conversation assignee to the current user' do
        service.send(:assign_agent, ['self'])
        expect(conversation.reload.assignee).to eq(user)
      end
    end

    context 'when agent_ids does not contain self' do
      let(:other_user) { create(:user, account: account) }

      before do
        create(:inbox_member, user: other_user, inbox: conversation.inbox)
      end

      it 'calls the super method' do
        service.send(:assign_agent, [other_user.id])
        expect(conversation.reload.assignee).to eq(other_user)
      end
    end

    context 'when agent_ids contains nil' do
      it 'unassigns the conversation' do
        conversation.update!(assignee: user)
        service.send(:assign_agent, ['nil'])
        expect(conversation.reload.assignee).to be_nil
      end
    end
  end

  describe '#add_private_note' do
    context 'when conversation is not a tweet' do
      it 'creates a new private message' do
        expect do
          service.send(:add_private_note, ['Test private note'])
        end.to change(Message, :count).by(1)

        message = Message.last
        expect(message.content).to eq('Test private note')
        expect(message.private).to be(true)
      end
    end

    context 'when conversation is a tweet' do
      before { allow(service).to receive(:conversation_a_tweet?).and_return(true) }

      it 'does not create a new message' do
        expect do
          service.send(:add_private_note, ['Test private note'])
        end.not_to change(Message, :count)
      end
    end
  end

  describe '#send_message' do
    context 'when conversation is not a tweet' do
      it 'creates a new public message' do
        expect do
          service.send(:send_message, ['Test message'])
        end.to change(Message, :count).by(1)

        message = Message.last
        expect(message.content).to eq('Test message')
        expect(message.private).to be(false)
      end
    end

    context 'when conversation is a tweet' do
      before { allow(service).to receive(:conversation_a_tweet?).and_return(true) }

      it 'does not create a new message' do
        expect do
          service.send(:send_message, ['Test message'])
        end.not_to change(Message, :count)
      end
    end
  end

  describe '#send_attachment' do
    before do
      macro.files.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
      macro.save!
    end

    context 'when conversation is not a tweet and macro has files attached' do
      before { allow(service).to receive(:conversation_a_tweet?).and_return(false) }

      it 'creates a new message with attachments' do
        expect do
          service.send(:send_attachment, [macro.files.first.blob_id])
        end.to change(Message, :count).by(1)

        message = Message.last
        expect(message.attachments).to be_present
      end
    end

    context 'when conversation is a tweet or macro has no files attached' do
      before { allow(service).to receive(:conversation_a_tweet?).and_return(true) }

      it 'does not create a new message' do
        expect do
          service.send(:send_attachment, [macro.files.first.blob_id])
        end.not_to change(Message, :count)
      end
    end
  end

  describe '#send_webhook_event' do
    it 'sends a webhook event' do
      expect(WebhookJob).to receive(:perform_later)
      service.send(:send_webhook_event, ['https://example.com/webhook'])
    end

    it 'refuses a url that the SSRF guard rejects' do
      allow(Macros::SafeUrl).to receive(:public_http?).and_return(false)
      expect(WebhookJob).not_to receive(:perform_later)

      expect { service.send(:send_webhook_event, ['http://169.254.169.254/latest/meta-data/']) }
        .to raise_error(ArgumentError, /Unsafe webhook URL/)
    end

    it 'checks the url after the variable substitution, not before' do
      service = described_class.new(macro, conversation, user, { 'host' => '169.254.169.254' })
      allow(Macros::SafeUrl).to receive(:public_http?).and_return(true)

      expect(WebhookJob).to receive(:perform_later).with('http://169.254.169.254/x', anything)
      allow(macro).to receive(:actions).and_return(
        [{ action_name: 'send_webhook_event', action_params: ['http://{{host}}/x'] }]
      )

      service.perform
      expect(Macros::SafeUrl).to have_received(:public_http?).with('http://169.254.169.254/x')
    end
  end

  describe 'execution audit record' do
    let(:service) { described_class.new(macro, conversation, user, { 'nome' => 'Ana' }) }

    it 'records a successful run' do
      allow(macro).to receive(:actions).and_return(
        [{ action_name: 'add_private_note', action_params: ['Ola {{nome}}'] }]
      )

      expect { service.perform }.to change(MacroExecution, :count).by(1)

      execution = MacroExecution.last
      expect(execution).to have_attributes(
        macro_id: macro.id, conversation_id: conversation.id, user_id: user.id,
        status: 'success', actions_run: 1, actions_total: 1, inputs: { 'nome' => 'Ana' }
      )
      expect(execution.error_message).to be_nil
    end

    it 'substitutes the input into the action params' do
      allow(macro).to receive(:actions).and_return(
        [{ action_name: 'add_private_note', action_params: ['Ola {{nome}}'] }]
      )

      service.perform

      expect(conversation.messages.last.content).to eq('Ola Ana')
    end

    it 'records partial when one action fails and another succeeds' do
      allow(macro).to receive(:actions).and_return([
                                                     { action_name: 'add_private_note', action_params: ['ok'] },
                                                     { action_name: 'send_webhook_event', action_params: ['http://blocked/x'] }
                                                   ])
      allow(Macros::SafeUrl).to receive(:public_http?).and_return(false)

      service.perform

      execution = MacroExecution.last
      expect(execution.status).to eq('partial')
      expect(execution.actions_run).to eq(1)
      expect(execution.error_message).to include('send_webhook_event')
    end

    it 'records failed when no action runs' do
      allow(macro).to receive(:actions).and_return(
        [{ action_name: 'send_webhook_event', action_params: ['http://blocked/x'] }]
      )
      allow(Macros::SafeUrl).to receive(:public_http?).and_return(false)

      service.perform

      expect(MacroExecution.last).to have_attributes(status: 'failed', actions_run: 0)
    end

    # Regressao do "Blocker 1": macro sem input_fields estourava RecordInvalid
    # dentro do job e nenhuma acao rodava, em silencio.
    it 'runs a macro that has no inputs at all' do
      service = described_class.new(macro, conversation, user)
      allow(macro).to receive(:actions).and_return(
        [{ action_name: 'add_private_note', action_params: ['sem inputs'] }]
      )

      expect { service.perform }.not_to raise_error
      expect(MacroExecution.last).to have_attributes(status: 'success', inputs: {})
    end
  end
end
