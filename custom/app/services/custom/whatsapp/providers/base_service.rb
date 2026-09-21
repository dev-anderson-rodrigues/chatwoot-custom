# [FORK] Motivo de falha do 360dialog no rastreio de entrega das campanhas.
#
# O modulo enterprise (Enterprise::Whatsapp::Providers::BaseService#parsed_error)
# so entende o formato de erro da Meta/Cloud API -- um objeto em `error`. O
# 360dialog responde de duas outras formas, e sem tratar as duas um envio que
# falha devolve `last_error` nil: a tabela de entrega da campanha mostraria so o
# texto generico "WhatsApp provider did not return a message id" no lugar do
# motivo real (numero sem WhatsApp, template invalido...) -- justamente a
# informacao que quem dispara uma cobranca precisa.
#
#   1. Erro de REQUISICAO (template ou parametro invalido, chave errada): objeto
#      `meta` com `http_code` e `developer_message`. E o formato que o proprio
#      Whatsapp360DialogService#error_message ja documenta e le.
#   2. Erro de ENTREGA no nivel do WhatsApp: lista `errors` com
#      code/title/details.
#
# O formato da Meta continua tendo prioridade (super); so cai aqui quando ele
# nao reconheceu nada. Tolerante a variacao de chave (`details`/`detail`/
# `message`) porque o segundo formato foi tratado pela documentacao da 360dialog,
# nao contra uma conta real.
module Custom::Whatsapp::Providers::BaseService
  # [Onda 7 / fatia 3] Guarda o status HTTP e o Retry-After junto do erro.
  #
  # Quem dispara campanha precisa distinguir falha TRANSITORIA (429, 5xx: vale
  # tentar de novo) de DEFINITIVA (400: numero sem WhatsApp, template invalido).
  # O `process_response` do upstream descarta o status e devolve so nil, e o
  # `parsed_error` acima e nil quando o corpo nao e reconhecido -- sem isto, um
  # 429 e um 400 ficam indistinguiveis. Vale para os dois providers.
  #
  # `message` ganha um texto padrao com o status quando o provider nao explicou:
  # melhor "returned HTTP 502" do que o generico "did not return a message id".
  #
  # No process_response (e nao no handle_error): la a resposta HTTP e sempre real,
  # e o handle_error continua exatamente como o upstream -- os testes dele o chamam
  # direto com um duble estrito que so tem `body` e `parsed_response`.
  def process_response(response, message)
    message_id = super
    add_http_details_to_last_error(response) if message_id.nil?
    message_id
  end

  private

  def add_http_details_to_last_error(response)
    @last_error = (last_error || {}).merge(
      http_status: response.code, retry_after: retry_after_seconds(response)
    ).compact
    @last_error[:message] ||= "WhatsApp provider returned HTTP #{response.code}"
  end

  # Retry-After em segundos. Data HTTP (o outro formato permitido) e ignorada:
  # vira nil e o chamador usa o backoff padrao.
  def retry_after_seconds(response)
    Integer(response.headers['retry-after'].to_s, 10, exception: false)
  end

  def parsed_error(response)
    super || parsed_360dialog_error(response)
  end

  def parsed_360dialog_error(response)
    parsed_response = response.parsed_response
    return unless parsed_response.is_a?(Hash)

    listed_360dialog_error(parsed_response) || meta_360dialog_error(parsed_response)
  end

  def listed_360dialog_error(parsed_response)
    error = Array(parsed_response['errors']).first
    return unless error.is_a?(Hash)

    {
      code: error['code'],
      title: error['title'],
      message: error['details'].presence || error['detail'].presence || error['message'].presence
    }.compact_blank.presence
  end

  def meta_360dialog_error(parsed_response)
    meta = parsed_response['meta']
    return unless meta.is_a?(Hash)

    { code: meta['http_code'], message: meta['developer_message'].presence }.compact_blank.presence
  end
end
