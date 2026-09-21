# [FORK] Campanha de WhatsApp tambem para o provider 360dialog ('default').
#
# O upstream trava o disparo em massa em `provider == 'whatsapp_cloud'`, mas a
# trava e propria da feature de campanhas, nao uma limitacao do envio:
#
#   - Whatsapp360DialogService#send_template existe, com a mesma assinatura da
#     versao Cloud, e e o que o Chatwoot ja usa para reabrir conversa fora da
#     janela de 24h nos dois providers;
#   - os dois herdam process_response do BaseService, entao o retorno (id da
#     mensagem) tem o mesmo formato -- o override enterprise depende dele para
#     marcar o destinatario como enviado ou falho;
#   - os dois webhooks de entrada herdam de Whatsapp::IncomingMessageBaseService,
#     onde o modulo enterprise grava delivered/read/failed no destinatario.
#
# Lista explicita em vez de aceitar qualquer provider: um provider novo que o
# upstream venha a criar nao herda o disparo em massa por acidente.
module Custom::Whatsapp::OneoffCampaignService
  SUPPORTED_PROVIDERS = %w[default whatsapp_cloud].freeze

  private

  def validate_provider!
    return if SUPPORTED_PROVIDERS.include?(channel.provider)

    raise "WhatsApp provider not supported for campaigns: #{channel.provider}"
  end
end
