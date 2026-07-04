require "rails_helper"

RSpec.describe Sync::TodoSyncService do
  let(:base) { ExternalTodoApi.configuration.base_url }
  let(:client) { ExternalTodoApi::Client.new }
  # No-op backoff so retry paths don't sleep during specs.
  let(:service) do
    described_class.new(client: client,
                        applier: Sync::Applier.new(client: client, backoff: ->(_) {}),
                        snapshot_retries: 1)
  end

  def stub_list(body)
    stub_request(:get, "#{base}/todolists")
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  it "push-creates a new local list with its items nested in a single POST" do
    list = TodoList.create!(name: "Groceries")
    item = list.todo_items.create!(title: "milk", complete: false)
    stub_list([])
    post = stub_request(:post, "#{base}/todolists")
           .to_return(status: 201,
                      body: { id: "E1", items: [{ id: "I1", source_id: "rails-#{item.id}" }] }.to_json,
                      headers: { "Content-Type" => "application/json" })

    result = service.call

    expect(post).to have_been_requested
    expect(result.counts[:created]).to eq(1)
    expect(list.reload.external_id).to eq("E1")
    expect(item.reload.external_id).to eq("I1")
  end

  it "pull-creates a list (and items) born on the external side" do
    stub_list([{ id: "E1", source_id: nil, name: "Remote", updated_at: Time.current.iso8601,
                 items: [{ id: "I1", source_id: nil, description: "milk", completed: true,
                           updated_at: Time.current.iso8601 }] }])

    result = service.call

    expect(result.counts[:pulled_create]).to eq(1)
    list = TodoList.find_by(external_id: "E1")
    expect(list.name).to eq("Remote")
    expect(list.todo_items.first).to have_attributes(title: "milk", complete: true, external_id: "I1")
  end

  it "propagates a local delete via a tombstone" do
    tomb = SyncTombstone.create!(record_type: "TodoList", record_id: 42, external_id: "E1", deleted_at: Time.current)
    stub_list([{ id: "E1", source_id: "rails-42", name: "x", items: [] }])
    del = stub_request(:delete, "#{base}/todolists/E1").to_return(status: 204)

    result = service.call

    expect(del).to have_been_requested
    expect(result.counts[:deleted]).to eq(1)
    expect(tomb.reload.propagated_at).to be_present
  end

  it "is idempotent: a converged state performs zero mutations (only the GET)" do
    list = TodoList.create!(name: "L", external_id: "E1")
    list.todo_items.create!(title: "t", complete: false, external_id: "I1")
    stub_list([{ id: "E1", source_id: "rails-#{list.id}", name: "L", updated_at: 1.hour.ago.iso8601,
                 items: [{ id: "I1", source_id: nil, description: "t", completed: false,
                           updated_at: 1.hour.ago.iso8601 }] }])

    result = service.call

    expect(result.counts.slice(:created, :updated, :deleted, :pulled_create, :pulled_update, :deleted_local)).to be_empty
    # No mutation stubs were registered, so any external write would have raised.
  end

  it "isolates partial failures: one bad record fails, the rest still sync" do
    ok = TodoList.create!(name: "Good")
    bad = TodoList.create!(name: "Bad")
    stub_list([])
    stub_request(:post, "#{base}/todolists").with(body: hash_including("name" => "Good"))
      .to_return(status: 201, body: { id: "E1", items: [] }.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:post, "#{base}/todolists").with(body: hash_including("name" => "Bad"))
      .to_return(status: 500)

    result = service.call

    expect(result.counts[:created]).to eq(1)
    expect(result.counts[:failed]).to eq(1)
    expect(ok.reload.external_id).to eq("E1")
    expect(bad.reload.external_id).to be_nil
  end

  it "aborts without mutating when the snapshot GET fails" do
    TodoList.create!(name: "L")
    stub_request(:get, "#{base}/todolists").to_return(status: 500)

    expect { service.call }.to raise_error(ExternalTodoApi::ResourceError)
  end
end
