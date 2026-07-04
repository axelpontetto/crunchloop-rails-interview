# Records a tombstone when a previously-synced record (one with an external_id)
# is destroyed, so the next sync can propagate the DELETE to the external API.
#
# Items destroyed as part of their list's cascade (`dependent: :destroy`) are
# skipped: deleting the list on the external side already removes its items, so
# emitting per-item DELETEs would be redundant (they'd 404).
module Syncable
  extend ActiveSupport::Concern

  included do
    # Set on a record before a pull-delete so destroying it locally (because it
    # was deleted on the external side) does NOT emit a tombstone that would try
    # to re-delete it externally.
    attr_accessor :skip_sync_tombstone

    after_destroy :record_sync_tombstone
  end

  private

  def record_sync_tombstone
    return if skip_sync_tombstone
    return if external_id.blank?
    return if destroyed_by_association # parent list delete cascades on the external side

    SyncTombstone.create!(
      record_type: self.class.name,
      record_id: id,
      external_id: external_id,
      parent_external_id: sync_parent_external_id,
      deleted_at: Time.current
    )
  end

  # Overridden by records nested under a parent (e.g. TodoItem) so the tombstone
  # carries the parent's external_id needed for the nested DELETE path.
  def sync_parent_external_id
    nil
  end
end
