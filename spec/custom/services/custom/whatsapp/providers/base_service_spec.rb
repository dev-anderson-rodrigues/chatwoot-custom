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

  it 'devolve nil quando nao reconhece nenhum dos formatos, sem levantar erro' do
    expect(service.send(:parsed_error, response_with('foo' => 'bar'))).to be_nil
    expect(service.send(:parsed_error, response_with('errors' => []))).to be_nil
    expect(service.send(:parsed_error, response_with('errors' => ['texto solto']))).to be_nil
    expect(service.send(:parsed_error, response_with('nao e um hash'))).to be_nil
  end
end
