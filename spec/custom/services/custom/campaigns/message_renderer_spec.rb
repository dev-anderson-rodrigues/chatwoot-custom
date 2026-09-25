require 'rails_helper'

# [FORK] Renderizacao do texto/assunto da campanha para um contato. Ver
# custom/app/services/custom/campaigns/message_renderer.rb.
RSpec.describe Custom::Campaigns::MessageRenderer do
  let(:account) { create(:account) }
  let(:campaign) { create(:campaign, account: account, inbox: create(:channel_telegram, account: account).inbox) }
  let(:custom_attributes) { { 'valor' => '150,00', 'boleto' => 'https://pay.example/abc' } }
  let(:contact) { create(:contact, account: account, name: 'Maria', custom_attributes: custom_attributes) }
  let(:renderer) { described_class.new(campaign: campaign, contact: contact) }

  describe '#body' do
    it 'renderiza dados e atributos customizados do contato' do
      expect(renderer.body('Oi {{ contact.name }}, deve R$ {{ contact.custom_attribute.valor }}.')).to eq('Oi Maria, deve R$ 150,00.')
    end

    it 'texto sem variavel passa direto' do
      expect(renderer.body('Sua fatura vence amanha.')).to eq('Sua fatura vence amanha.')
    end

    it 'pula, com o nome da variavel, quando ela renderiza vazia' do
      expect { renderer.body('Deve {{ contact.custom_attribute.vencimento }}') }
        .to raise_error(Custom::Campaigns::Skip, 'Empty variable: {{ contact.custom_attribute.vencimento }}')
    end

    it 'lista todas as variaveis vazias, sem repetir' do
      expect { renderer.body('{{ contact.custom_attribute.a }} {{ contact.custom_attribute.b }} {{ contact.custom_attribute.a }}') }
        .to raise_error(Custom::Campaigns::Skip, 'Empty variable: {{ contact.custom_attribute.a }}, {{ contact.custom_attribute.b }}')
    end

    it 'aceita vazio quando o operador usa o filtro default' do
      expect(renderer.body("Vence {{ contact.custom_attribute.vencimento | default: 'em breve' }}")).to eq('Vence em breve')
    end

    it 'variavel so com espacos conta como vazia' do
      contact.update!(custom_attributes: { 'valor' => '   ' })

      expect { renderer.body('{{ contact.custom_attribute.valor }}') }.to raise_error(Custom::Campaigns::Skip, /Empty variable/)
    end

    it 'pula quando a sintaxe Liquid nao renderiza (o upstream devolveria o texto cru, com as chaves)' do
      expect { renderer.body('{% if contact.name %} oi') }.to raise_error(Custom::Campaigns::Skip, 'Invalid Liquid syntax in the message')
    end

    describe 'texto literal (entre crases ou em raw)' do
      it 'variavel entre crases e literal: nao conta como vazia nem como sintaxe quebrada' do
        expect(renderer.body('Use o codigo `{{ codigo }}` para pagar')).to eq('Use o codigo `{{ codigo }}` para pagar')
      end

      it 'variavel dentro de raw tambem' do
        expect(renderer.body('{% raw %}{{ codigo }}{% endraw %} e {{ contact.name }}')).to eq('{{ codigo }} e Maria')
      end

      it 'mas uma variavel de verdade ao lado de um literal ainda e conferida' do
        expect { renderer.body('`{{ codigo }}` e {{ contact.custom_attribute.nada }}') }.to raise_error(Custom::Campaigns::Skip, /Empty variable/)
      end
    end

    describe 'marcacao num valor vindo do contato (phishing por markdown)' do
      it 'pula quando o valor tem link em markdown' do
        contact.update!(name: '[Pague agora](http://evil.example/login)')

        expect { renderer.body('Oi {{ contact.name }}') }.to raise_error(Custom::Campaigns::Skip, 'Suspicious formatting in variable: {{ contact.name }}')
      end

      it 'pula quando o valor tem imagem em markdown (pixel de rastreio)' do
        contact.update!(custom_attributes: { 'valor' => '![x](http://track.example/p.png)' })

        expect { renderer.body('{{ contact.custom_attribute.valor }}') }.to raise_error(Custom::Campaigns::Skip, /Suspicious formatting/)
      end

      it 'pula quando o valor tem tag HTML' do
        contact.update!(custom_attributes: { 'valor' => '<img src=x onerror=alert(1)>' })

        expect { renderer.body('{{ contact.custom_attribute.valor }}') }.to raise_error(Custom::Campaigns::Skip, /Suspicious formatting/)
      end

      it 'URL pura num atributo passa (link de boleto e o caso de uso)' do
        expect(renderer.body('Pague: {{ contact.custom_attribute.boleto }}')).to eq('Pague: https://pay.example/abc')
      end

      it 'o markdown que o OPERADOR escreve no texto nao e examinado' do
        expect(renderer.body('Pague [aqui](https://pay.example/abc), {{ contact.name }}.')).to eq('Pague [aqui](https://pay.example/abc), Maria.')
      end
    end
  end

  describe '#subject' do
    it 'renderiza variaveis' do
      expect(renderer.subject('Fatura de {{ contact.name }}')).to eq('Fatura de Maria')
    end

    it 'troca quebra de linha e caracteres de controle por espaco (senao o assunto sai com =0D=0A)' do
      contact.update!(custom_attributes: { 'ref' => "123\r\nBcc: evil@evil.example\r\nX-Injected: 1" })

      subject_line = renderer.subject('Fatura {{ contact.custom_attribute.ref }}')

      expect(subject_line).to eq('Fatura 123 Bcc: evil@evil.example X-Injected: 1')
      expect(subject_line).not_to match(/[[:cntrl:]]/)
    end

    it 'o assunto nao passa pelo markdown, entao a checagem de marcacao nao se aplica' do
      contact.update!(name: '[Maria](x)')

      expect(renderer.subject('Fatura de {{ contact.name }}')).to include('[maria](x)')
    end

    it 'pula tambem quando o assunto tem variavel vazia' do
      expect { renderer.subject('Fatura {{ contact.custom_attribute.fatura }}') }.to raise_error(Custom::Campaigns::Skip, /Empty variable/)
    end
  end

  describe 'idioma dos motivos' do
    it 'usa o idioma da conta' do
      account.update!(locale: 'pt_BR')

      expect { renderer.body('{{ contact.custom_attribute.nada }}') }.to raise_error(Custom::Campaigns::Skip, 'Variável vazia: {{ contact.custom_attribute.nada }}')
    end

    it 'formatacao suspeita tambem sai traduzida' do
      account.update!(locale: 'pt_BR')
      contact.update!(name: '[a](b)')

      expect { renderer.body('{{ contact.name }}') }.to raise_error(Custom::Campaigns::Skip, 'Formatação suspeita na variável: {{ contact.name }}')
    end
  end
end
