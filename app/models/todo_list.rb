class TodoList < ApplicationRecord
  include Syncable

  has_many :todo_items, dependent: :destroy

  validates :name, presence: true
end
