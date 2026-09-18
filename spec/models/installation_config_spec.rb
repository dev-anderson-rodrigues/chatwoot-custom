# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstallationConfig do
  subject(:installation_config) { described_class.new(name: 'INSTALLATION_NAME') }

  it { is_expected.to validate_presence_of(:name) }

  describe 'new record defaults' do
    it 'initializes serialized_value with indifferent access' do
      expect(installation_config.serialized_value).to eq({}.with_indifferent_access)
    end

    it 'returns nil for value before assignment' do
      expect(installation_config.value).to be_nil
    end
  end

  # [Onda 6a / fatia 2]
  describe 'BRAND_ACCENT_COLOR format' do
    subject(:config) { described_class.new(name: 'BRAND_ACCENT_COLOR') }

    it 'aceita cor hex de 6 digitos' do
      config.value = '#2781F6'
      expect(config).to be_valid
    end

    it 'aceita cor hex de 3 digitos' do
      config.value = '#FFF'
      expect(config).to be_valid
    end

    it 'aceita em branco -- e o super admin voltando ao padrao, nao um valor invalido' do
      config.value = ''
      expect(config).to be_valid
    end

    it 'rejeita valor que nao e cor hex' do
      config.value = 'blue'
      expect(config).not_to be_valid
      expect(config.errors[:base]).to include(/hex color/)
    end

    it 'rejeita hex sem o #' do
      config.value = '2781F6'
      expect(config).not_to be_valid
    end

    it 'nao valida o formato de outras chaves' do
      other = described_class.new(name: 'BRAND_NAME', value: 'nao e uma cor e tudo bem')
      expect(other).to be_valid
    end
  end
end
