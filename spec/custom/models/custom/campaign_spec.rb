require 'rails_helper'

# [FORK] Campanha por qualquer caixa (Onda 7 / fatia 2). Ver custom/app/models/custom/campaign.rb.
RSpec.describe Campaign do
  let(:account) { create(:account) }

  def build_campaign(inbox, **attrs)
    build(:campaign, account: account, inbox: inbox, **attrs)
  end

  describe 'caixas atendidas pelo disparo generico' do
    {
      'Email' => -> { create(:channel_email, account: account, smtp_enabled: true).inbox },
      'Telegram' => -> { create(:channel_telegram, account: account).inbox },
      'Instagram' => -> { create(:channel_instagram, account: account).inbox },
      'API' => -> { create(:channel_api, account: account).inbox },
      'Tiktok' => -> { create(:channel_tiktok, account: account).inbox }
    }.each do |type, factory|
      it "aceita #{type}: vira disparo em massa (one_off), agendado para agora" do
        inbox = instance_exec(&factory)
        campaign = build_campaign(inbox, template_params: { 'subject' => 'Assunto' })

        expect(campaign).to be_valid
        expect(campaign.campaign_type).to eq('one_off')
        expect(campaign.scheduled_at).to be_present
      end
    end

    it 'respeita o agendamento informado' do
      inbox = create(:channel_telegram, account: account).inbox
      scheduled = 2.days.from_now.change(usec: 0)

      campaign = build_campaign(inbox, scheduled_at: scheduled)
      campaign.valid?

      expect(campaign.scheduled_at).to eq(scheduled)
    end
  end

  describe 'e-mail exige assunto' do
    let(:inbox) { create(:channel_email, account: account, smtp_enabled: true).inbox }

    it 'e invalida sem assunto' do
      campaign = build_campaign(inbox)

      expect(campaign).not_to be_valid
      expect(campaign.errors[:template_params]).to include('must include a subject for e-mail campaigns')
    end

    it 'e invalida com assunto em branco' do
      expect(build_campaign(inbox, template_params: { 'subject' => '  ' })).not_to be_valid
    end

    it 'e valida com assunto (chave string ou simbolo)' do
      expect(build_campaign(inbox, template_params: { 'subject' => 'Fatura' })).to be_valid
      expect(build_campaign(inbox, template_params: { subject: 'Fatura' })).to be_valid
    end

    it 'expoe o assunto' do
      expect(build_campaign(inbox, template_params: { 'subject' => 'Fatura' }).email_subject).to eq('Fatura')
    end

    it 'as outras caixas nao exigem assunto' do
      expect(build_campaign(create(:channel_telegram, account: account).inbox)).to be_valid
    end
  end

  describe 'e-mail exige remetente proprio (nao o SMTP da plataforma)' do
    let(:channel) { create(:channel_email, account: account) }
    let(:inbox) { channel.inbox }
    let(:attrs) { { template_params: { 'subject' => 'Fatura' } } }

    it 'e invalida quando a caixa nao tem SMTP proprio' do
      campaign = build_campaign(inbox, **attrs)

      expect(campaign).not_to be_valid
      expect(campaign.errors[:inbox]).to include('needs its own SMTP (or a Google/Microsoft connection) to send campaigns')
    end

    it 'mesmo com SMTP global configurado (o mailer o usaria, mas e a infraestrutura de todos os tenants)' do
      stub_const('ENV', ENV.to_hash.merge('SMTP_ADDRESS' => 'smtp.plataforma.example'))

      expect(build_campaign(inbox, **attrs)).not_to be_valid
    end

    it 'e valida com SMTP proprio na caixa' do
      channel.update!(smtp_enabled: true)

      expect(build_campaign(inbox, **attrs)).to be_valid
    end

    it 'e valida com conexao Google (IMAP + OAuth)' do
      channel.update!(imap_enabled: true, provider: 'google')

      expect(build_campaign(inbox, **attrs)).to be_valid
    end

    it 'e valida com conexao Microsoft (IMAP + OAuth)' do
      channel.update!(imap_enabled: true, provider: 'microsoft')

      expect(build_campaign(inbox, **attrs)).to be_valid
    end

    it 'IMAP sozinho nao basta (so recebe)' do
      channel.update!(imap_enabled: true)

      expect(build_campaign(inbox, **attrs)).not_to be_valid
    end

    it 'CAMPAIGN_EMAIL_ALLOW_PLATFORM_SMTP=true libera (instalacao de uma empresa so)' do
      stub_const('ENV', ENV.to_hash.merge('CAMPAIGN_EMAIL_ALLOW_PLATFORM_SMTP' => 'true'))

      expect(build_campaign(inbox, **attrs)).to be_valid
    end

    it 'so vale na criacao: desligar o SMTP depois nao trava a campanha em andamento (o upstream faz update! a cada passo)' do
      channel.update!(smtp_enabled: true)
      campaign = create(:campaign, account: account, inbox: inbox, **attrs)
      channel.update_columns(smtp_enabled: false) # rubocop:disable Rails/SkipsModelValidations

      expect { campaign.update!(campaign_status: :processing) }.not_to raise_error
    end

    it 'mas trocar o assunto ou a caixa reexamina' do
      channel.update!(smtp_enabled: true)
      campaign = create(:campaign, account: account, inbox: inbox, **attrs)
      channel.update_columns(smtp_enabled: false) # rubocop:disable Rails/SkipsModelValidations

      campaign.template_params = { 'subject' => 'Outro assunto' }

      expect(campaign).not_to be_valid
    end

    it 'as outras caixas nao tem essa exigencia' do
      expect(build_campaign(create(:channel_telegram, account: account).inbox)).to be_valid
    end

    it 'a mensagem de erro sai no idioma da conta/usuario (pt_BR)' do
      I18n.with_locale(:pt_BR) do
        campaign = build_campaign(inbox, **attrs)
        campaign.valid?

        expect(campaign.errors[:inbox]).to include('precisa de SMTP próprio (ou de uma conexão Google/Microsoft) para enviar campanhas')
      end
    end
  end

  describe 'agendamento no passado (o agendador so pega os ultimos 3 dias)' do
    let(:inbox) { create(:channel_telegram, account: account).inbox }

    it 'data antiga demais na criacao vira "agora": senao a campanha nunca dispararia' do
      campaign = build_campaign(inbox, scheduled_at: 10.days.ago)
      campaign.valid?

      expect(campaign.scheduled_at).to be_within(5.seconds).of(Time.now.utc)
    end

    it 'data ate 5 minutos no passado (relogio do navegador) e respeitada' do
      when_scheduled = 2.minutes.ago.change(usec: 0)
      campaign = build_campaign(inbox, scheduled_at: when_scheduled)
      campaign.valid?

      expect(campaign.scheduled_at).to eq(when_scheduled)
    end

    it 'depois de criada, o agendamento nao e reescrito (a campanha disparada tem agendamento no passado por definicao)' do
      campaign = create(:campaign, account: account, inbox: inbox)
      original = campaign.scheduled_at
      travel_to(2.hours.from_now) { campaign.update!(campaign_status: :processing) }

      expect(campaign.reload.scheduled_at).to eq(original)
    end
  end

  describe 'o que continua como no upstream' do
    it 'Website continua sendo campanha ongoing, sem agendamento' do
      campaign = build_campaign(create(:inbox, account: account, channel: create(:channel_widget, account: account)))

      expect(campaign).to be_valid
      expect(campaign.campaign_type).to eq('ongoing')
      expect(campaign.scheduled_at).to be_nil
    end

    it 'SMS continua one_off' do
      campaign = build_campaign(create(:inbox, account: account, channel: create(:channel_sms, account: account)))

      expect(campaign).to be_valid
      expect(campaign.campaign_type).to eq('one_off')
    end

    it 'caixa fora das listas continua invalida' do
      campaign = build_campaign(create(:inbox, account: account, channel: create(:channel_twitter_profile, account: account)))

      expect(campaign).not_to be_valid
      expect(campaign.errors[:inbox]).to include('Unsupported Inbox type')
    end
  end

  describe '#trigger!' do
    it 'caixa generica dispara pelo servico generico' do
      campaign = create(:campaign, account: account, inbox: create(:channel_telegram, account: account).inbox)
      service = instance_double(Custom::Campaigns::OneoffMessageService, perform: true)
      allow(Custom::Campaigns::OneoffMessageService).to receive(:new).with(campaign: campaign).and_return(service)

      campaign.trigger!

      expect(service).to have_received(:perform)
      expect(campaign.reload).to be_processing
    end

    it 'SMS continua no servico do upstream, nao no generico' do
      campaign = create(:campaign, account: account, inbox: create(:inbox, account: account, channel: create(:channel_sms, account: account)))
      service = instance_double(Sms::OneoffSmsCampaignService, perform: true)
      allow(Sms::OneoffSmsCampaignService).to receive(:new).and_return(service)
      allow(Custom::Campaigns::OneoffMessageService).to receive(:new)

      campaign.trigger!

      expect(service).to have_received(:perform)
      expect(Custom::Campaigns::OneoffMessageService).not_to have_received(:new)
    end

    it 'e-mail dispara sem depender da flag do WhatsApp' do
      campaign = create(:campaign, account: account, inbox: create(:channel_email, account: account, smtp_enabled: true).inbox,
                                   template_params: { 'subject' => 'Fatura' })
      account.disable_features!(:whatsapp_campaign)
      service = instance_double(Custom::Campaigns::OneoffMessageService, perform: true)
      allow(Custom::Campaigns::OneoffMessageService).to receive(:new).and_return(service)

      campaign.trigger!

      expect(Custom::Campaigns::OneoffMessageService).to have_received(:new)
    end
  end
end
