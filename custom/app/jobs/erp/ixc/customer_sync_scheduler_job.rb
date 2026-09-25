class Erp::Ixc::CustomerSyncSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Integrations::Hook.where(app_id: 'ixc').find_each do |hook|
      Erp::Ixc::CustomerSyncJob.perform_later(hook.id)
    end
  end
end
