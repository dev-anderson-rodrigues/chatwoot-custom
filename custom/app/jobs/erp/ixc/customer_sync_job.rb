class Erp::Ixc::CustomerSyncJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(hook_id)
    hook = Integrations::Hook.find_by(id: hook_id, app_id: 'ixc')
    return unless hook

    Erp::Ixc::CustomerSyncService.new(hook: hook).sync_missing
  end
end
