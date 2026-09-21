# [FORK] Campanha de WhatsApp: liberada para o 360dialog e endurecida para volume.
#
# 1) PROVIDER ('default' = 360dialog)
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
#
# 2) VOLUME (Onda 7 / fatia 3)
#
# Riscos que a revisao de integracao apontou no upstream, para os dois providers:
#
#   - reexecutar reenviava para quem ja recebeu (process_recipient nao olhava o
#     status) -- agora so processa destinatario `queued`;
#   - um provider lento segurava o job inteiro (HTTParty sem timeout) -- agora ha
#     timeout por envio;
#   - um 429 virava falha permanente -- agora 429 (e 503 com Retry-After) sao
#     tentados de novo, com backoff. 500/502/504 e timeout NAO: o provider pode ter
#     processado e a resposta se perdido, e reenviar cobraria duas vezes;
#   - um erro inesperado num destinatario derrubava a campanha e, com o reaper,
#     em loop -- agora so aquele destinatario falha;
#   - template removido/pausado depois de criar a campanha gerava um POST fadado
#     a falhar POR CONTATO -- agora a campanha inteira e pulada de uma vez.
#
# A campanha presa em `processing` quando o job morre e tratada a parte, por
# Custom::Campaigns::ResetStaleProcessingJob.
#
# Configuravel por ambiente (padroes conservadores):
#   CAMPAIGN_SEND_INTERVAL_MS       pausa entre envios (padrao 300 => ~3 msg/s)
#   CAMPAIGN_SEND_TIMEOUT_SECONDS   teto de cada envio (padrao 30)
module Custom::Whatsapp::OneoffCampaignService
  SUPPORTED_PROVIDERS = %w[default whatsapp_cloud].freeze

  MAX_SEND_ATTEMPTS = 3
  # Espera antes da 2a e da 3a tentativa, quando o provider nao manda Retry-After.
  RETRY_DELAYS = [5, 15].freeze
  # Teto para o Retry-After: o job ocupa um worker enquanto espera.
  MAX_RETRY_WAIT = 30
  TIMEOUT_MESSAGE = 'Send timed out; the message may have been delivered'.freeze

  private

  def validate_provider!
    return if SUPPORTED_PROVIDERS.include?(channel.provider)

    raise "WhatsApp provider not supported for campaigns: #{channel.provider}"
  end

  # So `queued`: numa retomada (job que morreu no meio), quem ja foi enviado,
  # entregue, lido, falhou ou foi pulado NAO e reenviado.
  #
  # `reload`, nao o objeto em memoria: a lista de destinatarios e carregada ANTES
  # do envio, e se dois jobs correrem a mesma campanha (so acontece se o reaper
  # errar) cada um enxergaria a lista inteira como `queued` e enviaria tudo duas
  # vezes. Com o reload, quem o outro job ja enviou e pulado. Sobra uma janela do
  # tamanho de UM envio para o mesmo destinatario nos dois jobs; fecha-la de vez
  # pede um marcador de "enviando" que o enum do destinatario nao tem. Tambem
  # sobra a janela entre o POST e o mark_sent!, que sem chave de idempotencia no
  # provider nao da para fechar.
  #
  # O rescue e o que impede um destinatario "venenoso" de derrubar a campanha: o
  # override enterprise so protege o ENVIO, nao a renderizacao Liquid da mensagem
  # nem a gravacao do conteudo. Uma mensagem de campanha com sintaxe Liquid
  # invalida, por exemplo, levantaria no primeiro contato, o job abortaria com a
  # campanha em `processing`, o reaper a retomaria 10 min depois e o mesmo erro a
  # derrubaria de novo -- em loop, sem nunca chegar aos demais.
  def process_recipient(recipient)
    return unless recipient.reload.queued?

    super
  rescue StandardError => e
    fail_recipient_safely(recipient, e)
  end

  # Nao pode levantar: e o ultimo recurso. Se nem a gravacao da falha funcionar
  # (destinatario apagado no meio da execucao, por exemplo), so registra no log.
  def fail_recipient_safely(recipient, error)
    Rails.logger.error "Campaign #{campaign.id} recipient #{recipient.id}: #{error.class}: #{error.message}"
    recipient.mark_failed!(message: "Unexpected error: #{error.message}".truncate(500))
  rescue StandardError => e
    Rails.logger.error "Campaign #{campaign.id} recipient #{recipient.id}: could not record the failure (#{e.message})"
  end

  def skip_for_unavailable_template(recipient)
    recipient.mark_skipped!('Template not found or not approved; nothing was sent')
  end

  # Uma vez por execucao. `nil` de params = template nao achado/aprovado; `[]` =
  # achado e sem variaveis (por isso `nil?` e nao `blank?`). Qualquer erro ao
  # conferir NAO barra a campanha: o envio normal decide, como antes.
  def template_available?
    return @template_available if defined?(@template_available)

    @template_available = compute_template_available
  end

  def compute_template_available
    return true if campaign.template_params.blank?

    _name, _namespace, _lang, params = Whatsapp::TemplateProcessorService.new(
      channel: channel, template_params: campaign.template_params
    ).call
    !params.nil?
  rescue StandardError => e
    Rails.logger.error "Campaign #{campaign.id}: template check failed (#{e.message}); sending anyway"
    true
  end

  # O `super` (override enterprise) envia e grava o resultado no destinatario.
  # Aqui ficam a conferencia do template, o teto de tempo, a nova tentativa de
  # falha transitoria e o ritmo entre envios.
  #
  # A conferencia do template fica AQUI, imediatamente antes de enviar, e nao no
  # inicio do process_recipient: quem seria pulado por outro motivo (sem telefone,
  # variavel Liquid vazia) continua com o motivo original, e o ritmo so vale para
  # quem foi mesmo enviado -- pular a campanha inteira nao pode dormir 0,3s por
  # contato.
  def send_whatsapp_template_message(recipient:, to:, template_params:)
    return skip_for_unavailable_template(recipient) unless template_available?

    attempt = 1
    loop do
      forget_last_provider_error
      Timeout.timeout(send_timeout) { super }
      break unless retry_send?(recipient, attempt)

      pause(retry_delay(attempt))
      reset_for_retry(recipient)
      attempt += 1
    end
    pause(send_interval)
  rescue Timeout::Error
    recipient.mark_failed!(message: TIMEOUT_MESSAGE)
  ensure
    humanize_timeout(recipient)
  end

  # O rescue do enterprise engole o Timeout dentro do `super` e grava
  # 'execution expired' -- texto que nao diz que a mensagem pode ter saido.
  def humanize_timeout(recipient)
    return unless recipient.reload.failed? && recipient.error_message == 'execution expired'

    recipient.update!(error_message: TIMEOUT_MESSAGE)
  end

  # A REGRA de quando repetir e a parte que mais importa, porque reenviar sem chave
  # de idempotencia no provider pode cobrar duas vezes:
  #
  #   429            o provider recusou ANTES de processar (limite de vazao): seguro.
  #   503 + Retry-After   indisponivel e disse quando voltar: seguro.
  #   500, 502, 504, 503 sem Retry-After   o caso de "processou e a resposta se
  #                  perdeu" (gateway derrubou a conexao depois de aceitar): NAO
  #                  repete -- falha com o status registrado e o operador decide.
  #   timeout        idem: a requisicao pode ter chegado.
  #   erro de rede   a excecao morre no rescue do enterprise sem status HTTP; nao
  #                  e tentada de novo (nao da para saber se chegou).
  def retry_send?(recipient, attempt)
    return false if attempt >= MAX_SEND_ATTEMPTS

    recipient.reload.failed? && transient_error?(channel.last_provider_error)
  end

  def transient_error?(error)
    return false if error.blank?

    error[:http_status] == 429 || (error[:http_status] == 503 && error[:retry_after].present?)
  end

  # O `last_provider_error` do canal so e reatribuido quando o provider RESPONDE.
  # Uma excecao de rede numa tentativa seguinte deixaria o 429 da anterior valendo,
  # e `retry_send?` reenviaria por causa de um status velho. Zerar antes de cada
  # tentativa (o enterprise so expoe o leitor).
  def forget_last_provider_error
    channel.instance_variable_set(:@last_provider_error, nil)
  end

  def retry_delay(attempt)
    provider_wait = channel.last_provider_error&.dig(:retry_after)
    [provider_wait || RETRY_DELAYS[attempt - 1] || RETRY_DELAYS.last, MAX_RETRY_WAIT].min
  end

  def reset_for_retry(recipient)
    recipient.update!(status: :queued, failed_at: nil, error_code: nil, error_title: nil, error_message: nil)
  end

  def send_interval
    ENV.fetch('CAMPAIGN_SEND_INTERVAL_MS', 300).to_f / 1000
  end

  def send_timeout
    ENV.fetch('CAMPAIGN_SEND_TIMEOUT_SECONDS', 30).to_i
  end

  # Metodo proprio (e nao `sleep` solto) para os specs poderem trocar.
  def pause(seconds)
    sleep(seconds) if seconds.to_f.positive?
  end
end
