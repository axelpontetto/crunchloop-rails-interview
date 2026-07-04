module Sync
  # A single decision produced by the Reconciler and executed by the Applier.
  # Not all fields apply to every kind (see Reconciler for which are set):
  #
  #   :push_create_list  local
  #   :push_update_list  local
  #   :push_update_item  local
  #   :push_delete       tombstone
  #   :pull_create_list  external
  #   :pull_update_list  local, external
  #   :pull_delete_list  local
  #   :pull_create_item  external, parent_local
  #   :pull_update_item  local, external
  #   :pull_delete_item  local
  #   :link_repair       local, external          (adopt external_id after a lost link)
  #   :item_gap          local                    (new local item on an existing external list)
  #   :inconsistency     note                     (external claims to be ours but has no local/tombstone)
  Action = Struct.new(:kind, :local, :external, :tombstone, :parent_local, :note, keyword_init: true) do
    def label
      case kind
      when :push_delete then "#{tombstone.record_type}##{tombstone.record_id} (external_id=#{tombstone.external_id})"
      when :pull_create_list, :pull_create_item then "external_id=#{external.external_id}"
      when :inconsistency then note
      else "#{local.class.name}##{local&.id}"
      end
    end
  end
end
