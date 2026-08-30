require 'rails_helper'

RSpec.describe Macro do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  after do
    Current.user = nil
    Current.account = nil
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
  end

  describe 'validations' do
    it 'validation action name' do
      macro = FactoryBot.build(:macro, account: account, created_by: admin, updated_by: admin, actions: [{ action_name: :update_last_seen }])
      expect(macro).not_to be_valid
      expect(macro.errors.full_messages).to eq(['Actions Macro execution actions update_last_seen not supported.'])
    end
  end

  describe 'input_fields validation' do
    def build_macro(input_fields)
      FactoryBot.build(:macro, account: account, created_by: admin, updated_by: admin, actions: [], input_fields: input_fields)
    end

    def errors_for(input_fields)
      macro = build_macro(input_fields)
      macro.valid?
      macro.errors[:input_fields]
    end

    it 'accepts an empty list' do
      expect(build_macro([])).to be_valid
    end

    it 'accepts a well formed field' do
      expect(build_macro([{ 'key' => 'cpf', 'label' => 'CPF', 'type' => 'cpf' }])).to be_valid
    end

    it 'rejects a non-array' do
      expect(errors_for('nope')).to include('must be an array')
    end

    it 'rejects an entry that is not an object' do
      expect(errors_for(['nope'])).to include('input_fields[0] must be an object')
    end

    it 'requires a key' do
      expect(errors_for([{ 'label' => 'X', 'type' => 'text' }])).to include('input_fields[0].key is required')
    end

    it 'requires the key to be snake_case' do
      expect(errors_for([{ 'key' => 'CPF Cliente', 'label' => 'X', 'type' => 'text' }]))
        .to include('input_fields[0].key must be snake_case (lowercase, digits, underscore)')
    end

    it 'rejects duplicated keys' do
      fields = [
        { 'key' => 'cpf', 'label' => 'A', 'type' => 'text' },
        { 'key' => 'cpf', 'label' => 'B', 'type' => 'text' }
      ]
      expect(errors_for(fields)).to include("input_fields[1].key 'cpf' is duplicated")
    end

    it 'requires a label' do
      expect(errors_for([{ 'key' => 'cpf', 'label' => '  ', 'type' => 'text' }]))
        .to include('input_fields[0].label is required')
    end

    it 'rejects an unsupported type' do
      expect(errors_for([{ 'key' => 'cpf', 'label' => 'X', 'type' => 'sql' }]))
        .to include("input_fields[0].type 'sql' is not supported")
    end

    context 'with a select field' do
      it 'requires options' do
        expect(errors_for([{ 'key' => 'motivo', 'label' => 'Motivo', 'type' => 'select' }]))
          .to include('input_fields[0].options is required for select fields')
      end

      it 'accepts a field with options' do
        fields = [{ 'key' => 'motivo', 'label' => 'Motivo', 'type' => 'select',
                    'options' => [{ 'value' => '1', 'label' => 'Um' }] }]
        expect(build_macro(fields)).to be_valid
      end
    end

    context 'with a lookup field' do
      let(:base) { { 'key' => 'contrato', 'label' => 'Contrato', 'type' => 'lookup', 'depends_on' => ['cpf'] } }

      it 'requires a lookup_url' do
        expect(errors_for([base])).to include('input_fields[0].lookup_url is required for lookup fields')
      end

      it 'requires depends_on to list at least one key' do
        allow(Macros::SafeUrl).to receive(:public_http?).and_return(true)
        fields = [base.merge('lookup_url' => 'https://api.example.com/x').except('depends_on')]
        expect(errors_for(fields)).to include('input_fields[0].depends_on must list at least one key')
      end

      it 'rejects a non http(s) url' do
        fields = [base.merge('lookup_url' => 'ftp://api.example.com/x')]
        expect(errors_for(fields)).to include('input_fields[0].lookup_url must be a valid http(s) URL')
      end

      # A URL e acionada pelo servidor: sem esta guarda, uma macro global poderia
      # apontar para a rede interna da instalacao.
      it 'rejects a url that resolves to a private host' do
        allow(Macros::SafeUrl).to receive(:public_http?).and_return(false)
        fields = [base.merge('lookup_url' => 'http://169.254.169.254/latest/meta-data/')]
        expect(errors_for(fields))
          .to include('input_fields[0].lookup_url must point to a public host (no private/loopback IPs)')
      end

      it 'accepts a public url' do
        allow(Macros::SafeUrl).to receive(:public_http?).and_return(true)
        expect(build_macro([base.merge('lookup_url' => 'https://api.example.com/x')])).to be_valid
      end
    end
  end

  describe '#set_visibility' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:macro) { create(:macro, account: account, created_by: admin, updated_by: admin, actions: []) }

    context 'when user is administrator' do
      it 'set visibility with params' do
        expect(macro.visibility).to eq('personal')

        macro.set_visibility(admin, { visibility: :global })

        expect(macro.visibility).to eq('global')

        macro.set_visibility(admin, { visibility: :personal })

        expect(macro.visibility).to eq('personal')
      end
    end

    context 'when user is agent' do
      it 'set visibility always to agent' do
        Current.user = agent
        Current.account = account

        expect(macro.visibility).to eq('personal')

        macro.set_visibility(agent, { visibility: :global })

        expect(macro.visibility).to eq('personal')
      end
    end
  end

  describe '#with_visibility' do
    let(:agent_1) { create(:user, account: account, role: :agent) }
    let(:agent_2) { create(:user, account: account, role: :agent) }

    before do
      create(:macro, account: account, created_by: admin, updated_by: admin, visibility: :global, actions: [])
      create(:macro, account: account, created_by: admin, updated_by: admin, visibility: :global, actions: [])
      create(:macro, account: account, created_by: admin, updated_by: admin, visibility: :personal, actions: [])
      create(:macro, account: account, created_by: admin, updated_by: admin, visibility: :personal, actions: [])
      create(:macro, account: account, created_by: agent_1, updated_by: agent_1, visibility: :personal, actions: [])
      create(:macro, account: account, created_by: agent_1, updated_by: agent_1, visibility: :personal, actions: [])
      create(:macro, account: account, created_by: agent_2, updated_by: agent_2, visibility: :personal, actions: [])
      create(:macro, account: account, created_by: agent_2, updated_by: agent_2, visibility: :personal, actions: [])
      create(:macro, account: account, created_by: agent_2, updated_by: agent_2, visibility: :personal, actions: [])
    end

    context 'when user is administrator' do
      it 'return all macros in account' do
        Current.user = admin
        Current.account = account

        macros = account.macros.global.or(account.macros.personal.where(created_by_id: admin.id))

        expect(described_class.with_visibility(admin, {}).count).to eq(macros.count)
      end
    end

    context 'when user is agent' do
      it 'return all macros in account and created_by user' do
        Current.user = agent_2
        Current.account = account

        macros_for_agent_2 = account.macros.global.count + agent_2.macros.personal.count
        expect(described_class.with_visibility(agent_2, {}).count).to eq(macros_for_agent_2)

        Current.user = agent_1

        macros_for_agent_1 = account.macros.global.count + agent_1.macros.personal.count
        expect(described_class.with_visibility(agent_1, {}).count).to eq(macros_for_agent_1)
      end
    end
  end

  describe '#associations' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let!(:global_macro) { FactoryBot.create(:macro, account: account, created_by: agent, updated_by: agent, visibility: :global, actions: []) }
    let!(:personal_macro) { FactoryBot.create(:macro, account: account, created_by: agent, updated_by: agent, visibility: :personal, actions: []) }

    context 'when you delete the author' do
      it 'nullify the created_by column' do
        expect(global_macro.created_by).to eq(agent)
        expect(global_macro.updated_by).to eq(agent)
        expect(personal_macro.created_by).to eq(agent)
        expect(personal_macro.updated_by).to eq(agent)

        personal_macro_id = personal_macro.id
        agent.destroy!

        expect(global_macro.reload.created_by).to be_nil
        expect(global_macro.reload.updated_by).to be_nil
        expect(described_class.find_by(id: personal_macro_id)).to be_nil
      end
    end
  end
end
