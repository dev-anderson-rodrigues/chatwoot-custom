require 'rails_helper'

# [FORK] Guarda da camada custom/.
#
# A camada so funciona se tres coisas estiverem de pe ao mesmo tempo: a pasta
# custom/ existir, o application.rb ter colocado custom/app/* nos autoload paths,
# e o prepend_mod_with ter encontrado o modulo Custom:: e o colocado NA FRENTE do
# Enterprise:: na cadeia de ancestrais.
#
# Nenhuma das tres da erro visivel quando quebra -- o override simplesmente para
# de valer em silencio, e o job volta a deixar o hub ditar o plano. Por isso a
# checagem e explicita aqui.
RSpec.describe Custom::Internal::CheckNewVersionsJob do
  it 'lista custom entre as extensoes ativas' do
    expect(ChatwootApp).to be_custom
    expect(ChatwootApp.extensions).to include('custom')
  end

  it 'autocarrega constantes sob o namespace Custom::' do
    expect(described_class).to be_a(Module)
    expect(described_class.name).to eq('Custom::Internal::CheckNewVersionsJob')
  end

  it 'coloca o modulo Custom:: na frente do Enterprise:: na cadeia de ancestrais' do
    ancestors = Internal::CheckNewVersionsJob.ancestors

    expect(ancestors).to include(described_class)
    expect(ancestors).to include(Enterprise::Internal::CheckNewVersionsJob)
    expect(ancestors.index(described_class))
      .to be < ancestors.index(Enterprise::Internal::CheckNewVersionsJob)
  end
end
