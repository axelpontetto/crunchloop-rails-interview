# A positive record that a previously-synced local record was deleted, so the
# reconciler can propagate the DELETE to the external API. Once the external
# DELETE succeeds we set propagated_at (idempotency — never delete twice).
class SyncTombstone < ApplicationRecord
  scope :pending, -> { where(propagated_at: nil) }

  def mark_propagated!
    update!(propagated_at: Time.current)
  end
end
