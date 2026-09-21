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
  private

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
