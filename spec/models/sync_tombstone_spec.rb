require "rails_helper"

RSpec.describe SyncTombstone do
  describe ".pending" do
    it "returns only tombstones not yet propagated" do
      pending = described_class.create!(record_type: "TodoList", record_id: 1, external_id: "E1", deleted_at: Time.current)
      described_class.create!(record_type: "TodoList", record_id: 2, external_id: "E2",
                              deleted_at: Time.current, propagated_at: Time.current)
      expect(described_class.pending).to contain_exactly(pending)
    end
  end
end

RSpec.describe Syncable do
  describe "tombstone creation on destroy" do
    it "records a tombstone when a synced record is destroyed" do
      list = TodoList.create!(name: "L", external_id: "E1")
      expect { list.destroy! }.to change { SyncTombstone.where(record_type: "TodoList", external_id: "E1").count }.by(1)
    end

    it "does not record a tombstone for a record that was never synced" do
      list = TodoList.create!(name: "L") # no external_id
      expect { list.destroy! }.not_to(change { SyncTombstone.count })
    end

    it "carries the parent list's external_id for a deleted item" do
      list = TodoList.create!(name: "L", external_id: "E1")
      item = list.todo_items.create!(title: "t", complete: false, external_id: "I1")

      item.destroy!

      tomb = SyncTombstone.find_by(record_type: "TodoItem", external_id: "I1")
      expect(tomb.parent_external_id).to eq("E1")
    end

    it "does not emit per-item tombstones when the whole list is destroyed (cascade)" do
      list = TodoList.create!(name: "L", external_id: "E1")
      list.todo_items.create!(title: "t", complete: false, external_id: "I1")

      list.destroy!

      expect(SyncTombstone.where(record_type: "TodoItem")).to be_empty
      expect(SyncTombstone.where(record_type: "TodoList", external_id: "E1")).to exist
    end
  end
end
