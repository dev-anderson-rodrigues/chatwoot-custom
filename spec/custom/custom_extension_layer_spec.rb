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
RSpec.describe 'custom extension layer' do
  it 'lista custom entre as extensoes ativas' do
    expect(ChatwootApp).to be_custom
    expect(ChatwootApp.extensions).to include('custom')
  end

  it 'autocarrega constantes sob o namespace Custom::' do
    expect { Custom::Internal::CheckNewVersionsJob }.not_to raise_error
  end

  it 'coloca o modulo Custom:: na frente do Enterprise:: na cadeia de ancestrais' do
    ancestors = Internal::CheckNewVersionsJob.ancestors

    expect(ancestors).to include(Custom::Internal::CheckNewVersionsJob)
    expect(ancestors).to include(Enterprise::Internal::CheckNewVersionsJob)
    expect(ancestors.index(Custom::Internal::CheckNewVersionsJob))
      .to be < ancestors.index(Enterprise::Internal::CheckNewVersionsJob)
  end
end
