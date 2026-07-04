module Sync
  # Normalized view of a TodoItem as returned by the external API.
  ExternalItem = Struct.new(:external_id, :source_id, :description, :completed, :updated_at, keyword_init: true)
end
