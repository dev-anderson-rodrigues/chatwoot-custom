# [FORK] Acopla o destravamento de campanha ao agendador que ja roda a cada 5 min.
#
# Pelo prepend_mod_with que o TriggerScheduledItemsJob ja tem, em vez de uma
# entrada nova no config/schedule.yml (arquivo do upstream). Ver
# Custom::Campaigns::ResetStaleProcessingJob.
module Custom::TriggerScheduledItemsJob
  def perform
    super
    Custom::Campaigns::ResetStaleProcessingJob.perform_later
  end
end
