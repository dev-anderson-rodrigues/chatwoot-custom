require 'rails_helper'

describe '/app/login', type: :request do
  context 'without DEFAULT_LOCALE' do
    it 'renders the dashboard' do
      get '/app/login'
      expect(response).to have_http_status(:success)
    end
  end

  context 'with DEFAULT_LOCALE' do
    it 'renders the dashboard' do
      with_modified_env DEFAULT_LOCALE: 'pt_BR' do
        get '/app/login'
        expect(response).to have_http_status(:success)
        expect(response.body).to include "selectedLocale: 'pt_BR'"
      end
    end
  end

  context 'with non-HTML format' do
    it 'returns not acceptable for JSON with error message' do
      get '/app/login', headers: { 'Accept' => 'application/json' }
      expect(response).to have_http_status(:not_acceptable)
      expect(response.parsed_body).to eq({ 'error' => 'Please use API routes instead of dashboard routes for JSON requests' })
    end
  end

  # [Onda 6a] O <head> so pode citar a marca configurada. Antes desta onda o
  # bloco de DISPLAY_MANIFEST citava nove arquivos PNG e um manifest.json do
  # proprio Chatwoot, sempre -- independente do que o super admin configurasse.
  context 'with branding configured' do
    after { GlobalConfig.clear_cache }

    it 'nao referencia nenhum dos icones estaticos do Chatwoot' do
      get '/app/login'

      expect(response.body).not_to match(/android-icon|apple-icon-\d/)
    end

    it 'o icone de 512px e o apple-touch-icon usam LOGO_THUMBNAIL' do
      # O schema de teste do RSpec pula o hook que db:migrate tem em producao
      # (ConfigLoader.new.process via db_enhancements.rake), entao um banco de
      # teste "limpo" nao tem nenhuma InstallationConfig -- DISPLAY_MANIFEST
      # vem nil (falso). Numa instalacao real isso ja vem seedado. O
      # apple-touch-icon fica dentro do bloco `if DISPLAY_MANIFEST`, entao o
      # teste precisa garantir que ele esta ligado, senao testaria um bloco
      # que nunca renderiza.
      InstallationConfig.find_or_create_by(name: 'DISPLAY_MANIFEST') { |c| c.value = true }.update!(value: true)
      config = InstallationConfig.find_or_create_by(name: 'LOGO_THUMBNAIL') { |c| c.value = '/brand-assets/logo_thumbnail.svg' }
      config.update!(value: 'https://cdn.example.com/logo.png')
      GlobalConfig.clear_cache

      get '/app/login'

      expect(response.body).to include('<link rel="icon" type="image/png" sizes="512x512" href="https://cdn.example.com/logo.png">')
      expect(response.body).to include('<link rel="apple-touch-icon" href="https://cdn.example.com/logo.png">')
    end

    it 'com DISPLAY_MANIFEST desligado, so sobra o favicon dinamico' do
      config = InstallationConfig.find_or_create_by(name: 'DISPLAY_MANIFEST') { |c| c.value = true }
      config.update!(value: false)
      GlobalConfig.clear_cache

      get '/app/login'

      expect(response.body).not_to include('rel="manifest"')
      expect(response.body).not_to include('apple-touch-icon')
      expect(response.body).to include('sizes="512x512"')
    end

    # [Onda 6a / fatia 2]
    it 'usa BRAND_ACCENT_COLOR no theme-color e no msapplication-TileColor' do
      InstallationConfig.find_or_create_by(name: 'DISPLAY_MANIFEST') { |c| c.value = true }.update!(value: true)
      InstallationConfig.find_or_create_by(name: 'BRAND_ACCENT_COLOR') { |c| c.value = '#2781F6' }.update!(value: '#FF5733')
      GlobalConfig.clear_cache

      get '/app/login'

      expect(response.body).to include('<meta name="theme-color" content="#FF5733">')
      expect(response.body).to include('<meta name="msapplication-TileColor" content="#FF5733">')
    end

    it 'cai no azul padrao quando BRAND_ACCENT_COLOR nao esta configurado' do
      InstallationConfig.find_or_create_by(name: 'DISPLAY_MANIFEST') { |c| c.value = true }.update!(value: true)
      GlobalConfig.clear_cache

      get '/app/login'

      expect(response.body).to include('<meta name="theme-color" content="#2781F6">')
    end
  end

  # Routes are loaded once on app start
  # hence Rails.application.reload_routes! is used in this spec
  # ref : https://stackoverflow.com/a/63584877/939299
  context 'with CW_API_ONLY_SERVER true' do
    it 'returns 404' do
      with_modified_env CW_API_ONLY_SERVER: 'true' do
        Rails.application.reload_routes!
        get '/app/login'
        expect(response).to have_http_status(:not_found)
      end
      Rails.application.reload_routes!
    end
  end
end
