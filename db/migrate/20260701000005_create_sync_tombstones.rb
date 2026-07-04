# Positive record of a locally-deleted, previously-synced record. This is what
# lets the reconciler propagate a delete to the external API unambiguously
# (a hard delete otherwise leaves no trace to distinguish "deleted" from
# "never existed"). Purged once propagated.
class CreateSyncTombstones < ActiveRecord::Migration[7.1]
  def change
    create_table :sync_tombstones do |t|
      t.string   :record_type, null: false        # "TodoList" | "TodoItem"
      t.bigint   :record_id,   null: false         # local id (for traceability)
      t.string   :external_id, null: false         # id on the external API to DELETE
      t.string   :parent_external_id               # for items: the parent list's external_id
      t.datetime :deleted_at,  null: false
      t.datetime :propagated_at                     # set once the external DELETE succeeds
      t.timestamps
    end

    add_index :sync_tombstones, %i[record_type external_id]
    add_index :sync_tombstones, :propagated_at
  end
end
