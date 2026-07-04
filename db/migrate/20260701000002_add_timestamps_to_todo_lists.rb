# TodoLists had no timestamps. Last-write-wins sync needs updated_at on both
# sides, so we add them, backfill existing rows, then enforce NOT NULL.
class AddTimestampsToTodoLists < ActiveRecord::Migration[7.1]
  def up
    add_column :todo_lists, :created_at, :datetime
    add_column :todo_lists, :updated_at, :datetime

    now = Time.current
    TodoList.reset_column_information
    TodoList.update_all(created_at: now, updated_at: now)

    change_column_null :todo_lists, :created_at, false
    change_column_null :todo_lists, :updated_at, false
  end

  def down
    remove_column :todo_lists, :created_at
    remove_column :todo_lists, :updated_at
  end
end
