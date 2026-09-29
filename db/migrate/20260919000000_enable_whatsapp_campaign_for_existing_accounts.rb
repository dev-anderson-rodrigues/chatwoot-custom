# [FORK] Liga whatsapp_campaign nas contas que ja existem.
#
# Este arquivo liga o flag so nas contas que JA existem. Sozinho ele nao basta:
# o padrao das contas NOVAS vem do registro ACCOUNT_LEVEL_FEATURE_DEFAULTS, e o
# ConfigLoader do deploy nao sobrescreve entrada que ja existe nele -- entao
# trocar o valor no features.yml nao chega a conta criada depois. Isso e
# corrigido em 20260921000000_set_fork_feature_defaults.rb, que atualiza o
# registro tambem. (Este comentario dizia o contrario ate 2026-09-21.)
#
# Neste fork cada empresa e uma conta, entao as que ja existem precisam do flag
# ligado explicitamente, senao a campanha de WhatsApp levanta 'WhatsApp
# campaigns feature not enabled' para elas. Mesmo formato de
# 20260120121402_enable_captain_tasks_for_existing_accounts.rb.
#
# Idempotente: enable_features! sobre flag ja ligado nao muda nada.
class EnableWhatsappCampaignForExistingAccounts < ActiveRecord::Migration[7.0]
  def up
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each { |account| account.enable_features!('whatsapp_campaign') }
    end
  end

  def down
    # Sem reversao: nao da para saber quais contas ja tinham o flag ligado por
    # decisao propria antes desta migration.
  end
end
