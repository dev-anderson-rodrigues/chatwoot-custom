require 'rails_helper'

describe ManifestsController, type: :request do
  # `find_or_create_by` (nao factory): estas linhas ja existem em toda conta
  # real, populadas pelo installation_config.yml. O teste so muda o valor.
  def set_config(name, value)
    config = InstallationConfig.find_or_create_by(name: name) { |c| c.value = value }
    config.value = value
    config.save!(validate: false)
    GlobalConfig.clear_cache
  end

  after { GlobalConfig.clear_cache }

  # `application/manifest+json` nao tem parser registrado em
  # ActionDispatch::IntegrationTest (so json/xml/html tem, nativamente) --
  # `response.parsed_body` devolveria a string crua em vez do hash. Registrar
  # um parser so para isto seria plumbing desproporcional a um endpoint;
  # `JSON.parse` direto e mais simples e igualmente explicito. Comportamento
  # real do content-type verificado manualmente contra o servidor (correto).
  # rubocop:disable Rails/ResponseParsedBody
  def manifest_body
    JSON.parse(response.body)
  end
  # rubocop:enable Rails/ResponseParsedBody

  describe 'GET /manifest.json' do
    it 'reflete o nome e a marca configurados, nao os do Chatwoot' do
      set_config('INSTALLATION_NAME', 'Nexora QA')
      set_config('BRAND_NAME', 'Nexora')

      get '/manifest.json'

      expect(response).to be_successful
      expect(response.media_type).to eq('application/manifest+json')
      expect(manifest_body['name']).to eq('Nexora QA')
      expect(manifest_body['short_name']).to eq('Nexora')
    end

    it 'usa LOGO_THUMBNAIL para os dois tamanhos de icone, sem inventar arquivo que a config nao tem' do
      set_config('LOGO_THUMBNAIL', 'https://cdn.example.com/logo.png')

      get '/manifest.json'

      icons = manifest_body['icons']
      expect(icons.map { |icon| icon['src'] }).to all(eq('https://cdn.example.com/logo.png'))
      expect(icons.map { |icon| icon['sizes'] }).to contain_exactly('192x192', '512x512')
    end

    # O campo aceita qualquer URL, e o padrao de instalacao e um .svg -- um
    # `type` fixo em image/png faria navegador estrito rejeitar o icone padrao.
    it 'infere o mime type da extensao do LOGO_THUMBNAIL' do
      set_config('LOGO_THUMBNAIL', '/brand-assets/logo_thumbnail.svg')
      get '/manifest.json'
      expect(manifest_body['icons'].first['type']).to eq('image/svg+xml')

      set_config('LOGO_THUMBNAIL', 'https://cdn.example.com/logo.jpg')
      get '/manifest.json'
      expect(manifest_body['icons'].first['type']).to eq('image/jpeg')

      set_config('LOGO_THUMBNAIL', 'https://cdn.example.com/logo-sem-extensao')
      get '/manifest.json'
      expect(manifest_body['icons'].first['type']).to eq('image/png')
    end

    # CDN com cache-busting (`?v=2`) e o caso comum que quebrava antes da
    # correcao: `File.extname` sobre a URL crua devolvia `.svg?v=2` inteiro,
    # nao batia com nenhum `when`, e anunciava svg como image/png.
    it 'ignora query string ao inferir o mime type' do
      set_config('LOGO_THUMBNAIL', 'https://cdn.example.com/logo.svg?v=2')

      get '/manifest.json'

      expect(manifest_body['icons'].first['type']).to eq('image/svg+xml')
    end

    it 'devolve icons vazio quando LOGO_THUMBNAIL nao esta configurado' do
      set_config('LOGO_THUMBNAIL', '')

      get '/manifest.json'

      expect(manifest_body['icons']).to eq([])
    end

    # [Onda 6a / fatia 2]
    it 'usa BRAND_ACCENT_COLOR para theme_color e background_color' do
      set_config('BRAND_ACCENT_COLOR', '#FF5733')

      get '/manifest.json'

      expect(manifest_body['theme_color']).to eq('#FF5733')
      expect(manifest_body['background_color']).to eq('#FF5733')
    end

    it 'cai no azul padrao quando BRAND_ACCENT_COLOR nao esta configurado' do
      set_config('BRAND_ACCENT_COLOR', '')

      get '/manifest.json'

      expect(manifest_body['theme_color']).to eq('#2781F6')
      expect(manifest_body['background_color']).to eq('#2781F6')
    end

    it 'nao exige sessao' do
      get '/manifest.json'
      expect(response).to be_successful
    end
  end

  describe 'GET /apple-touch-icon.png' do
    it 'redireciona para o LOGO_THUMBNAIL configurado' do
      set_config('LOGO_THUMBNAIL', 'https://cdn.example.com/logo.png')

      get '/apple-touch-icon.png'

      expect(response).to redirect_to('https://cdn.example.com/logo.png')
    end

    # Sem guard, `redirect_to("")` resolveria para a URL atual -- um redirect
    # para a propria rota, loop que so o navegador corta depois de varias
    # voltas. 404 e a resposta correta para "nao ha icone configurado".
    it 'devolve 404 em vez de um redirect vazio quando LOGO_THUMBNAIL nao esta configurado' do
      set_config('LOGO_THUMBNAIL', '')

      get '/apple-touch-icon.png'

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /apple-touch-icon-precomposed.png' do
    it 'redireciona para o mesmo LOGO_THUMBNAIL' do
      set_config('LOGO_THUMBNAIL', 'https://cdn.example.com/logo.png')

      get '/apple-touch-icon-precomposed.png'

      expect(response).to redirect_to('https://cdn.example.com/logo.png')
    end
  end
end
