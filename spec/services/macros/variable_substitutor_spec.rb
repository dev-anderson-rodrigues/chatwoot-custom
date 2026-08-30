require 'rails_helper'

RSpec.describe Macros::VariableSubstitutor do
  subject(:substitutor) { described_class.new(inputs) }

  let(:inputs) { { 'nome' => 'Ana', 'protocolo' => 12_345, 'tags' => %w[urgente vip] } }

  describe '#substitute_params' do
    it 'replaces tokens by the value the agent filled in' do
      expect(substitutor.substitute_params(['Ola {{nome}}, protocolo {{protocolo}}']))
        .to eq(['Ola Ana, protocolo 12345'])
    end

    it 'accepts spaces inside the token' do
      expect(substitutor.substitute_params(['Ola {{ nome }}'])).to eq(['Ola Ana'])
    end

    it 'joins array values with a comma' do
      expect(substitutor.substitute_params(['Tags: {{tags}}'])).to eq(['Tags: urgente, vip'])
    end

    it 'replaces the same token more than once' do
      expect(substitutor.substitute_params(['{{nome}} e {{nome}}'])).to eq(['Ana e Ana'])
    end

    it 'substitutes every element of the params array' do
      expect(substitutor.substitute_params(['{{nome}}', 'fixo', '{{protocolo}}']))
        .to eq(%w[Ana fixo 12345])
    end

    # Deixar o literal "{{cpf}}" passar significaria mandar isso para o cliente.
    it 'blanks out an unknown token instead of leaving it literal' do
      expect(substitutor.substitute_params(['Ola {{desconhecido}}!'])).to eq(['Ola !'])
    end

    it 'blanks out a token whose value is nil' do
      expect(described_class.new('x' => nil).substitute_params(['[{{x}}]'])).to eq(['[]'])
    end

    it 'accepts symbol keys' do
      expect(described_class.new(nome: 'Ana').substitute_params(['{{nome}}'])).to eq(['Ana'])
    end

    it 'ignores malformed or uppercase tokens' do
      expect(substitutor.substitute_params(['{{ NOME }} {{1x}} {single}']))
        .to eq(['{{ NOME }} {{1x}} {single}'])
    end

    it 'leaves non-string params untouched' do
      expect(substitutor.substitute_params([1, nil, true])).to eq([1, nil, true])
    end

    it 'returns non-array params unchanged' do
      expect(substitutor.substitute_params('{{nome}}')).to eq('{{nome}}')
      expect(substitutor.substitute_params(nil)).to be_nil
    end

    it 'handles a nil inputs hash' do
      expect(described_class.new(nil).substitute_params(['[{{nome}}]'])).to eq(['[]'])
    end
  end
end
