require 'rails_helper'
require Rails.root.join('db/migrate/20260921000000_set_fork_feature_defaults')

# [FORK] O padrao das contas NOVAS vem do registro ACCOUNT_LEVEL_FEATURE_DEFAULTS
# no banco, e o ConfigLoader do deploy nao sobrescreve o que ja esta la -- entao
# mudar o features.yml numa instalacao existente nao chega a conta nenhuma criada
# depois. Estes testes partem do estado de uma instalacao existente (registro com
# os padroes do upstream) e provam que a migration corrige as duas pontas.
RSpec.describe SetForkFeatureDefaults do
  subject(:migration) { described_class.new }

  before do
    ConfigLoader.new.process
    config = InstallationConfig.find_by!(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    config.value = config.value.map do |feature|
      case feature['name']
      when 'whatsapp_campaign' then feature.merge('enabled' => false)
      when 'companies' then feature.merge('enabled' => true)
      else feature
      end
    end
    config.save!
    GlobalConfig.clear_cache
  end

  after { GlobalConfig.clear_cache }

  def run_migration
    ActiveRecord::Migration.suppress_messages { migration.up }
  end

  it 'reproduz o problema: sem a migration, uma conta nova herda os padroes antigos' do
    account = create(:account)

    expect(account.feature_enabled?('whatsapp_campaign')).to be false
    expect(account.feature_enabled?('companies')).to be true
  end

  it 'faz uma conta criada DEPOIS herdar whatsapp_campaign ligado e companies desligado' do
    run_migration
    account = create(:account)

    expect(account.feature_enabled?('whatsapp_campaign')).to be true
    expect(account.feature_enabled?('companies')).to be false
  end

  it 'ajusta as contas que ja existiam' do
    existing = create(:account)

    run_migration

    existing.reload
    expect(existing.feature_enabled?('whatsapp_campaign')).to be true
    expect(existing.feature_enabled?('companies')).to be false
  end

  it 'nao mexe nas outras features' do
    existing = create(:account)
    other_features = existing.enabled_features.keys - %w[whatsapp_campaign companies]

    run_migration

    expect(existing.reload.enabled_features.keys - %w[whatsapp_campaign companies]).to match_array(other_features)
  end

  it 'e idempotente' do
    existing = create(:account)

    run_migration
    run_migration

    existing.reload
    expect(existing.feature_enabled?('whatsapp_campaign')).to be true
    expect(existing.feature_enabled?('companies')).to be false
  end

  it 'nao quebra numa instalacao sem o registro de padroes e ainda ajusta as contas' do
    existing = create(:account)
    InstallationConfig.find_by!(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS').destroy

    expect { run_migration }.not_to raise_error
    expect(existing.reload.feature_enabled?('whatsapp_campaign')).to be true
  end
end
