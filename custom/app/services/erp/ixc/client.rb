require 'net/http'
require 'json'
require 'base64'
require 'digest'

module Erp::Ixc
  class Client
    TIMEOUT = 10

    def initialize(hook:)
      @base_url = (hook.settings['api_url'] || hook.reference_id).to_s.chomp('/')
      @token    = hook.settings['api_token'] || hook.access_token
      @user_id  = hook.settings['api_user'] || '1'
    end

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

    # Busca faturas vencidas do mes corrente usando status_cobranca='P'.
    # Uma unica chamada à API: IXC ja filtra por mes e status de cobrança.
    def current_month_overdue_invoices(min_atraso: 1)
      today = Date.today
      body = {
        page: '1', rp: '1000',
        sortname: 'fn_areceber.data_vencimento', sortorder: 'asc',
        grid_param: JSON.generate([
                                    { 'TB' => 'fn_areceber.status',          'OP' => '=',  'P' => 'A' },
                                    { 'TB' => 'fn_areceber.status_cobranca', 'OP' => '=',  'P' => 'P' },
                                    { 'TB' => 'fn_areceber.data_vencimento', 'OP' => '>=', 'P' => today.beginning_of_month.to_s }
                                  ])
      }
      response = request('fn_areceber', body)
      raw = Array(response['registros'])
      raw.select do |r|
        due = Date.parse(r['data_vencimento']) rescue nil
        next false unless due
        (today - due).to_i >= min_atraso
      end
    end

    def customers_page(page:, per_page: 100)
      body = { page: page.to_s, rp: per_page.to_s, sortname: 'cliente.id', sortorder: 'asc' }
      response = request('cliente', body)
      { records: Array(response['registros']), total: response['total'].to_i }
    end

    CUSTOMER_FETCH_CONCURRENCY = 15
    CUSTOMER_CACHE_TTL         = 3600 # 1 hora em segundos

    # Busca clientes com cache Redis ($velma) TTL 1h + pool de threads para misses.
    def get_customers_by_ids(ids)
      return {} if ids.empty?

      result   = {}
      uncached = []
      ns       = cache_namespace

      ids.each do |id|
        raw = $velma.with { |r| r.get("ixc:#{ns}:customer:#{id}") } rescue nil
        if raw
          result[id.to_s] = JSON.parse(raw)
        else
          uncached << id
        end
      end

      unless uncached.empty?
        mutex = Mutex.new
        uncached.each_slice(CUSTOMER_FETCH_CONCURRENCY) do |slice|
          slice.map do |id|
            Thread.new do
              customer = get_customer(id) rescue nil
              next unless customer

              json = customer.to_json
              $velma.with { |r| r.setex("ixc:#{ns}:customer:#{id}", CUSTOMER_CACHE_TTL, json) } rescue nil
              mutex.synchronize { result[id.to_s] = customer }
            end
          end.each(&:join)
        end
      end

      result
    end

    def invalidate_customer_cache(id)
      ns = cache_namespace
      $velma.with { |r| r.del("ixc:#{ns}:customer:#{id}") } rescue nil
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
            req["Authorization"] = "Basic #{auth_header}"
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

    def cache_namespace
      Digest::MD5.hexdigest("#{@user_id}:#{@base_url}")[0, 8]
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
