require 'rails_helper'

# [FORK] Destrava campanha presa em `processing` (job que morreu no meio). Ver
# custom/app/jobs/custom/campaigns/reset_stale_processing_job.rb.
RSpec.describe Custom::Campaigns::ResetStaleProcessingJob do
  let(:account) { create(:account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { whatsapp_channel.inbox }
  let!(:campaign) { create(:campaign, inbox: inbox, account: account) }

  def set_processing(started_at:)
    # rubocop:disable Rails/SkipsModelValidations
    campaign.update_columns(campaign_status: Campaign.campaign_statuses[:processing], started_at: started_at)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def add_recipient(updated_at:)
    contact = create(:contact, :with_phone_number, account: account)
    recipient = campaign.campaign_recipients.create!(account: account, inbox: inbox, contact: contact, status: :sent)
    recipient.update_columns(updated_at: updated_at) # rubocop:disable Rails/SkipsModelValidations
  end

  it 'esta na frente do agendador: o TriggerScheduledItemsJob enfileira o destravamento' do
    expect { TriggerScheduledItemsJob.perform_now }.to have_enqueued_job(described_class)
  end

  it 'volta para active e reenfileira a campanha presa ha muito tempo, sem atividade' do
    set_processing(started_at: 2.hours.ago)

    expect { described_class.perform_now }.to have_enqueued_job(Campaigns::TriggerOneoffCampaignJob).with(campaign)
    expect(campaign.reload).to be_active
  end

  it 'destrava tambem quando ha destinatarios, mas todos parados' do
    set_processing(started_at: 2.hours.ago)
    add_recipient(updated_at: 1.hour.ago)

    described_class.perform_now

    expect(campaign.reload).to be_active
  end

  it 'nao mexe em campanha grande e lenta, mas viva (destinatario atualizado ha pouco)' do
    set_processing(started_at: 2.hours.ago)
    add_recipient(updated_at: 1.minute.ago)

    expect { described_class.perform_now }.not_to have_enqueued_job(Campaigns::TriggerOneoffCampaignJob)
    expect(campaign.reload).to be_processing
  end

  it 'nao mexe em campanha que comecou ha pouco' do
    set_processing(started_at: 5.minutes.ago)

    expect { described_class.perform_now }.not_to have_enqueued_job(Campaigns::TriggerOneoffCampaignJob)
    expect(campaign.reload).to be_processing
  end

  # O maior intervalo legitimo sem tocar em destinatario e ~2 min (3 tentativas de
  # 30s + esperas); 10 min tem folga, e encurta a recuperacao depois de um deploy.
  it 'usa 10 minutos como limite do batimento' do
    expect(described_class::STALE_AFTER).to eq(10.minutes)
  end

  it 'destrava logo depois do limite quando nao ha nenhuma atividade' do
    set_processing(started_at: 11.minutes.ago)

    described_class.perform_now

    expect(campaign.reload).to be_active
  end

  it 'nao destrava quando o ultimo destinatario mexeu um pouco antes do limite' do
    set_processing(started_at: 2.hours.ago)
    add_recipient(updated_at: 9.minutes.ago)

    described_class.perform_now

    expect(campaign.reload).to be_processing
  end

  it 'nao mexe em campanha ativa nem concluida' do
    completed = create(:campaign, inbox: inbox, account: account)
    # rubocop:disable Rails/SkipsModelValidations
    completed.update_columns(campaign_status: Campaign.campaign_statuses[:completed], started_at: 2.hours.ago)
    # rubocop:enable Rails/SkipsModelValidations

    expect { described_class.perform_now }.not_to have_enqueued_job(Campaigns::TriggerOneoffCampaignJob)
    expect(completed.reload).to be_completed
    expect(campaign.reload).to be_active
  end

  it 'nao mexe em campanha ongoing (widget)' do
    widget_campaign = create(:campaign, account: account)
    # rubocop:disable Rails/SkipsModelValidations
    widget_campaign.update_columns(campaign_status: Campaign.campaign_statuses[:processing], started_at: 2.hours.ago)
    # rubocop:enable Rails/SkipsModelValidations

    expect { described_class.perform_now }.not_to have_enqueued_job(Campaigns::TriggerOneoffCampaignJob).with(widget_campaign)
    expect(widget_campaign.reload).to be_processing
  end
end
