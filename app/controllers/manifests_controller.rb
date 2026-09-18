# [Onda 6a] O manifest.json e os icones de convencao (apple-touch-icon*) do
# instalador nao podem ser arquivos estaticos: eles fixavam o logo e o nome do
# Chatwoot, nao da marca configurada. config.public_file_server.enabled roda
# ANTES do router, entao os arquivos estaticos equivalentes tiveram que sair de
# public/ para estas rotas serem alcancadas.
class ManifestsController < ActionController::Base
  # [Onda 6a / fatia 2] Mesmo valor que estava fixo aqui antes de
  # BRAND_ACCENT_COLOR existir -- config ausente ou vazia (campo limpo no
  # super admin, ou banco sem seed, ver nota de fatia 1) cai neste padrao em
  # vez de gerar `theme_color: nil` no manifest.
  DEFAULT_ACCENT_COLOR = '#2781F6'.freeze
  # apple-touch-icon.png / apple-touch-icon-precomposed.png: convencao do
  # Safari/iOS, descoberta por caminho fixo sem nenhuma tag <link> -- nao tem
  # como apontar para a config de outra forma que nao seja responder aqui.
  # Redirect (nao proxy): LOGO_THUMBNAIL pode ser uma URL externa, e buscar e
  # repassar os bytes aqui duplicaria o trabalho que o proprio navegador ja
  # faz ao seguir o redirect.
  # Sem guard, um LOGO_THUMBNAIL vazio (campo limpo e salvo no super admin)
  # viraria `redirect_to("")`, que o Rails resolve para a URL atual -- um
  # redirect para a propria rota, loop que so o navegador corta depois de
  # varias voltas. 404 e a resposta correta para "nao ha icone configurado".
  def apple_touch_icon
    return head :not_found if logo_thumbnail.blank?

    redirect_to logo_thumbnail, allow_other_host: true
  end

  def show
    render json: manifest, content_type: 'application/manifest+json'
  end

  private

  def global_config
    @global_config ||= GlobalConfig.get('INSTALLATION_NAME', 'BRAND_NAME', 'LOGO_THUMBNAIL', 'BRAND_ACCENT_COLOR')
  end

  def logo_thumbnail
    global_config['LOGO_THUMBNAIL']
  end

  # O formato hex ja e validado na escrita (InstallationConfig#brand_accent_color_format);
  # aqui so cobre a ausencia -- campo nunca configurado, limpo no super admin,
  # ou banco de teste sem seed (ver nota de fatia 1) -- sem repetir a validacao.
  def accent_color
    global_config['BRAND_ACCENT_COLOR'].presence || DEFAULT_ACCENT_COLOR
  end

  # Duas entradas para a MESMA imagem, tamanhos diferentes declarados: sem
  # processamento de imagem no servidor, e a config so guarda uma URL (o campo
  # ja documenta thumbnail 512x512, responsabilidade de quem preenche). Chrome
  # exige um icone >=192 e idealmente um >=512 para elegibilidade de instalacao
  # PWA -- declarar os dois a partir do mesmo arquivo cobre o criterio sem
  # inventar tamanhos que a config nao tem.
  #
  # Sem icone (LOGO_THUMBNAIL vazio): array vazio, nao uma entrada com `src`
  # em branco -- um icone sem imagem nao e um icone menor, e invalido.
  def manifest
    {
      name: global_config['INSTALLATION_NAME'],
      short_name: global_config['BRAND_NAME'],
      icons: icons,
      start_url: '/',
      display: 'standalone',
      background_color: accent_color,
      theme_color: accent_color
    }
  end

  def icons
    return [] if logo_thumbnail.blank?

    [
      { src: logo_thumbnail, sizes: '192x192', type: icon_mime_type },
      { src: logo_thumbnail, sizes: '512x512', type: icon_mime_type }
    ]
  end

  # A config aceita qualquer URL, e o valor padrao e um .svg -- declarar
  # image/png fixo faria navegadores estritos rejeitarem o icone quando o
  # admin usa o padrao. Sniffa pela extensao; sem extensao reconhecida, cai em
  # png (o formato que o proprio texto de ajuda do campo pede).
  #
  # `URI.parse(...).path`, nao `logo_thumbnail` cru: um CDN com cache-busting
  # (`logo.svg?v=2`) faria `File.extname` devolver `.svg?v=2` inteiro, que nao
  # bate com nenhum `when` e cai no `else` errado -- svg anunciado como png.
  # Falha de parse (URL malformada) usa o valor cru como fallback: pior caso e
  # o mesmo comportamento de antes desta protecao, nao um erro novo.
  def icon_mime_type
    path = begin
      URI.parse(logo_thumbnail.to_s).path
    rescue URI::InvalidURIError
      logo_thumbnail.to_s
    end

    case File.extname(path.to_s).delete('.').downcase
    when 'svg' then 'image/svg+xml'
    when 'jpg', 'jpeg' then 'image/jpeg'
    else 'image/png'
    end
  end
end
