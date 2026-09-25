# [FORK] Overrides do disparo em massa por qualquer caixa (Onda 7 / fatia 2) em classes que NAO tem
# gancho de extensao (`prepend_mod_with`) no upstream: o controller de analytics (enterprise), o
# SendReplyJob e o NotificationListener. `to_prepare` (e nao um prepend direto) porque essas classes sao
# recarregadas em development: cada nova classe precisa receber o modulo.
Rails.application.config.to_prepare do
  Api::V1::Accounts::Campaigns::AnalyticsController.prepend(Custom::CampaignAnalyticsAccess)
  SendReplyJob.prepend(Custom::CampaignSendReplyGuard)
  NotificationListener.prepend(Custom::CampaignNotificationFilter)
end
