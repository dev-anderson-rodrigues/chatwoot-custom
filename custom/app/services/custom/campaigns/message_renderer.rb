# [FORK] Renderiza o texto e o assunto da campanha para UM contato (Onda 7 / fatia 2).
#
# Usa o Liquid::CampaignTemplateService do upstream (drops contact/agent/inbox/account) e acrescenta o
# que uma cobranca em massa exige -- tudo com o mesmo desfecho, `Custom::Campaigns::Skip` (o contato
# nao recebe e o motivo aparece na tela de resultados):
#
#   - VARIAVEL VAZIA: o {{ contact.custom_attribute.valor }} sem o atributo renderiza "" e a cobranca
#     sairia "vence em ." -- mesmo criterio que o WhatsApp ja aplica aos parametros do template. Quem
#     quer aceitar vazio usa o filtro: {{ contact.name | default: 'cliente' }}.
#   - SINTAXE QUE NAO RENDERIZA: o servico do upstream rescue Liquid::Error e devolve o texto cru, com as
#     chaves, que iria ao cliente.
#   - MARCACAO NO VALOR (so no corpo): um nome ou atributo que o PROPRIO CONTATO controla (perfil do
#     Telegram, widget, API publica) passa pelo markdown do e-mail. "[Pague agora](http://x)" no nome
#     viraria link ativo numa cobranca com a marca do cliente -- phishing. So os VALORES sao examinados,
#     nunca o texto do operador, que pode ter markdown de proposito. Quem precisa de um link usa a URL
#     pura no atributo.
#
# Variavel entre crases ou dentro de {% raw %} e literal (o servico do upstream ja protege as crases),
# entao nao conta como variavel.
class Custom::Campaigns::MessageRenderer
  VARIABLE_PATTERN = /\{\{(.*?)\}\}/m
  UNRENDERED_PATTERN = /\{\{|\{%/
  LITERAL_PATTERN = /\{%-?\s*raw\s*-?%\}.*?\{%-?\s*endraw\s*-?%\}|`.*?`/m
  # Link/imagem em markdown e tag HTML dentro de um valor.
  MARKUP_PATTERN = %r{\]\(|!\[|<\s*/?\s*[a-z]}i

  pattr_initialize [:campaign!, :contact!]

  def body(template)
    render(template, guard_markup: true)
  end

  # Cabecalho de e-mail e texto puro: sem markdown, mas com CR/LF (a gem `mail` os codifica em vez de
  # injetar cabecalho, so que o assunto sairia com "=0D=0A" literal), entao viram espaco.
  def subject(template)
    render(template, guard_markup: false).gsub(/[[:cntrl:]]+/, ' ').squish
  end

  private

  def render(template, guard_markup:)
    checkable = template.gsub(LITERAL_PATTERN, '')
    values = variable_values(checkable)
    ensure_filled!(values)
    ensure_plain!(values) if guard_markup
    # O que sobra de chave em texto LITERAL (entre crases) e de proposito; so o resto tem de renderizar.
    raise Custom::Campaigns::Skip, reason('skip.liquid_syntax') if renderer.call(checkable).match?(UNRENDERED_PATTERN)

    renderer.call(template)
  end

  # { 'contact.name' => 'Maria', ... } -- o valor de cada variavel usada no texto, uma vez cada.
  def variable_values(template)
    template.scan(VARIABLE_PATTERN).flatten.map(&:strip).uniq.index_with do |expression|
      renderer.call("{{ #{expression} }}")
    end
  end

  def ensure_filled!(values)
    blank = values.select { |_expression, value| value.strip.empty? }.keys
    raise Custom::Campaigns::Skip, reason('skip.blank_variable', variables: format_variables(blank)) if blank.any?
  end

  def ensure_plain!(values)
    suspicious = values.select { |_expression, value| value.match?(MARKUP_PATTERN) }.keys
    raise Custom::Campaigns::Skip, reason('skip.unsafe_variable', variables: format_variables(suspicious)) if suspicious.any?
  end

  def format_variables(expressions)
    expressions.map { |expression| "{{ #{expression} }}" }.join(', ')
  end

  def renderer
    @renderer ||= Liquid::CampaignTemplateService.new(campaign: campaign, contact: contact)
  end

  def reason(key, **)
    Custom::Campaigns::Reasons.t(campaign.account, key, **)
  end
end
