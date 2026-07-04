class TodoItem < ApplicationRecord
  include Syncable

  belongs_to :todo_list

  validates :title, presence: true
  validates :complete, inclusion: { in: [true, false] }

  private

  def sync_parent_external_id
    todo_list&.external_id
  end
end
