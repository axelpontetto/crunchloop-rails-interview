module Sync
  # Executes the Actions produced by the Reconciler. This is where the external
  # HTTP calls and local DB writes happen. Each action is isolated: a failure is
  # recorded in the Result and the run continues (partial-failure isolation).
  # Transient external failures are retried per-record with backoff so we never
  # redo already-synced records.
  class Applier
    DEFAULT_RETRIES = 3

    def initialize(client:, logger: Rails.logger, retries: DEFAULT_RETRIES, backoff: method(:default_backoff))
      @client = client
      @logger = logger
      @retries = retries
      @backoff = backoff
    end

    def apply(actions)
      result = Result.new
      actions.each { |action| apply_one(action, result) }
      result
    end

    private

    def apply_one(action, result)
      case action.kind
      when :push_create_list then push_create_list(action, result)
      when :push_update_list then push_update_list(action, result)
      when :push_update_item then push_update_item(action, result)
      when :push_delete      then push_delete(action, result)
      when :pull_create_list then pull_create_list(action, result)
      when :pull_update_list then pull_update_list(action, result)
      when :pull_delete_list then pull_delete_list(action, result)
      when :pull_create_item then pull_create_item(action, result)
      when :pull_update_item then pull_update_item(action, result)
      when :pull_delete_item then pull_delete_item(action, result)
      when :link_repair      then link_repair(action, result)
      when :item_gap         then item_gap(action, result)
      when :inconsistency    then inconsistency(action, result)
      end
    rescue StandardError => e
      @logger.error("[Sync] FAIL #{action.kind} #{action.label}: #{e.class} #{e.message}")
      result.record(:failed, action, error: e)
    end

    # --- Push -------------------------------------------------------------

    def push_create_list(action, result)
      list = action.local
      items = list.todo_items.to_a
      body = with_retry do
        @client.create_todolist(
          source_id: Mapper.source_id_for(list),
          name: list.name,
          items: items.map { |i| Mapper.item_create_payload(i) }
        )
      end

      ActiveRecord::Base.transaction do
        list.update_columns(external_id: body["id"].to_s, last_synced_at: now)
        returned = Array(body["items"]).index_by { |ri| ri["source_id"] }
        items.each do |item|
          ri = returned[Mapper.source_id_for(item)]
          item.update_columns(external_id: ri["id"].to_s, last_synced_at: now) if ri
        end
      end
      log("PUSH_CREATE", action)
      result.record(:created, action)
    end

    def push_update_list(action, result)
      list = action.local
      with_retry { @client.update_todolist(id: list.external_id, name: list.name) }
      list.update_columns(last_synced_at: now)
      log("PUSH_UPDATE", action)
      result.record(:updated, action)
    end

    def push_update_item(action, result)
      item = action.local
      with_retry do
        @client.update_todoitem(list_id: item.todo_list.external_id, id: item.external_id,
                                description: item.title, completed: item.complete)
      end
      item.update_columns(last_synced_at: now)
      log("PUSH_UPDATE", action)
      result.record(:updated, action)
    end

    def push_delete(action, result)
      t = action.tombstone
      with_retry do
        if t.record_type == "TodoList"
          @client.delete_todolist(id: t.external_id)
        else
          @client.delete_todoitem(list_id: t.parent_external_id, id: t.external_id)
        end
      end
      t.mark_propagated!
      log("PUSH_DELETE", action)
      result.record(:deleted, action)
    end

    # --- Pull (local writes only) -----------------------------------------

    def pull_create_list(action, result)
      ext = action.external
      ActiveRecord::Base.transaction do
        list = TodoList.create!(name: ext.name, external_id: ext.external_id, last_synced_at: now)
        touch_synced(list, ext.updated_at)
        ext.items.each do |ei|
          item = list.todo_items.create!(title: ei.description, complete: ei.completed,
                                         external_id: ei.external_id, last_synced_at: now)
          touch_synced(item, ei.updated_at)
        end
      end
      log("PULL_CREATE", action)
      result.record(:pulled_create, action)
    end

    def pull_update_list(action, result)
      list = action.local
      list.update!(name: action.external.name)
      touch_synced(list, action.external.updated_at)
      log("PULL_UPDATE", action)
      result.record(:pulled_update, action)
    end

    def pull_delete_list(action, result)
      destroy_without_tombstone(action.local)
      log("PULL_DELETE", action)
      result.record(:deleted_local, action)
    end

    def pull_create_item(action, result)
      ext = action.external
      item = action.parent_local.todo_items.create!(
        title: ext.description, complete: ext.completed,
        external_id: ext.external_id, last_synced_at: now
      )
      touch_synced(item, ext.updated_at)
      log("PULL_CREATE", action)
      result.record(:pulled_create, action)
    end

    def pull_update_item(action, result)
      item = action.local
      ext = action.external
      item.update!(title: ext.description, complete: ext.completed)
      touch_synced(item, ext.updated_at)
      log("PULL_UPDATE", action)
      result.record(:pulled_update, action)
    end

    def pull_delete_item(action, result)
      destroy_without_tombstone(action.local)
      log("PULL_DELETE", action)
      result.record(:deleted_local, action)
    end

    # --- Bookkeeping / edge cases -----------------------------------------

    def link_repair(action, result)
      action.local.update_columns(external_id: action.external.external_id, last_synced_at: now)
      log("LINK_REPAIR", action)
      result.record(:linked, action)
    end

    def item_gap(action, result)
      @logger.warn("[Sync] ITEM_GAP #{action.label}: cannot create a standalone item on an existing external list")
      result.record(:skipped_gap, action)
    end

    def inconsistency(action, result)
      @logger.warn("[Sync] INCONSISTENCY #{action.label}")
      result.record(:inconsistency, action)
    end

    # --- Utilities --------------------------------------------------------

    def destroy_without_tombstone(record)
      record.skip_sync_tombstone = true
      record.destroy!
    end

    # Persist last_synced_at and align updated_at to the external value so the
    # next run doesn't mistake this record for "locally newer" (anti ping-pong).
    def touch_synced(record, external_updated_at)
      attrs = { last_synced_at: now }
      attrs[:updated_at] = external_updated_at if external_updated_at
      record.update_columns(attrs)
    end

    def with_retry
      attempt = 0
      begin
        attempt += 1
        yield
      rescue ExternalTodoApi::ResourceError => e
        raise unless e.retryable? && attempt < @retries

        @backoff.call(attempt)
        retry
      end
    end

    def default_backoff(attempt)
      sleep(0.5 * (2**(attempt - 1)))
    end

    def log(event, action)
      @logger.info("[Sync] #{event} #{action.label}")
    end

    def now = Time.current
  end
end
