# [FORK] Liga whatsapp_campaign nas contas que ja existem.
#
# features.yml passou a ter `enabled: true` para whatsapp_campaign, mas isso so
# vale para contas criadas depois -- o ConfigLoader atualiza
# ACCOUNT_LEVEL_FEATURE_DEFAULTS no deploy, e esse default e lido no cadastro.
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
