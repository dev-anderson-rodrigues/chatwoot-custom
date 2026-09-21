# [FORK] Destrava campanha presa em `processing` quando o job morreu no meio.
#
# O agendador (TriggerScheduledItemsJob, a cada 5 min) so pega campanha `active`,
# e Campaign#mark_processing! faz `next if processing?`. Se o job cai depois de
# marcar `processing` -- deploy, SIGKILL, queda do worker -- a campanha fica assim
# para sempre: reexecutar nao retoma, e o resto do publico nunca recebe.
#
# "Presa" = em `processing` ha mais de STALE_AFTER E sem NENHUM destinatario
# atualizado nesse tempo. O segundo criterio e o batimento: um envio em andamento
# atualiza a linha do destinatario a cada mensagem, entao campanha grande e lenta
# mas viva nao e confundida com morta.
#
# STALE_AFTER = 10 min: o maior intervalo LEGITIMO sem atividade num job vivo e de
# ~2 min (3 tentativas de ate 30s cada, mais 20s de espera entre elas), entao 10
# min deixa folga larga e encurta a recuperacao depois de um deploy -- o SIGTERM
# interrompe o job, o Sidekiq o reenfileira, a nova execucao ve `processing` e nao
# faz nada, e a campanha fica parada ate este job agir.
#
# Ao destravar volta para `active` e reenfileira direto (o agendador ignora
# campanha com scheduled_at de mais de 3 dias). A retomada NAO reenvia: o
# Custom::Whatsapp::OneoffCampaignService so processa destinatario `queued`,
# conferido com reload a cada envio.
#
# Falso positivo (job vivo e parado ha mais de 10 min sem tocar em nenhum
# destinatario) e improvavel, mas nao impossivel. Se acontecer, dois jobs correm a
# mesma campanha; o reload por destinatario faz cada um pular quem o outro ja
# enviou, e o que sobra e a chance de UM destinatario sair duas vezes se os dois
# chegarem nele no mesmo instante -- nao a campanha inteira duplicada.
class Custom::Campaigns::ResetStaleProcessingJob < ApplicationJob
  queue_as :scheduled_jobs

  STALE_AFTER = 10.minutes

  def perform
    Campaign.processing.one_off.where(started_at: ...STALE_AFTER.ago).find_each do |campaign|
      next if recently_active?(campaign)

      reset(campaign)
    end
  end

  private

  def recently_active?(campaign)
    campaign.campaign_recipients.exists?(['updated_at > ?', STALE_AFTER.ago])
  end

  # update_columns: so o status importa, e uma validacao do model (remetente ou
  # caixa que mudou de conta, por exemplo) nao pode impedir o destravamento.
  def reset(campaign)
    Rails.logger.warn "Campaign #{campaign.id} stuck in processing since #{campaign.started_at}; resetting to active"
    # rubocop:disable Rails/SkipsModelValidations
    campaign.update_columns(campaign_status: Campaign.campaign_statuses[:active])
    # rubocop:enable Rails/SkipsModelValidations
    ::Campaigns::TriggerOneoffCampaignJob.perform_later(campaign)
  end
end
