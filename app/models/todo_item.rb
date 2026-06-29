class TodoItem < ApplicationRecord
  belongs_to :todo_list

  validates :title, presence: true
  validates :complete, inclusion: { in: [true, false] }
end
