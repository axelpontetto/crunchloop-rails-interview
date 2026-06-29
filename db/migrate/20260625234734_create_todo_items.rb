class CreateTodoItems < ActiveRecord::Migration[7.0]
  def change
    create_table :todo_items do |t|
      t.string :title, null: false
      t.boolean :complete, default: false, null: false
      t.references :todo_list, null: false, foreign_key: true

      t.timestamps
    end
  end
end
