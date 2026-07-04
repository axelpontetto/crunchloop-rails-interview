# Runs one full reconciliation between the local DB and the external Todo API.
#
# One run == one job: the single GET snapshot is the unit of consistency, so
# splitting into per-record jobs would multiply reads. The service is
# idempotent, so a retried job simply re-reconciles whatever is still pending.
class TodoSyncJob < ApplicationJob
  queue_as :sync

  # Transient infrastructure failures (external API down / slow on the GET):
  # retry the whole run with growing backoff.
  retry_on ExternalTodoApi::ResourceError, wait: :polynomially_longer, attempts: 5
  retry_on Faraday::TimeoutError, wait: :polynomially_longer, attempts: 5

  # A deliberate safety stop (empty snapshot guard, nil snapshot) should not retry.
  discard_on Sync::Aborted

  # Serialize runs so two overlapping syncs never act on the same state.
  limits_concurrency key: "todo-sync", to: 1

  def perform
    result = Sync::TodoSyncService.new.call
    Rails.logger.info("[Sync] job finished: #{result}")
    result
  end
end
