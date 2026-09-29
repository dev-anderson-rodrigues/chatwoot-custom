# [FORK] Padroes de feature flag que o fork decidiu diferentes do upstream.
#
#   whatsapp_campaign -> LIGADO  (campanha de cobranca por WhatsApp, Onda 7)
#   companies         -> DESLIGADO (cada empresa e uma conta; a entidade "Company"
#                                   agrupa contatos DENTRO de uma conta e so faria
#                                   sentido para filiais -- decisao do dono, 2026-09-19)
#
# Por que mexer no registro e nao so no features.yml: o padrao das contas NOVAS
# vem do registro ACCOUNT_LEVEL_FEATURE_DEFAULTS no banco (Featurable#
# enable_default_features), e o ConfigLoader do deploy roda com reconcile_only_new:
# so ACRESCENTA feature que ainda nao existe, nunca sobrescreve a que ja esta la.
# Trocar o valor no YAML, numa instalacao existente, nao chega a nenhuma conta
# criada depois -- e neste produto cada nova empresa e uma conta nova. Mesmo
# desenho de 20250416182131_flip_chatwoot_v4_default_feature_flag_installation_config.rb.
#
# Depois ajusta as contas que ja existem (o registro so vale para cadastro novo).
# Idempotente. Uma conta que queira Empresas (filiais) liga de volta no super admin.
class SetForkFeatureDefaults < ActiveRecord::Migration[7.0]
  FEATURE_DEFAULTS = { 'whatsapp_campaign' => true, 'companies' => false }.freeze

  def up
    update_installation_defaults
    update_existing_accounts
    GlobalConfig.clear_cache
  end

  def down
    # Sem reversao: nao da para saber quais contas tinham cada flag ligado ou
    # desligado por decisao propria antes desta migration.
  end

  private

  def update_installation_defaults
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config.blank? || config.value.blank?

    config.value = config.value.map do |feature|
      FEATURE_DEFAULTS.key?(feature['name']) ? feature.merge('enabled' => FEATURE_DEFAULTS[feature['name']]) : feature
    end
    config.save!
  end

  def update_existing_accounts
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each do |account|
        FEATURE_DEFAULTS.each do |name, enabled|
          enabled ? account.enable_features!(name) : account.disable_features!(name)
        end
      end
    end
  end
end
