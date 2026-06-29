require 'rails_helper'

RSpec.describe TodoItem, type: :model do
  let(:todo_list) { TodoList.create!(name: "Groceries") }

  it "is valid with a title and a list" do
    expect(todo_list.todo_items.build(title: "Milk")).to be_valid
  end

  it "requires a title" do
    item = todo_list.todo_items.build(title: "")
    expect(item).not_to be_valid
    expect(item.errors[:title]).to be_present
  end

  it "requires a todo_list" do
    expect(TodoItem.new(title: "Milk")).not_to be_valid
  end

  it "defaults complete to false" do
    expect(todo_list.todo_items.create!(title: "Milk").complete).to be false
  end
end
