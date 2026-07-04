require "rails_helper"

RSpec.describe TodoSyncJob do
  include ActiveJob::TestHelper

  it "enqueues on the :sync queue" do
    expect { described_class.perform_later }.to have_enqueued_job(described_class).on_queue("sync")
  end

  it "invokes the sync service when performed" do
    service = instance_double(Sync::TodoSyncService, call: Sync::Result.new)
    allow(Sync::TodoSyncService).to receive(:new).and_return(service)

    described_class.perform_now

    expect(service).to have_received(:call)
  end

  it "is configured to retry transient external errors and discard deliberate aborts" do
    expect(described_class.rescue_handlers.map(&:first)).to include(
      "ExternalTodoApi::ResourceError", "Sync::Aborted"
    )
  end
end
