require 'rails_helper'

describe Whatsapp::OneoffCampaignService do
  let(:account) { create(:account) }
  let!(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let!(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:label1) { create(:label, account: account) }
  let(:label2) { create(:label, account: account) }
  let!(:campaign) do
    create(:campaign, inbox: whatsapp_inbox, account: account,
                      audience: [{ type: 'Label', id: label1.id }, { type: 'Label', id: label2.id }],
                      template_params: template_params)
  end
  let(:template_params) do
    {
      'name' => 'ticket_status_updated',
      'namespace' => '23423423_2342423_324234234_2343224',
      'category' => 'UTILITY',
      'language' => 'en',
      'processed_params' => { 'body' => { 'name' => 'John', 'ticket_id' => '2332' } }
    }
  end

  before do
    # Stub HTTP requests to WhatsApp API
    stub_request(:post, /graph\.facebook\.com.*messages/)
      .to_return(status: 200, body: { messages: [{ id: 'message_id_123' }] }.to_json, headers: { 'Content-Type' => 'application/json' })

    # Ensure the service uses our mocked channel object by stubbing the whole delegation chain
    # Using allow_any_instance_of here because the service is instantiated within individual tests
    # and we need to mock the delegated channel method for proper test isolation
    allow_any_instance_of(described_class).to receive(:channel).and_return(whatsapp_channel) # rubocop:disable RSpec/AnyInstance
  end

  describe '#perform' do
    before do
      # Enable WhatsApp campaigns feature flag for all tests
      account.enable_features!(:whatsapp_campaign)
    end

    context 'when campaign validation fails' do
      it 'raises error if campaign is completed' do
        campaign.completed!

        expect { described_class.new(campaign: campaign).perform }.to raise_error 'Completed Campaign'
      end

      it 'raises error when campaign is not a WhatsApp campaign' do
        sms_channel = create(:channel_sms, account: account)
        sms_inbox = create(:inbox, channel: sms_channel, account: account)
        invalid_campaign = create(:campaign, inbox: sms_inbox, account: account)

        expect { described_class.new(campaign: invalid_campaign).perform }
          .to raise_error "Invalid campaign #{invalid_campaign.id}"
      end

      it 'raises error when campaign is not oneoff' do
        allow(campaign).to receive(:one_off?).and_return(false)

        expect { described_class.new(campaign: campaign).perform }.to raise_error "Invalid campaign #{campaign.id}"
      end

      # [FORK] O upstream travava em whatsapp_cloud; o fork libera tambem o
      # 360dialog ('default') via custom/app/services/custom/whatsapp/. Um
      # provider fora da lista continua barrado.
      it 'raises error when channel provider is not supported for campaigns' do
        allow(whatsapp_channel).to receive(:provider).and_return('unsupported_provider')

        expect { described_class.new(campaign: campaign).perform }
          .to raise_error 'WhatsApp provider not supported for campaigns: unsupported_provider'
      end

      it 'raises error when WhatsApp campaigns feature is not enabled' do
        account.disable_features!(:whatsapp_campaign)

        expect { described_class.new(campaign: campaign).perform }.to raise_error 'WhatsApp campaigns feature not enabled'
      end
    end

    # [FORK] 360dialog ('default'): o envio sai pela API da 360dialog, com o
    # mesmo contrato de send_template, e o id devolvido marca o destinatario
    # como enviado -- se o id nao voltasse, o override enterprise marcaria
    # todos como falha mesmo com a mensagem entregue.
    context 'when the channel uses the 360dialog provider' do
      before do
        whatsapp_channel.update!(provider: 'default')
        stub_request(:post, %r{waba\.360dialog\.io/v1/messages})
          .to_return(status: 200, body: { messages: [{ id: 'wamid.360dialog_1' }] }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'sends the template through the 360dialog API and completes the campaign' do
        contact = create(:contact, :with_phone_number, account: account)
        contact.update_labels([label1.title])

        described_class.new(campaign: campaign).perform

        expect(a_request(:post, %r{waba\.360dialog\.io/v1/messages})).to have_been_made.once
        expect(campaign.reload.completed?).to be true
      end

      it 'marks the recipient as sent with the id returned by the provider' do
        contact = create(:contact, :with_phone_number, account: account)
        contact.update_labels([label1.title])

        described_class.new(campaign: campaign).perform

        expect(campaign.campaign_recipients.pluck(:source_id)).to eq(['wamid.360dialog_1'])
      end

      # Erro de requisicao (o caso mais comum: template/parametro invalido) vem em
      # `meta.developer_message` -- formato que o proprio servico do 360dialog ja
      # documenta. Sem o tratamento em custom/.../providers/base_service.rb, a
      # tabela de entrega mostraria so "provider did not return a message id".
      it 'records the request error reason when 360dialog returns it in meta' do
        stub_request(:post, %r{waba\.360dialog\.io/v1/messages})
          .to_return(status: 400, headers: { 'Content-Type' => 'application/json' },
                     body: { meta: { success: false, http_code: 400,
                                     developer_message: 'number of localizable_params does not match' } }.to_json)
        contact = create(:contact, :with_phone_number, account: account)
        contact.update_labels([label1.title])

        described_class.new(campaign: campaign).perform

        expect(campaign.campaign_recipients.first).to have_attributes(
          status: 'failed', error_code: '400', error_message: 'number of localizable_params does not match'
        )
      end

      # E a lista `errors` (falha de entrega no nivel do WhatsApp).
      it 'records the provider reason when 360dialog rejects the message' do
        stub_request(:post, %r{waba\.360dialog\.io/v1/messages})
          .to_return(status: 400, headers: { 'Content-Type' => 'application/json' },
                     body: { errors: [{ code: 1013, title: 'User is invalid',
                                        details: 'Recipient number is not a WhatsApp user' }] }.to_json)
        contact = create(:contact, :with_phone_number, account: account)
        contact.update_labels([label1.title])

        described_class.new(campaign: campaign).perform

        expect(campaign.campaign_recipients.first).to have_attributes(
          status: 'failed', error_code: '1013', error_title: 'User is invalid',
          error_message: 'Recipient number is not a WhatsApp user'
        )
      end
    end

    # [FORK / Onda 7 fatia 3] Endurecimento para volume, vale para os dois
    # providers. Ver custom/app/services/custom/whatsapp/oneoff_campaign_service.rb.
    context 'when hardened for volume' do
      let(:messages_url) { /graph\.facebook\.com.*messages/ }
      let(:pauses) { [] }
      let(:contact) do
        create(:contact, :with_phone_number, account: account).tap { |c| c.update_labels([label1.title]) }
      end

      def json_headers(extra = {})
        { 'Content-Type' => 'application/json' }.merge(extra)
      end

      def ok_response(id = 'wamid.ok')
        { status: 200, headers: json_headers, body: { messages: [{ id: id }] }.to_json }
      end

      before do
        # Registra em vez de dormir. Stub em `sleep` e nao em `pause`: `pause` mora
        # num modulo PREPENDADO (custom/), que ganha de qualquer stub feito na
        # classe -- o `sleep` real rodaria. `sleep` fica atras dele na cadeia.
        allow_any_instance_of(described_class).to receive(:sleep) { |_service, seconds| pauses << seconds } # rubocop:disable RSpec/AnyInstance
      end

      it 'only processes queued recipients when the campaign is resumed' do
        already_sent = create(:contact, :with_phone_number, account: account)
        already_sent.update_labels([label1.title])
        campaign.campaign_recipients.create!(account: account, inbox: whatsapp_inbox, contact: already_sent,
                                             status: :sent, source_id: 'wamid.before_the_crash')
        contact

        described_class.new(campaign: campaign).perform

        expect(a_request(:post, messages_url)).to have_been_made.once
        expect(campaign.campaign_recipients.find_by(contact: already_sent))
          .to have_attributes(status: 'sent', source_id: 'wamid.before_the_crash')
      end

      it 'does not resend to recipients that failed or were skipped earlier' do
        %i[failed skipped].each do |status|
          other = create(:contact, :with_phone_number, account: account)
          other.update_labels([label1.title])
          campaign.campaign_recipients.create!(account: account, inbox: whatsapp_inbox, contact: other, status: status)
        end

        described_class.new(campaign: campaign).perform

        expect(a_request(:post, messages_url)).not_to have_been_made
      end

      it 'skips the whole campaign at once when the template is not approved anymore' do
        campaign.update!(template_params: template_params.merge('name' => 'template_that_was_removed'))
        contact

        described_class.new(campaign: campaign).perform

        expect(a_request(:post, messages_url)).not_to have_been_made
        expect(campaign.campaign_recipients.first)
          .to have_attributes(status: 'skipped', error_message: 'Template not found or not approved; nothing was sent')
      end

      it 'paces the sends' do
        # id unico por chamada: source_id tem indice unico no destinatario
        stub_request(:post, messages_url).to_return do
          { status: 200, headers: json_headers, body: { messages: [{ id: SecureRandom.hex(6) }] }.to_json }
        end
        contact
        second = create(:contact, :with_phone_number, account: account)
        second.update_labels([label1.title])

        described_class.new(campaign: campaign).perform

        expect(pauses.count(0.3)).to eq(2)
      end

      it 'does not sleep between recipients when nothing is sent' do
        campaign.update!(template_params: template_params.merge('name' => 'template_that_was_removed'))
        contact

        described_class.new(campaign: campaign).perform

        expect(pauses).to be_empty
      end

      it 'retries a 429 honoring Retry-After and ends up sent' do
        stub_request(:post, messages_url)
          .to_return(status: 429, headers: json_headers('Retry-After' => '7'), body: { error: { message: 'Too many' } }.to_json)
          .then.to_return(ok_response('wamid.after_retry'))
        contact

        described_class.new(campaign: campaign).perform

        expect(a_request(:post, messages_url)).to have_been_made.twice
        expect(pauses).to include(7)
        expect(campaign.campaign_recipients.first).to have_attributes(status: 'sent', source_id: 'wamid.after_retry', error_message: nil)
      end

      it 'caps the wait suggested by the provider' do
        stub_request(:post, messages_url)
          .to_return(status: 429, headers: json_headers('Retry-After' => '3600'), body: {}.to_json)
          .then.to_return(ok_response)
        contact

        described_class.new(campaign: campaign).perform

        expect(pauses).to include(30)
        expect(pauses).not_to include(3600)
      end

      it 'gives up after three attempts on a persistent 429 and keeps the reason' do
        stub_request(:post, messages_url).to_return(status: 429, headers: json_headers, body: {}.to_json)
        contact

        described_class.new(campaign: campaign).perform

        expect(a_request(:post, messages_url)).to have_been_made.times(3)
        expect(pauses).to include(5, 15)
        expect(campaign.campaign_recipients.first)
          .to have_attributes(status: 'failed', error_message: 'WhatsApp provider returned HTTP 429')
      end

      it 'retries a 503 only when the provider says when to come back (Retry-After)' do
        stub_request(:post, messages_url)
          .to_return(status: 503, headers: json_headers('Retry-After' => '4'), body: {}.to_json)
          .then.to_return(ok_response('wamid.after_503'))
        contact

        described_class.new(campaign: campaign).perform

        expect(a_request(:post, messages_url)).to have_been_made.twice
        expect(campaign.campaign_recipients.first).to have_attributes(status: 'sent', source_id: 'wamid.after_503')
      end

      # 500/502/504 (e 503 sem Retry-After) sao o caso "o provider processou e a
      # resposta se perdeu". Reenviar cobraria duas vezes.
      [500, 502, 503, 504].each do |status|
        it "does not retry a #{status} without Retry-After: the provider may have processed the message" do
          stub_request(:post, messages_url)
            .to_return(status: status, headers: json_headers, body: {}.to_json)
            .then.to_return(ok_response('wamid.must_not_be_used'))
          contact

          described_class.new(campaign: campaign).perform

          expect(a_request(:post, messages_url)).to have_been_made.once
          expect(campaign.campaign_recipients.first)
            .to have_attributes(status: 'failed', error_message: "WhatsApp provider returned HTTP #{status}")
        end
      end

      # O last_provider_error so e reatribuido quando o provider responde: sem zerar
      # antes de cada tentativa, uma excecao de rede depois de um 429 deixaria o
      # status velho valendo e o envio seria repetido.
      it 'does not retry because of a stale 429 after a network error on the next attempt' do
        stub_request(:post, messages_url)
          .to_return(status: 429, headers: json_headers('Retry-After' => '1'), body: {}.to_json)
          .then.to_raise(SocketError.new('connection reset'))
          .then.to_return(ok_response('wamid.must_not_be_used'))
        contact

        described_class.new(campaign: campaign).perform

        expect(a_request(:post, messages_url)).to have_been_made.twice
        expect(campaign.campaign_recipients.first).to have_attributes(status: 'failed')
      end

      # A lista de destinatarios e carregada antes do envio: se outro job ja
      # enviou este destinatario, o objeto em memoria ainda diz `queued`.
      it 'skips a recipient that another run has already sent, even when the in-memory copy is stale' do
        stale = campaign.campaign_recipients.create!(account: account, inbox: whatsapp_inbox, contact: contact, status: :queued)
        CampaignRecipient.where(id: stale.id).update_all(status: CampaignRecipient.statuses[:sent], source_id: 'wamid.other_job') # rubocop:disable Rails/SkipsModelValidations

        described_class.new(campaign: campaign).send(:process_recipient, stale)

        expect(a_request(:post, messages_url)).not_to have_been_made
        expect(stale.reload).to have_attributes(status: 'sent', source_id: 'wamid.other_job')
      end

      # Sem o rescue por destinatario, um erro inesperado abortaria o job com a
      # campanha em `processing`; o reaper a retomaria e o mesmo erro a derrubaria
      # de novo, em loop.
      it 'does not abort the campaign when something unexpected raises for a recipient' do
        allow_any_instance_of(Liquid::CampaignTemplateService).to receive(:call).and_raise(Liquid::SyntaxError, 'bad liquid') # rubocop:disable RSpec/AnyInstance
        contact
        second = create(:contact, :with_phone_number, account: account)
        second.update_labels([label1.title])

        expect { described_class.new(campaign: campaign).perform }.not_to raise_error

        expect(campaign.reload.completed?).to be true
        expect(campaign.campaign_recipients.pluck(:status)).to all(eq('failed'))
        expect(campaign.campaign_recipients.first.error_message).to start_with('Unexpected error:')
      end

      it 'does not retry a definitive failure such as a 400' do
        stub_request(:post, messages_url)
          .to_return(status: 400, headers: json_headers, body: { error: { code: 131_026, message: 'Undeliverable' } }.to_json)
        contact

        described_class.new(campaign: campaign).perform

        expect(a_request(:post, messages_url)).to have_been_made.once
        expect(campaign.campaign_recipients.first).to have_attributes(status: 'failed', error_code: '131026')
      end

      # Sem chave de idempotencia no provider, reenviar apos timeout poderia
      # cobrar duas vezes.
      it 'does not retry a timeout and says the message may have been delivered' do
        stub_request(:post, messages_url).to_timeout
        contact

        described_class.new(campaign: campaign).perform

        expect(a_request(:post, messages_url)).to have_been_made.once
        expect(campaign.campaign_recipients.first)
          .to have_attributes(status: 'failed', error_message: 'Send timed out; the message may have been delivered')
      end

      it 'keeps processing the remaining recipients after one of them fails' do
        stub_request(:post, messages_url)
          .to_return(status: 400, headers: json_headers, body: { error: { message: 'bad number' } }.to_json)
          .then.to_return(ok_response('wamid.second'))
        contact
        second = create(:contact, :with_phone_number, account: account)
        second.update_labels([label1.title])

        described_class.new(campaign: campaign).perform

        expect(campaign.campaign_recipients.pluck(:status)).to contain_exactly('failed', 'sent')
        expect(campaign.reload.completed?).to be true
      end
    end

    context 'when campaign is valid' do
      it 'marks campaign as completed' do
        described_class.new(campaign: campaign).perform

        expect(campaign.reload.completed?).to be true
      end

      it 'marks the campaign completed after processing the audience' do
        contact = create(:contact, :with_phone_number, account: account)
        contact.update_labels([label1.title])

        expect(whatsapp_channel).to receive(:send_template) do
          expect(campaign.reload.completed?).to be false
        end

        described_class.new(campaign: campaign).perform

        expect(campaign.reload.completed?).to be true
      end

      it 'processes contacts with matching labels' do
        contact_with_label1, contact_with_label2, contact_with_both_labels =
          create_list(:contact, 3, :with_phone_number, account: account)
        contact_with_label1.update_labels([label1.title])
        contact_with_label2.update_labels([label2.title])
        contact_with_both_labels.update_labels([label1.title, label2.title])

        expect(whatsapp_channel).to receive(:send_template).exactly(3).times

        described_class.new(campaign: campaign).perform
      end

      it 'skips contacts without phone numbers' do
        contact_without_phone = create(:contact, account: account, phone_number: nil)
        contact_without_phone.update_labels([label1.title])

        expect(whatsapp_channel).not_to receive(:send_template)

        described_class.new(campaign: campaign).perform
      end

      it 'uses template processor service to process templates' do
        contact = create(:contact, :with_phone_number, account: account)
        contact.update_labels([label1.title])

        # [FORK] `at_least(:once)`: o override em custom/ confere o template uma vez
        # antes de enviar, alem da instancia que o proprio envio cria.
        expect(Whatsapp::TemplateProcessorService).to receive(:new)
          .with(channel: whatsapp_channel, template_params: template_params)
          .at_least(:once)
          .and_call_original

        described_class.new(campaign: campaign).perform
      end

      it 'sends template message with correct parameters' do
        contact = create(:contact, :with_phone_number, account: account)
        contact.update_labels([label1.title])

        expect(whatsapp_channel).to receive(:send_template).with(
          contact.phone_number,
          hash_including(
            name: 'ticket_status_updated',
            namespace: '23423423_2342423_324234234_2343224',
            lang_code: 'en',
            parameters: array_including(
              hash_including(
                type: 'body',
                parameters: array_including(
                  hash_including(type: 'text', parameter_name: 'name', text: 'John'),
                  hash_including(type: 'text', parameter_name: 'ticket_id', text: '2332')
                )
              )
            )
          ),
          nil
        )

        described_class.new(campaign: campaign).perform
      end

      it 'processes liquid variables in template parameters' do
        contact = create(:contact, :with_phone_number, account: account, name: 'Jane Smith', email: 'jane@example.com')
        contact.update_labels([label1.title])

        campaign_with_liquid = create(:campaign, inbox: whatsapp_inbox, account: account,
                                                 audience: [{ type: 'Label', id: label1.id }],
                                                 template_params: {
                                                   'name' => 'ticket_status_updated',
                                                   'namespace' => '23423423_2342423_324234234_2343224',
                                                   'category' => 'UTILITY',
                                                   'language' => 'en',
                                                   'processed_params' => {
                                                     'body' => {
                                                       'name' => '{{contact.name}}',
                                                       'ticket_id' => '{{contact.email}}'
                                                     }
                                                   }
                                                 })

        contact_drop_name = ContactDrop.new(contact).name

        expect(whatsapp_channel).to receive(:send_template).with(
          contact.phone_number,
          hash_including(
            name: 'ticket_status_updated',
            namespace: '23423423_2342423_324234234_2343224',
            lang_code: 'en',
            parameters: array_including(
              hash_including(
                type: 'body',
                parameters: array_including(
                  hash_including(type: 'text', parameter_name: 'name', text: contact_drop_name),
                  hash_including(type: 'text', parameter_name: 'ticket_id', text: contact.email)
                )
              )
            )
          ),
          nil
        )

        described_class.new(campaign: campaign_with_liquid).perform
      end

      it 'skips contacts when liquid variables resolve to blank values' do
        contact = create(:contact, :with_phone_number, account: account, name: 'Jane', email: nil)
        contact.update_labels([label1.title])

        campaign_with_blank_liquid = create(:campaign, inbox: whatsapp_inbox, account: account,
                                                       audience: [{ type: 'Label', id: label1.id }],
                                                       template_params: {
                                                         'name' => 'test_template',
                                                         'namespace' => 'test_namespace',
                                                         'language' => 'en',
                                                         'processed_params' => {
                                                           'body' => {
                                                             'email' => '{{contact.email}}'
                                                           }
                                                         }
                                                       })

        expect(whatsapp_channel).not_to receive(:send_template)
        expect(Rails.logger).to receive(:info).with("Skipping contact #{contact.name} - liquid variables resolved to blank values")
        allow(Rails.logger).to receive(:info)

        described_class.new(campaign: campaign_with_blank_liquid).perform
      end
    end

    context 'when template_params is missing' do
      let(:template_params) { nil }

      it 'skips contacts and logs error' do
        contact = create(:contact, :with_phone_number, account: account)
        contact.update_labels([label1.title])

        expect(Rails.logger).to receive(:error)
          .with("Skipping contact #{contact.name} - no template_params found for WhatsApp campaign")
        expect(whatsapp_channel).not_to receive(:send_template)

        described_class.new(campaign: campaign).perform
      end
    end

    context 'when send_template raises an error' do
      it 'logs error and continues processing remaining contacts' do
        contact_error, contact_success = create_list(:contact, 2, :with_phone_number, account: account)
        contact_error.update_labels([label1.title])
        contact_success.update_labels([label1.title])
        error_message = 'WhatsApp API error'

        allow(whatsapp_channel).to receive(:send_template).and_return(nil)

        expect(whatsapp_channel).to receive(:send_template).with(contact_error.phone_number, anything, nil).and_raise(StandardError, error_message)
        expect(whatsapp_channel).to receive(:send_template).with(contact_success.phone_number, anything, nil).once

        expect(Rails.logger).to receive(:error)
          .with("Failed to send WhatsApp template message to #{contact_error.phone_number}: #{error_message}")
        expect(Rails.logger).to receive(:error).with(/Backtrace:/)

        described_class.new(campaign: campaign).perform
        expect(campaign.reload.completed?).to be true
      end
    end
  end
end
