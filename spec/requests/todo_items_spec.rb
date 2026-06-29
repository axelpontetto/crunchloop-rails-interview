require 'rails_helper'

RSpec.describe "/todolists/:todo_list_id/todoitems", type: :request do
  let(:todo_list) { TodoList.create!(name: "Groceries") }

  let(:valid_attributes) { { title: "Buy milk" } }
  let(:invalid_attributes) { { title: "" } }

  let(:turbo_headers) { { "Accept" => "text/vnd.turbo-stream.html" } }

  describe "GET /index" do
    it "renders a successful response" do
      todo_list.todo_items.create!(valid_attributes)
      get todo_list_todo_items_url(todo_list)
      expect(response).to be_successful
    end
  end

  describe "GET /edit" do
    it "renders a successful response" do
      todo_item = todo_list.todo_items.create!(valid_attributes)
      get edit_todo_list_todo_item_url(todo_list, todo_item)
      expect(response).to be_successful
    end
  end

  describe "POST /create" do
    context "with valid parameters" do
      it "creates a new TodoItem scoped to the list" do
        expect {
          post todo_list_todo_items_url(todo_list), params: { todo_item: valid_attributes }
        }.to change(todo_list.todo_items, :count).by(1)
      end

      it "responds with a turbo stream" do
        post todo_list_todo_items_url(todo_list),
             params: { todo_item: valid_attributes }, headers: turbo_headers
        expect(response.media_type).to eq Mime[:turbo_stream]
        expect(response.body).to include("turbo-stream")
      end
    end

    context "with invalid parameters" do
      it "does not create a new TodoItem" do
        expect {
          post todo_list_todo_items_url(todo_list), params: { todo_item: invalid_attributes }
        }.to change(TodoItem, :count).by(0)
      end

      it "responds with 422" do
        post todo_list_todo_items_url(todo_list), params: { todo_item: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PATCH /update" do
    it "updates the requested todo_item" do
      todo_item = todo_list.todo_items.create!(valid_attributes)
      patch todo_list_todo_item_url(todo_list, todo_item),
            params: { todo_item: { complete: true } }, headers: turbo_headers
      expect(todo_item.reload.complete).to be true
      expect(response.media_type).to eq Mime[:turbo_stream]
    end

    it "responds with 422 for invalid params" do
      todo_item = todo_list.todo_items.create!(valid_attributes)
      patch todo_list_todo_item_url(todo_list, todo_item), params: { todo_item: invalid_attributes }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /destroy" do
    it "destroys the requested todo_item" do
      todo_item = todo_list.todo_items.create!(valid_attributes)
      expect {
        delete todo_list_todo_item_url(todo_list, todo_item), headers: turbo_headers
      }.to change(TodoItem, :count).by(-1)
    end
  end

  describe "PATCH /check_all" do
    it "marks every item in the list complete" do
      todo_list.todo_items.create!(title: "a", complete: false)
      todo_list.todo_items.create!(title: "b", complete: false)
      patch check_all_todo_list_todo_items_url(todo_list), headers: turbo_headers
      expect(todo_list.todo_items.pluck(:complete)).to all(be true)
      expect(response.media_type).to eq Mime[:turbo_stream]
    end
  end
end
