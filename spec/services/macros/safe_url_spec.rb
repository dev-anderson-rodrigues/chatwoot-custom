require 'rails_helper'

RSpec.describe Macros::SafeUrl do
  describe '.public_http?' do
    # Resolv e stubado para o teste nao depender de DNS de verdade.
    def stub_resolve(host, addresses)
      allow(Resolv).to receive(:getaddresses).with(host).and_return(addresses)
    end

    context 'when the host resolves to a public address' do
      it 'allows it' do
        stub_resolve('example.com', ['93.184.216.34'])
        expect(described_class.public_http?('https://example.com/webhook')).to be true
      end
    end

    context 'when the scheme is not http(s)' do
      %w[file:///etc/passwd ftp://example.com gopher://example.com javascript:alert(1)].each do |url|
        it "rejects #{url}" do
          expect(described_class.public_http?(url)).to be false
        end
      end
    end

    context 'when the host resolves into a blocked range' do
      {
        'loopback' => '127.0.0.1',
        'metadata de cloud (link-local)' => '169.254.169.254',
        'privada classe A' => '10.1.2.3',
        'privada classe B' => '172.16.5.4',
        'privada classe C' => '192.168.1.1',
        'CGNAT' => '100.64.0.1',
        'this network' => '0.0.0.0',
        'multicast' => '224.0.0.1',
        'reservado' => '240.0.0.1',
        'loopback v6' => '::1',
        'unique local v6' => 'fc00::1',
        'link-local v6' => 'fe80::1'
      }.each do |label, address|
        it "rejects #{label} (#{address})" do
          stub_resolve('evil.test', [address])
          expect(described_class.public_http?('http://evil.test/x')).to be false
        end
      end

      it 'rejects loopback written as an ipv4-mapped ipv6 address' do
        stub_resolve('evil.test', ['::ffff:127.0.0.1'])
        expect(described_class.public_http?('http://evil.test/x')).to be false
      end

      it 'rejects when only one of several addresses is private' do
        stub_resolve('evil.test', ['93.184.216.34', '127.0.0.1'])
        expect(described_class.public_http?('http://evil.test/x')).to be false
      end
    end

    context 'when the hostname itself is internal' do
      %w[http://localhost/x http://redis.local/x http://api.internal/x http://foo.localhost/x].each do |url|
        it "rejects #{url}" do
          expect(described_class.public_http?(url)).to be false
        end
      end
    end

    context 'when resolution fails or is empty' do
      it 'fails closed on an empty answer' do
        stub_resolve('nowhere.test', [])
        expect(described_class.public_http?('http://nowhere.test/x')).to be false
      end

      it 'fails closed when the resolver raises' do
        allow(Resolv).to receive(:getaddresses).and_raise(Resolv::ResolvError)
        expect(described_class.public_http?('http://nowhere.test/x')).to be false
      end
    end

    context 'when the url is malformed or blank' do
      [nil, '', '   ', 'http://', 'not a url'].each do |url|
        it "rejects #{url.inspect}" do
          expect(described_class.public_http?(url)).to be false
        end
      end
    end

    context 'when ALLOW_PRIVATE_WEBHOOK_URLS is on' do
      it 'lets private addresses through (escape hatch de desenvolvimento)' do
        with_modified_env ALLOW_PRIVATE_WEBHOOK_URLS: 'true' do
          expect(described_class.public_http?('http://localhost:3000/x')).to be true
        end
      end
    end
  end
end
