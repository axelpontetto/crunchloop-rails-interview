class TodoList < ApplicationRecord
  validates :name, presence: true
end