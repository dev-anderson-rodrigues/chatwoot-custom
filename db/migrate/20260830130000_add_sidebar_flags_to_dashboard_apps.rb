class AddSidebarFlagsToDashboardApps < ActiveRecord::Migration[7.1]
  def change
    # Duas coisas diferentes, de proposito:
    #   show_in_sidebar -- o app aparece na sidebar, agrupado sob "Aplicativos"
    #   pin_to_sidebar  -- o app sobe para item de primeiro nivel, fora do grupo
    add_column :dashboard_apps, :show_in_sidebar, :boolean, default: false, null: false
    add_column :dashboard_apps, :pin_to_sidebar, :boolean, default: false, null: false
  end
end
