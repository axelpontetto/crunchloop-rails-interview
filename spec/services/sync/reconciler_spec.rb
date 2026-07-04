require "rails_helper"

RSpec.describe Sync::Reconciler do
  # Pure engine: build local records + a normalized external snapshot and assert
  # the decisions. No HTTP, no external stubs needed.

  def reconcile(externals, tombstones: [])
    locals = TodoList.includes(:todo_items).to_a
    described_class.new(local_lists: locals, external_lists: externals, tombstones: tombstones).call
  end

  def kinds(actions) = actions.map(&:kind)

  def ext_list(external_id:, name:, source_id: nil, updated_at: Time.current, items: [])
    Sync::ExternalList.new(external_id: external_id, source_id: source_id, name: name,
                           updated_at: updated_at, items: items)
  end

  def ext_item(external_id:, description:, completed: false, source_id: nil, updated_at: Time.current)
    Sync::ExternalItem.new(external_id: external_id, source_id: source_id, description: description,
                           completed: completed, updated_at: updated_at)
  end

  describe "lists" do
    it "push-creates a local list that was never synced" do
      TodoList.create!(name: "Groceries")
      actions = reconcile([])
      expect(kinds(actions)).to eq([:push_create_list])
    end

    it "pull-creates an external list born on the external side (no source_id)" do
      actions = reconcile([ext_list(external_id: "E1", name: "Remote", source_id: nil)])
      expect(kinds(actions)).to eq([:pull_create_list])
    end

    it "push-updates when both exist, values differ and local is newer" do
      list = TodoList.create!(name: "New name", external_id: "E1")
      list.update_column(:updated_at, Time.current)
      ext = ext_list(external_id: "E1", name: "Old name", updated_at: 1.hour.ago)
      expect(kinds(reconcile([ext]))).to eq([:push_update_list])
    end

    it "pull-updates when both exist, values differ and external is newer" do
      list = TodoList.create!(name: "Stale", external_id: "E1")
      list.update_column(:updated_at, 1.hour.ago)
      ext = ext_list(external_id: "E1", name: "Fresh", updated_at: Time.current)
      expect(kinds(reconcile([ext]))).to eq([:pull_update_list])
    end

    it "is a no-op when values match (dirty-check), regardless of timestamps" do
      list = TodoList.create!(name: "Same", external_id: "E1")
      list.update_column(:updated_at, 1.hour.ago)
      ext = ext_list(external_id: "E1", name: "Same", updated_at: Time.current)
      expect(reconcile([ext])).to be_empty
    end

    it "pull-deletes a previously-synced local list absent from the snapshot" do
      TodoList.create!(name: "Gone", external_id: "E1")
      expect(kinds(reconcile([]))).to eq([:pull_delete_list])
    end

    it "push-deletes from a pending tombstone" do
      tomb = SyncTombstone.create!(record_type: "TodoList", record_id: 1, external_id: "E1", deleted_at: Time.current)
      actions = reconcile([], tombstones: [tomb])
      expect(kinds(actions)).to eq([:push_delete])
    end

    it "flags an inconsistency: external claims to be ours but has no local record or tombstone" do
      ext = ext_list(external_id: "E1", name: "Orphan", source_id: "rails-999")
      expect(kinds(reconcile([ext]))).to eq([:inconsistency])
    end

    it "repairs a lost link via source_id fallback instead of duplicating" do
      list = TodoList.create!(name: "Same") # external_id lost after a crash
      ext = ext_list(external_id: "E1", name: "Same", source_id: "rails-#{list.id}")
      actions = reconcile([ext])
      expect(kinds(actions)).to eq([:link_repair])
      expect(actions.first.external.external_id).to eq("E1")
    end
  end

  describe "items" do
    it "pull-creates an external item under a matched list" do
      TodoList.create!(name: "L", external_id: "E1")
      ext = ext_list(external_id: "E1", name: "L",
                     items: [ext_item(external_id: "I1", description: "milk", source_id: nil)])
      expect(kinds(reconcile([ext]))).to eq([:pull_create_item])
    end

    it "push-updates an item when local is newer and fields differ (title<->description)" do
      list = TodoList.create!(name: "L", external_id: "E1")
      item = list.todo_items.create!(title: "buy milk", complete: false, external_id: "I1")
      item.update_column(:updated_at, Time.current)
      ext = ext_list(external_id: "E1", name: "L",
                     items: [ext_item(external_id: "I1", description: "buy bread", updated_at: 1.hour.ago)])
      expect(kinds(reconcile([ext]))).to eq([:push_update_item])
    end

    it "pull-updates an item when external is newer (complete<->completed)" do
      list = TodoList.create!(name: "L", external_id: "E1")
      item = list.todo_items.create!(title: "task", complete: false, external_id: "I1")
      item.update_column(:updated_at, 1.hour.ago)
      ext = ext_list(external_id: "E1", name: "L",
                     items: [ext_item(external_id: "I1", description: "task", completed: true, updated_at: Time.current)])
      expect(kinds(reconcile([ext]))).to eq([:pull_update_item])
    end

    it "pull-deletes a previously-synced item absent from the snapshot" do
      list = TodoList.create!(name: "L", external_id: "E1")
      list.todo_items.create!(title: "old", complete: false, external_id: "I1")
      ext = ext_list(external_id: "E1", name: "L", items: [])
      expect(kinds(reconcile([ext]))).to eq([:pull_delete_item])
    end

    it "flags the API gap: a new local item on a list that already exists externally" do
      list = TodoList.create!(name: "L", external_id: "E1")
      list.todo_items.create!(title: "new item", complete: false) # no external_id
      ext = ext_list(external_id: "E1", name: "L", items: [])
      expect(kinds(reconcile([ext]))).to eq([:item_gap])
    end
  end
end
