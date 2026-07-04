module Sync
  # Pure diff engine. Given the local records, the normalized external snapshot
  # and the pending tombstones, it returns the list of Actions to apply. It does
  # NO I/O (no HTTP, no DB writes) so the whole decision matrix is unit-testable.
  #
  # Matching: by external_id first, then by source_id (repairs a link lost to a
  # crash between POST and saving external_id). Updates use last-write-wins on
  # updated_at, gated by a value dirty-check (only act when values actually
  # differ, which also prevents ping-pong). Deletes: "the delete wins".
  class Reconciler
    # Local is treated as the winner unless the external record is newer by more
    # than this, to keep ties/clock-skew deterministic.
    EPSILON = 1.second

    def initialize(local_lists:, external_lists:, tombstones: [])
      @local_lists = local_lists
      @external_lists = external_lists
      @tombstones = tombstones
      @actions = []
    end

    def call
      index_externals
      index_tombstones

      @local_lists.each { |local| reconcile_list(local) }
      @external_lists.each { |ext| pull_or_flag_list(ext) unless matched?(ext) }
      @tombstones.each { |t| @actions << Action.new(kind: :push_delete, tombstone: t) }

      @actions
    end

    private

    def index_externals
      @ext_by_external_id = @external_lists.index_by(&:external_id)
      @ext_by_local_id = {}
      @external_lists.each do |ext|
        local_id = Mapper.local_id_from_source_id(ext.source_id)
        @ext_by_local_id[local_id] = ext if local_id
      end
      @matched_ext_ids = Set.new
    end

    def index_tombstones
      @list_tombstone_ids = @tombstones.select { |t| t.record_type == "TodoList" }.map(&:external_id).to_set
      @item_tombstone_ids = @tombstones.select { |t| t.record_type == "TodoItem" }.map(&:external_id).to_set
    end

    def matched?(ext) = @matched_ext_ids.include?(ext.external_id)

    # --- Lists -------------------------------------------------------------

    def reconcile_list(local)
      ext = match_external_for(local, @ext_by_external_id, @ext_by_local_id)

      if ext
        @matched_ext_ids << ext.external_id
        @actions << Action.new(kind: :link_repair, local: local, external: ext) if local.external_id.blank?
        reconcile_list_fields(local, ext)
        reconcile_items(local, ext)
      elsif local.external_id.present?
        # Was synced before, absent from a complete snapshot -> deleted externally.
        @actions << Action.new(kind: :pull_delete_list, local: local)
      else
        # Never pushed -> create it (with its items nested).
        @actions << Action.new(kind: :push_create_list, local: local)
      end
    end

    def reconcile_list_fields(local, ext)
      return unless local.name != ext.name

      if local_wins?(local.updated_at, ext.updated_at)
        @actions << Action.new(kind: :push_update_list, local: local)
      else
        @actions << Action.new(kind: :pull_update_list, local: local, external: ext)
      end
    end

    def pull_or_flag_list(ext)
      if ours?(ext.source_id)
        return if @list_tombstone_ids.include?(ext.external_id) # tombstone loop will delete it

        @actions << Action.new(kind: :inconsistency,
                               note: "TodoList external_id=#{ext.external_id} source_id=#{ext.source_id} has no local record or tombstone")
      else
        @actions << Action.new(kind: :pull_create_list, external: ext)
      end
    end

    # --- Items (within a matched list) ------------------------------------

    def reconcile_items(local, ext)
      ext_by_external_id = ext.items.index_by(&:external_id)
      ext_by_local_id = {}
      ext.items.each do |ei|
        local_id = Mapper.local_id_from_source_id(ei.source_id)
        ext_by_local_id[local_id] = ei if local_id
      end
      matched_ids = Set.new

      local.todo_items.each do |item|
        match = match_external_for(item, ext_by_external_id, ext_by_local_id)

        if match
          matched_ids << match.external_id
          @actions << Action.new(kind: :link_repair, local: item, external: match) if item.external_id.blank?
          reconcile_item_fields(item, match)
        elsif item.external_id.present?
          @actions << Action.new(kind: :pull_delete_item, local: item)
        else
          # New local item on a list that already exists externally: no API
          # endpoint to create a standalone item -> flag and skip.
          @actions << Action.new(kind: :item_gap, local: item)
        end
      end

      ext.items.each do |ei|
        next if matched_ids.include?(ei.external_id)

        pull_or_flag_item(ei, local)
      end
    end

    def reconcile_item_fields(item, ext)
      return unless item.title != ext.description || item.complete != ext.completed

      if local_wins?(item.updated_at, ext.updated_at)
        @actions << Action.new(kind: :push_update_item, local: item)
      else
        @actions << Action.new(kind: :pull_update_item, local: item, external: ext)
      end
    end

    def pull_or_flag_item(ext, parent_local)
      if ours?(ext.source_id)
        return if @item_tombstone_ids.include?(ext.external_id)

        @actions << Action.new(kind: :inconsistency,
                               note: "TodoItem external_id=#{ext.external_id} source_id=#{ext.source_id} has no local record or tombstone")
      else
        @actions << Action.new(kind: :pull_create_item, external: ext, parent_local: parent_local)
      end
    end

    # --- Helpers -----------------------------------------------------------

    def match_external_for(record, by_external_id, by_local_id)
      if record.external_id.present?
        by_external_id[record.external_id]
      else
        by_local_id[record.id]
      end
    end

    def ours?(source_id) = !Mapper.local_id_from_source_id(source_id).nil?

    def local_wins?(local_time, ext_time)
      return true if ext_time.nil?
      return false if local_time.nil?

      (local_time - ext_time) >= -EPSILON
    end
  end
end
