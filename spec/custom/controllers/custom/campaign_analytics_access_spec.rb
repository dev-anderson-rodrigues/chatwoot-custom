require 'rails_helper'

# [FORK] Analytics de campanha para o disparo generico (Onda 7 / fatia 2). Ver
# custom/app/controllers/custom/campaign_analytics_access.rb.
RSpec.describe 'Campaign analytics API for generic dispatch', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:channel_email, account: account, smtp_enabled: true).inbox }
  let(:campaign) do
    create(:campaign, account: account, inbox: inbox, template_params: { 'subject' => 'Fatura' })
  end
  let(:metrics_path) { "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/analytics/metrics" }
  let(:contacts_path) { "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}/analytics/contacts" }

  def add_recipient(contact, **attrs)
    CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: contact, **attrs)
  end

  before do
    add_recipient(create(:contact, account: account, email: 'sent@example.com'), status: :sent, source_id: 'message:1')
    add_recipient(create(:contact, account: account, email: 'failed@example.com'), status: :failed, error_message: 'smtp is down')
    add_recipient(create(:contact, account: account, email: nil), status: :skipped, error_message: 'Contact has no e-mail address')
  end

  it 'devolve as metricas de uma campanha de e-mail, sem exigir a flag do WhatsApp' do
    account.disable_features!(:whatsapp_campaign)

    get metrics_path, headers: administrator.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('audience' => 3, 'sent' => 1, 'failed' => 1, 'skipped' => 1)
  end

  it 'Enviadas nao inclui quem o canal recusou depois (senao enviadas + falharam passariam do publico)' do
    # No disparo generico o source_id nasce com a mensagem; este destinatario foi entregue ao canal e falhou depois.
    add_recipient(create(:contact, account: account, email: 'late@example.com'), status: :failed, source_id: 'message:2', error_message: 'blocked by the user')

    get metrics_path, headers: administrator.create_new_auth_token

    body = response.parsed_body
    expect(body).to include('audience' => 4, 'sent' => 1, 'failed' => 2, 'skipped' => 1)
    expect(body['sent'] + body['failed'] + body['skipped']).to eq(body['audience'])
  end

  it 'Enviadas inclui entregues e lidas (canal com recibo)' do
    add_recipient(create(:contact, account: account, email: 'd@example.com'), status: :delivered, source_id: 'message:3')
    add_recipient(create(:contact, account: account, email: 'r@example.com'), status: :read, source_id: 'message:4')

    get metrics_path, headers: administrator.create_new_auth_token

    expect(response.parsed_body).to include('sent' => 3, 'delivered' => 2, 'read' => 1)
  end

  it 'lista os destinatarios com o motivo e o e-mail do contato' do
    get contacts_path, params: { status: 'failed' }, headers: administrator.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']).to contain_exactly(
      include('status' => 'failed', 'error_message' => 'smtp is down', 'contact' => include('email' => 'failed@example.com'))
    )
  end

  it 'lista quem foi pulado, com o motivo' do
    get contacts_path, params: { status: 'skipped' }, headers: administrator.create_new_auth_token

    expect(response.parsed_body['payload']).to contain_exactly(
      include('status' => 'skipped', 'error_message' => 'Contact has no e-mail address')
    )
  end

  it 'exige acesso a campanha (agente nao ve)' do
    get metrics_path, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:unauthorized)
  end

  it 'nao vaza campanha de outra conta' do
    other_admin = create(:user, account: create(:account), role: :administrator)

    get metrics_path, headers: other_admin.create_new_auth_token

    expect(response).to have_http_status(:unauthorized)
  end

  context 'when the inbox is not served by the generic dispatch' do
    it 'campanha ongoing (Website) continua sem analytics' do
      widget_campaign = create(:campaign, account: account)

      get "/api/v1/accounts/#{account.id}/campaigns/#{widget_campaign.display_id}/analytics/metrics",
          headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    it 'WhatsApp continua exigindo a flag' do
      whatsapp = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
      whatsapp_campaign = create(:campaign, account: account, inbox: whatsapp.inbox)
      account.disable_features!(:whatsapp_campaign)

      get "/api/v1/accounts/#{account.id}/campaigns/#{whatsapp_campaign.display_id}/analytics/metrics",
          headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end

    it 'WhatsApp com a flag ligada continua funcionando' do
      whatsapp = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
      whatsapp_campaign = create(:campaign, account: account, inbox: whatsapp.inbox)
      account.enable_features!(:whatsapp_campaign)

      get "/api/v1/accounts/#{account.id}/campaigns/#{whatsapp_campaign.display_id}/analytics/metrics",
          headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:ok)
    end
  end
end
