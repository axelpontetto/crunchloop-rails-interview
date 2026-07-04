require "rails_helper"

RSpec.describe ExternalTodoApi::Client do
  let(:client) { described_class.new }
  let(:base) { ExternalTodoApi.configuration.base_url }

  describe "#list_todolists" do
    it "GETs /todolists and returns the parsed lists with nested items" do
      body = [{ id: "E1", source_id: nil, name: "Remote", items: [{ id: "I1", description: "milk", completed: false }] }]
      stub = stub_request(:get, "#{base}/todolists")
             .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

      result = client.list_todolists

      expect(stub).to have_been_requested
      expect(result.first["id"]).to eq("E1")
      expect(result.first["items"].first["description"]).to eq("milk")
    end
  end

  describe "#create_todolist" do
    it "POSTs source_id, name and nested items, returning the created record" do
      stub = stub_request(:post, "#{base}/todolists")
             .with(body: { source_id: "rails-1", name: "L", items: [{ source_id: "rails-2", description: "milk", completed: false }] })
             .to_return(status: 201, body: { id: "E1", items: [{ id: "I1", source_id: "rails-2" }] }.to_json,
                        headers: { "Content-Type" => "application/json" })

      result = client.create_todolist(source_id: "rails-1", name: "L",
                                      items: [{ source_id: "rails-2", description: "milk", completed: false }])

      expect(stub).to have_been_requested
      expect(result["id"]).to eq("E1")
    end
  end

  describe "#update_todolist" do
    it "PATCHes the list name" do
      stub = stub_request(:patch, "#{base}/todolists/E1").with(body: { name: "New" })
             .to_return(status: 200, body: {}.to_json, headers: { "Content-Type" => "application/json" })
      client.update_todolist(id: "E1", name: "New")
      expect(stub).to have_been_requested
    end
  end

  describe "#update_todoitem" do
    it "PATCHes description and completed on the nested path" do
      stub = stub_request(:patch, "#{base}/todolists/E1/todoitems/I1")
             .with(body: { description: "d", completed: true })
             .to_return(status: 200, body: {}.to_json, headers: { "Content-Type" => "application/json" })
      client.update_todoitem(list_id: "E1", id: "I1", description: "d", completed: true)
      expect(stub).to have_been_requested
    end
  end

  describe "deletes" do
    it "DELETEs a list" do
      stub = stub_request(:delete, "#{base}/todolists/E1").to_return(status: 204)
      client.delete_todolist(id: "E1")
      expect(stub).to have_been_requested
    end

    it "treats a 404 on delete as already-deleted (no error)" do
      stub_request(:delete, "#{base}/todolists/E1").to_return(status: 404)
      expect(client.delete_todolist(id: "E1")).to be_nil
    end
  end

  describe "error handling" do
    it "raises a retryable ResourceError on 500" do
      stub_request(:get, "#{base}/todolists").to_return(status: 500)
      expect { client.list_todolists }.to raise_error(ExternalTodoApi::ResourceError) { |e| expect(e).to be_retryable }
    end

    it "raises a non-retryable ResourceError on 422" do
      stub_request(:post, "#{base}/todolists").to_return(status: 422)
      expect do
        client.create_todolist(source_id: "rails-1", name: "L")
      end.to raise_error(ExternalTodoApi::ResourceError) { |e| expect(e).not_to be_retryable }
    end

    it "raises a retryable ResourceError on a transport timeout" do
      stub_request(:get, "#{base}/todolists").to_timeout
      expect { client.list_todolists }.to raise_error(ExternalTodoApi::ResourceError) { |e| expect(e).to be_retryable }
    end
  end
end
