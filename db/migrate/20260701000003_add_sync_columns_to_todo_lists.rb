# Sync bookkeeping for TodoLists.
#   external_id     - id of the matching record on the external API (string).
#   last_synced_at  - timestamp of the last successful reconciliation.
class AddSyncColumnsToTodoLists < ActiveRecord::Migration[7.1]
  def change
    add_column :todo_lists, :external_id, :string
    add_column :todo_lists, :last_synced_at, :datetime
    add_index :todo_lists, :external_id, unique: true, where: "external_id IS NOT NULL"
  end
end
