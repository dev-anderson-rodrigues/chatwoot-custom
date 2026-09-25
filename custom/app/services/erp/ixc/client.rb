require 'net/http'
require 'json'
require 'base64'

module Erp::Ixc
  class Client
    TIMEOUT = 10

    def initialize(hook:)
      @base_url = (hook.settings['api_url'] || hook.reference_id).to_s.chomp('/')
      @token    = hook.settings['api_token'] || hook.access_token
      @user_id  = hook.settings['api_user'] || '1'
    end

    # Busca cliente(s) por CPF/CNPJ (formato livre, normalizado internamente).
    def search_by_document(document)
      normalized = document.to_s.gsub(/\D/, '')
      return [] if normalized.blank?

      list('cliente',
           qtype: 'cliente.cnpj_cpf',
           query: document.to_s,
           oper: '=',
           rp: '5',
           sortname: 'cliente.id')
    end

    # Busca cliente(s) por número de celular (últimos 11 dígitos).
    def search_by_phone(phone)
      normalized = phone.to_s.gsub(/\D/, '').last(11)
      return [] if normalized.blank?

      results = list('cliente',
                     qtype: 'cliente.telefone_celular',
                     query: normalized,
                     oper: '=',
                     rp: '5',
                     sortname: 'cliente.id')
      return results if results.any?

      list('cliente',
           qtype: 'cliente.fone',
           query: normalized,
           oper: '=',
           rp: '5',
           sortname: 'cliente.id')
    end

    def get_customer(customer_id)
      list('cliente',
           qtype: 'cliente.id',
           query: customer_id.to_s,
           oper: '=',
           rp: '1',
           sortname: 'cliente.id').first
    end

    # status: 'A' = aberto, 'B' = baixado/pago, 'C' = cancelado
    def get_invoices(customer_id, status: 'A')
      list('fn_areceber',
           qtype: 'fn_areceber.id_cliente',
           query: customer_id.to_s,
           oper: '=',
           rp: '50',
           sortname: 'fn_areceber.data_vencimento',
           sortorder: 'desc',
           grid_param: JSON.generate([
                                       { 'TB' => 'fn_areceber.status', 'OP' => '=', 'P' => status }
                                     ]))
    end

    def get_contracts(customer_id)
      list('cliente_contrato',
           qtype: 'cliente_contrato.id_cliente',
           query: customer_id.to_s,
           oper: '=',
           rp: '20',
           sortname: 'cliente_contrato.id',
           sortorder: 'desc')
    end

    private

    def list(endpoint, params)
      body = { page: '1', sortorder: 'asc' }.merge(params)
      response = request(endpoint, body)
      records = response['registros']
      records.is_a?(Array) ? records : []
    end

    def request(endpoint, body)
      uri  = URI.parse("#{@base_url}/webservice/v1/#{endpoint}")
      http = build_http(uri)
      req  = build_request(uri.path, body)
      resp = http.request(req)
      parse_response(resp)
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise TimeoutError, e.message
    rescue JSON::ParserError => e
      raise RequestError, "JSON parse error: #{e.message}"
    end

    def build_http(uri)
      http              = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = uri.scheme == 'https'
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT
      http
    end

    def build_request(path, body)
      req                  = Net::HTTP::Get.new(path)
      req['Authorization'] = "Basic #{auth_header}"
      req['ixcsoft']       = 'listar'
      req['Content-Type']  = 'application/json'
      req.body             = body.to_json
      req
    end

    def parse_response(resp)
      raise AuthenticationError if resp.code == '401'
      raise RequestError, "HTTP #{resp.code}: #{resp.body}" unless resp.is_a?(Net::HTTPSuccess)

      JSON.parse(resp.body)
    end

    def auth_header
      Base64.strict_encode64("#{@user_id}:#{@token}")
    end
  end

  Error               = Class.new(StandardError)
  AuthenticationError = Class.new(Error)
  TimeoutError        = Class.new(Error)
  RequestError        = Class.new(Error)
end
