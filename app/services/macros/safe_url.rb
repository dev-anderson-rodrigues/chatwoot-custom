require 'ipaddr'
require 'resolv'

# Guarda de SSRF para as URLs que a macro pode acionar: o `lookup_url` de um
# input_field e a URL do action `send_webhook_event`. Ambas sao escritas por
# quem edita a macro, entao um agente com permissao de macro global poderia
# apontar para a rede interna da instalacao (metadata de cloud, Redis, Postgres,
# admin interno) e usar a resposta como canal de exfiltracao.
#
# A politica e fail-closed: qualquer duvida -- DNS que nao resolve, IP que nao
# parseia, esquema estranho -- devolve false.
class Macros::SafeUrl
  PRIVATE_RANGES = [
    IPAddr.new('0.0.0.0/8'),        # "this network"
    IPAddr.new('10.0.0.0/8'),       # privada
    IPAddr.new('100.64.0.0/10'),    # CGNAT
    IPAddr.new('127.0.0.0/8'),      # loopback
    IPAddr.new('169.254.0.0/16'),   # link-local (metadata de cloud fica aqui)
    IPAddr.new('172.16.0.0/12'),    # privada
    IPAddr.new('192.0.0.0/24'),     # IETF protocol assignments
    IPAddr.new('192.168.0.0/16'),   # privada
    IPAddr.new('198.18.0.0/15'),    # benchmark
    IPAddr.new('224.0.0.0/4'),      # multicast
    IPAddr.new('240.0.0.0/4'),      # reservado
    IPAddr.new('::1/128'),          # loopback v6
    IPAddr.new('fc00::/7'),         # unique local v6
    IPAddr.new('fe80::/10')         # link-local v6
  ].freeze

  BLOCKED_SUFFIXES = %w[.local .internal .localhost].freeze

  class << self
    def public_http?(url)
      uri = parse(url)
      return false unless valid_http_uri?(uri)
      return true if allow_private?

      host = uri.host.downcase
      return false if blocked_suffix?(host)

      resolves_to_public_addresses?(host)
    end

    private

    def parse(url)
      URI.parse(url.to_s)
    rescue URI::InvalidURIError
      nil
    end

    def valid_http_uri?(uri)
      uri.present? && %w[http https].include?(uri.scheme) && uri.host.present?
    end

    def resolves_to_public_addresses?(host)
      addresses = resolve(host)
      # Host que nao resolve nao e "seguro por nao existir": pode ser DNS
      # interno intermitente. Fail-closed.
      return false if addresses.empty?

      addresses.none? { |addr| private_address?(addr) }
    end

    def blocked_suffix?(host)
      BLOCKED_SUFFIXES.any? { |suffix| host == suffix.delete_prefix('.') || host.end_with?(suffix) }
    end

    def resolve(host)
      Resolv.getaddresses(host)
    rescue StandardError
      []
    end

    def private_address?(addr)
      ip = IPAddr.new(addr.to_s)
      # ::ffff:127.0.0.1 e loopback escrito como IPv6: sem normalizar, ele nao
      # bate com a faixa 127.0.0.0/8 e passaria batido.
      ip = ip.native if ip.ipv4_mapped?
      PRIVATE_RANGES.any? { |range| range.include?(ip) }
    rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
      true
    end

    # Escape hatch de desenvolvimento: em docker-compose o webhook costuma
    # apontar para outro container, que resolve para IP privado. Nunca ligar
    # em producao.
    def allow_private?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch('ALLOW_PRIVATE_WEBHOOK_URLS', 'false'))
    end
  end
end
