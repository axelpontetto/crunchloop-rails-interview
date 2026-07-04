module Sync
  # Normalized view of a TodoList (with its items) as returned by the external API.
  # items is always an array (see Mapper.normalize_list).
  ExternalList = Struct.new(:external_id, :source_id, :name, :updated_at, :items, keyword_init: true)
end
