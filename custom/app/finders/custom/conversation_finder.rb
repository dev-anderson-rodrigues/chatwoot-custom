# [FORK] Filtro `my_teams_only`: restringe a lista de conversas aos times do
# proprio agente.
#
# Mora aqui, e nao no app/finders/conversation_finder.rb, porque o
# ConversationFinder ja chama prepend_mod_with -- entao a camada custom/ e o
# ponto de extensao previsto. Assim o arquivo do upstream fica intacto e o
# proximo merge de versao nao conflita.
module Custom::ConversationFinder
  private

  def set_up
    super
    filter_by_my_teams
  end

  # Mantem as conversas sem time nenhum: elas ainda nao foram triadas e precisam
  # continuar visiveis, senao ninguem as pega.
  #
  # Passar nil dentro do array e proposital -- o Rails gera
  # `team_id IN (...) OR team_id IS NULL` sozinho, e isso ja resolve o caso do
  # agente que nao esta em time nenhum (vira apenas `team_id IS NULL`).
  #
  # ActiveModel::Type::Boolean trata como falso so a lista conhecida
  # ('false', '0', 'f', 'off', ''); qualquer outro valor liga o filtro. Erra
  # para o lado restritivo, que e o seguro aqui.
  def filter_by_my_teams
    return unless ActiveModel::Type::Boolean.new.cast(params[:my_teams_only])

    my_team_ids = current_user.teams.where(account_id: current_account.id).pluck(:id)
    @conversations = @conversations.where(team_id: my_team_ids + [nil])
  end
end
