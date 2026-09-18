require 'rails_helper'

RSpec.describe MacroExecution do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:macro) { create(:macro, account: account, created_by: admin, updated_by: admin, actions: []) }

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:macro) }
    it { is_expected.to belong_to(:user).optional }
    it { is_expected.to belong_to(:conversation).optional }
  end

  describe 'validations' do
    # Regressao: `inputs` era validado com presence: true, mas a coluna e
    # jsonb not null default {} e `{}.blank?` e true no Rails. Toda macro sem
    # input_fields estourava RecordInvalid dentro do job -- depois do endpoint
    # ja ter respondido 200 -- e nenhuma acao rodava. Falha silenciosa.
    it 'accepts an empty inputs hash (macro without input_fields)' do
      execution = described_class.new(account: account, macro: macro, inputs: {})
      expect(execution).to be_valid
    end

    it 'accepts a populated inputs hash' do
      execution = described_class.new(account: account, macro: macro, inputs: { 'cpf' => '123' })
      expect(execution).to be_valid
    end

    it 'rejects a non-hash inputs' do
      execution = described_class.new(account: account, macro: macro, inputs: ['nope'])
      expect(execution).not_to be_valid
      expect(execution.errors[:inputs]).to include('must be a hash')
    end
  end

  describe 'status' do
    it 'defaults to pending' do
      expect(described_class.new.status).to eq('pending')
    end

    it 'exposes the four execution outcomes' do
      expect(described_class.statuses).to eq('pending' => 0, 'success' => 1, 'partial' => 2, 'failed' => 3)
    end
  end

  describe '.recent' do
    it 'orders newest first' do
      old = create(:macro_execution, account: account, macro: macro, created_at: 2.days.ago)
      new = create(:macro_execution, account: account, macro: macro, created_at: 1.hour.ago)

      expect(described_class.recent.to_a).to eq([new, old])
    end
  end

  describe 'when the macro is destroyed' do
    it 'destroys its executions' do
      create(:macro_execution, account: account, macro: macro)
      expect { macro.destroy! }.to change(described_class, :count).by(-1)
    end
  end

  describe 'when the conversation is destroyed' do
    it 'keeps the audit record with a dangling conversation_id' do
      conversation = create(:conversation, account: account)
      execution = create(:macro_execution, account: account, macro: macro, conversation: conversation)

      conversation.destroy!

      expect(execution.reload).to be_present
      expect(execution.conversation).to be_nil
    end
  end
end
