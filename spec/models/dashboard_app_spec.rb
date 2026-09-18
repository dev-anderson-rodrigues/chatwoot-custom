require 'rails_helper'

RSpec.describe DashboardApp do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  def build_app(url)
    described_class.new(
      account: account,
      user: user,
      title: 'Painel do ERP',
      content: [{ 'type' => 'frame', 'url' => url }]
    )
  end

  describe 'content validation' do
    it 'accepts an ordinary https url' do
      expect(build_app('https://erp.exemplo.com/painel')).to be_valid
    end

    it 'accepts the url variables the dashboard app interpolates' do
      app = build_app('https://erp.exemplo.com/?c={account_id}&t={user_token}')

      # Se a validacao rejeitasse as chaves, a interpolacao da fatia 8 seria
      # inutil: o admin nao conseguiria salvar a URL que a usa.
      expect(app).to be_valid
    end

    it 'rejects a url that hides the real host behind userinfo' do
      app = build_app('https://host-confiavel.com@host-do-atacante.com/')

      expect(app).not_to be_valid
      expect(app.errors[:content]).to include(': URL must not contain userinfo')
    end

    it 'rejects userinfo with a password too' do
      app = build_app('https://confiavel.com:senha@host-do-atacante.com/')

      expect(app).not_to be_valid
      expect(app.errors[:content]).to include(': URL must not contain userinfo')
    end

    it 'still rejects what the schema already rejected' do
      app = build_app('ftp://erp.exemplo.com')

      expect(app).not_to be_valid
      expect(app.errors[:content]).to include(': Invalid data')
    end

    it 'does not report userinfo when the schema already failed' do
      app = build_app('nao-e-url')

      # Sem o retorno antecipado, uma URL invalida acumularia as duas mensagens
      # e a de userinfo confundiria quem le o erro.
      expect(app.errors[:content]).not_to include(': URL must not contain userinfo')
      expect(app).not_to be_valid
    end
  end
end
