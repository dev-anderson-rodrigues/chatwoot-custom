require 'rails_helper'

# [FORK] Motivo de falha do 360dialog. Ver custom/app/services/custom/whatsapp/
# providers/base_service.rb.
RSpec.describe Whatsapp::Providers::BaseService do
  subject(:service) { described_class.new(whatsapp_channel: Object.new) }

  def response_with(body)
    Struct.new(:parsed_response).new(body)
  end

  it 'esta na frente do modulo enterprise na cadeia de ancestrais' do
    ancestors = described_class.ancestors

    expect(ancestors.index(Custom::Whatsapp::Providers::BaseService))
      .to be < ancestors.index(Enterprise::Whatsapp::Providers::BaseService)
  end

  it 'le o erro do 360dialog, que vem numa lista em `errors`' do
    response = response_with(
      'errors' => [{ 'code' => 1013, 'title' => 'User is invalid', 'details' => 'Recipient number is not a WhatsApp user' }]
    )

    expect(service.send(:parsed_error, response)).to eq(
      code: 1013, title: 'User is invalid', message: 'Recipient number is not a WhatsApp user'
    )
  end

  # Formato que o proprio Whatsapp360DialogService#error_message documenta:
  # erro de requisicao (template/parametro invalido) vem em `meta`.
  it 'le o erro de requisicao do 360dialog, que vem em `meta`' do
    response = response_with(
      'meta' => { 'success' => false, 'http_code' => 400, 'developer_message' => 'template params invalid',
                  '360dialog_trace_id' => 'abc' }
    )

    expect(service.send(:parsed_error, response)).to eq(code: 400, message: 'template params invalid')
  end

  it 'ignora `meta` sem informacao de erro' do
    response = response_with('meta' => { 'api_status' => 'stable', 'version' => '2.x' })

    expect(service.send(:parsed_error, response)).to be_nil
  end

  it 'aceita `detail` e `message` no lugar de `details`' do
    response = response_with('errors' => [{ 'code' => 1, 'title' => 'T', 'detail' => 'via detail' }])
    expect(service.send(:parsed_error, response)).to include(message: 'via detail')

    response = response_with('errors' => [{ 'code' => 1, 'title' => 'T', 'message' => 'via message' }])
    expect(service.send(:parsed_error, response)).to include(message: 'via message')
  end

  it 'mantem a prioridade do formato da Meta quando os dois aparecem' do
    response = response_with(
      'error' => { 'code' => 131_026, 'message' => 'Message undeliverable' },
      'errors' => [{ 'code' => 1, 'title' => 'outro', 'details' => 'nao deveria ganhar' }]
    )

    expect(service.send(:parsed_error, response)).to include(code: 131_026, message: 'Message undeliverable')
  end

  # [Onda 7 / fatia 3] Status HTTP e Retry-After para distinguir falha transitoria.
  describe '#process_response' do
    def response_double(code:, body:, headers: {}, success: false)
      instance_double(HTTParty::Response, code: code, parsed_response: body, body: body.to_json,
                                          headers: headers, success?: success)
    end

    it 'guarda o status HTTP e o Retry-After junto do erro do provider' do
      response = response_double(code: 429, headers: { 'retry-after' => '12' },
                                 body: { 'error' => { 'code' => 130_429, 'message' => 'Rate limit hit' } })

      expect(service.process_response(response, nil)).to be_nil
      expect(service.last_error).to include(http_status: 429, retry_after: 12, code: 130_429, message: 'Rate limit hit')
    end

    it 'da um texto com o status quando o provider nao explicou o erro' do
      service.process_response(response_double(code: 502, body: { 'foo' => 'bar' }), nil)

      expect(service.last_error).to include(http_status: 502, message: 'WhatsApp provider returned HTTP 502')
    end

    it 'ignora Retry-After em formato de data HTTP' do
      response = response_double(code: 503, headers: { 'retry-after' => 'Wed, 21 Oct 2026 07:28:00 GMT' }, body: {})

      service.process_response(response, nil)

      expect(service.last_error).not_to have_key(:retry_after)
    end

    it 'mantem o motivo do 360dialog junto do status' do
      response = response_double(code: 400, body: { 'meta' => { 'http_code' => 400, 'developer_message' => 'bad params' } })

      service.process_response(response, nil)

      expect(service.last_error).to include(http_status: 400, code: 400, message: 'bad params')
    end

    it 'nao acrescenta erro nenhum quando o envio deu certo, e devolve o id da mensagem' do
      response = response_double(code: 200, success: true, body: { 'messages' => [{ 'id' => 'wamid.1' }] })

      expect(service.process_response(response, nil)).to eq('wamid.1')
      expect(service.last_error).to be_nil
    end
  end

  it 'devolve nil quando nao reconhece nenhum dos formatos, sem levantar erro' do
    expect(service.send(:parsed_error, response_with('foo' => 'bar'))).to be_nil
    expect(service.send(:parsed_error, response_with('errors' => []))).to be_nil
    expect(service.send(:parsed_error, response_with('errors' => ['texto solto']))).to be_nil
    expect(service.send(:parsed_error, response_with('nao e um hash'))).to be_nil
  end
end
