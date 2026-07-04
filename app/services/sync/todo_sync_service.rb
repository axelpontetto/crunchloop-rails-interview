module Sync
  # Orchestrates one full reconciliation run:
  #   1. fetch the external snapshot (single GET, retried; a hard failure aborts
  #      the run so we never act on an incomplete snapshot)
  #   2. load local records + pending tombstones
  #   3. reconcile (pure) and apply the resulting actions
  #
  # Returns a Sync::Result. The core (Reconciler) is pure and the I/O lives in
  # the Client/Applier, so this can be driven from a rake task or an ActiveJob.
  #
  # We trust a successful snapshot as the complete external state (the API has no
  # pagination), so deletes are propagated as-is. The protection against
  # detectable failures is the fatal fetch below.
  class TodoSyncService
    def initialize(client: ExternalTodoApi::Client.new, logger: Rails.logger, applier: nil,
                   snapshot_retries: 3, snapshot_backoff: ->(attempt) { sleep(0.5 * attempt) })
      @client = client
      @logger = logger
      @applier = applier || Applier.new(client: client, logger: logger)
      @snapshot_retries = snapshot_retries
      @snapshot_backoff = snapshot_backoff
    end

    def call
      tagged do
        external_lists = Mapper.normalize_snapshot(fetch_snapshot)
        local_lists = TodoList.includes(:todo_items).to_a
        tombstones = SyncTombstone.pending.to_a

        actions = Reconciler.new(local_lists: local_lists, external_lists: external_lists,
                                 tombstones: tombstones).call
        result = @applier.apply(actions)
        @logger.info("[Sync] #{result}")
        result
      end
    end

    private

    def fetch_snapshot
      attempt = 0
      begin
        attempt += 1
        raw = @client.list_todolists
        raise Aborted, "External snapshot returned nil" if raw.nil?

        raw
      rescue ExternalTodoApi::ResourceError => e
        if e.retryable? && attempt < @snapshot_retries
          @snapshot_backoff.call(attempt)
          retry
        end
        # Propagate: nothing has been applied, so the run aborts. A queued job
        # can retry the whole run later (it is idempotent).
        raise
      end
    end

    def tagged(&block)
      if @logger.respond_to?(:tagged)
        @logger.tagged("Sync", &block)
      else
        yield
      end
    end
  end
end
