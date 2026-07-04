# Sync bookkeeping for TodoItems (see AddSyncColumnsToTodoLists).
class AddSyncColumnsToTodoItems < ActiveRecord::Migration[7.1]
  def change
    add_column :todo_items, :external_id, :string
    add_column :todo_items, :last_synced_at, :datetime
    add_index :todo_items, :external_id, unique: true, where: "external_id IS NOT NULL"
  end
end
