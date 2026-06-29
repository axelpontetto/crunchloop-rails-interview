require 'rails_helper'

RSpec.describe TodoList, type: :model do
  it "is valid with a name" do
    expect(TodoList.new(name: "Groceries")).to be_valid
  end

  it "requires a name" do
    list = TodoList.new(name: "")
    expect(list).not_to be_valid
    expect(list.errors[:name]).to be_present
  end

  it "destroys its items when destroyed" do
    list = TodoList.create!(name: "Groceries")
    list.todo_items.create!(title: "Milk")
    expect { list.destroy }.to change(TodoItem, :count).by(-1)
  end
end
