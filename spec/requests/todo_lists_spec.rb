require 'rails_helper'

RSpec.describe "/todolists", type: :request do
  let(:valid_attributes) { { name: "Groceries" } }
  let(:invalid_attributes) { { name: "" } }
  let(:turbo_headers) { { "Accept" => "text/vnd.turbo-stream.html" } }

  describe "GET /index" do
    it "renders a successful response" do
      TodoList.create!(valid_attributes)
      get todo_lists_url
      expect(response).to be_successful
    end
  end

  describe "GET /edit" do
    it "renders a successful response" do
      todo_list = TodoList.create!(valid_attributes)
      get edit_todo_list_url(todo_list)
      expect(response).to be_successful
    end
  end

  describe "POST /create" do
    context "with valid parameters" do
      it "creates a new TodoList" do
        expect {
          post todo_lists_url, params: { todo_list: valid_attributes }
        }.to change(TodoList, :count).by(1)
      end

      it "responds with a turbo stream" do
        post todo_lists_url, params: { todo_list: valid_attributes }, headers: turbo_headers
        expect(response.media_type).to eq Mime[:turbo_stream]
      end
    end

    context "with invalid parameters" do
      it "does not create a new TodoList" do
        expect {
          post todo_lists_url, params: { todo_list: invalid_attributes }
        }.to change(TodoList, :count).by(0)
      end

      it "responds with 422" do
        post todo_lists_url, params: { todo_list: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PATCH /update" do
    it "updates the requested todo_list" do
      todo_list = TodoList.create!(valid_attributes)
      patch todo_list_url(todo_list), params: { todo_list: { name: "Work" } }, headers: turbo_headers
      expect(todo_list.reload.name).to eq "Work"
      expect(response.media_type).to eq Mime[:turbo_stream]
    end
  end

  describe "DELETE /destroy" do
    it "destroys the requested todo_list and its items" do
      todo_list = TodoList.create!(valid_attributes)
      todo_list.todo_items.create!(title: "x")
      expect {
        delete todo_list_url(todo_list), headers: turbo_headers
      }.to change(TodoList, :count).by(-1).and change(TodoItem, :count).by(-1)
    end
  end
end
