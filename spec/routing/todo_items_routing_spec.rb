require "rails_helper"

RSpec.describe TodoItemsController, type: :routing do
  describe "routing" do
    it "routes to #index" do
      expect(get: "/todolists/1/todoitems").to route_to("todo_items#index", todo_list_id: "1")
    end

    it "routes to #new" do
      expect(get: "/todolists/1/todoitems/new").to route_to("todo_items#new", todo_list_id: "1")
    end

    it "routes to #show" do
      expect(get: "/todolists/1/todoitems/2").to route_to("todo_items#show", todo_list_id: "1", id: "2")
    end

    it "routes to #edit" do
      expect(get: "/todolists/1/todoitems/2/edit").to route_to("todo_items#edit", todo_list_id: "1", id: "2")
    end

    it "routes to #create" do
      expect(post: "/todolists/1/todoitems").to route_to("todo_items#create", todo_list_id: "1")
    end

    it "routes to #update via PUT" do
      expect(put: "/todolists/1/todoitems/2").to route_to("todo_items#update", todo_list_id: "1", id: "2")
    end

    it "routes to #update via PATCH" do
      expect(patch: "/todolists/1/todoitems/2").to route_to("todo_items#update", todo_list_id: "1", id: "2")
    end

    it "routes to #destroy" do
      expect(delete: "/todolists/1/todoitems/2").to route_to("todo_items#destroy", todo_list_id: "1", id: "2")
    end

    it "routes to #check_all" do
      expect(patch: "/todolists/1/todoitems/check_all").to route_to("todo_items#check_all", todo_list_id: "1")
    end
  end
end
