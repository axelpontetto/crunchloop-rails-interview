namespace :sync do
  desc "Run a full reconciliation with the external Todo API now (inline) and print the result"
  task run: :environment do
    result = Sync::TodoSyncService.new.call
    puts result
    exit(result.failed? ? 2 : 0)
  rescue Sync::Aborted, ExternalTodoApi::ResourceError => e
    warn "Sync aborted: #{e.class} #{e.message}"
    exit 1
  end

  desc "Enqueue a reconciliation job (requires a running Solid Queue worker: bin/rails solid_queue:start)"
  task enqueue: :environment do
    TodoSyncJob.perform_later
    puts "Enqueued TodoSyncJob on the :sync queue."
  end
end
