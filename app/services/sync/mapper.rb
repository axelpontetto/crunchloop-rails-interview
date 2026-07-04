module Sync
  # Translates between local records and the external API representation:
  # field mapping, the namespaced source_id, timestamp parsing, and normalizing
  # the raw GET payload into ExternalList/ExternalItem structs.
  #
  # Field mapping: local title <-> external description; local complete <-> external completed.
  module Mapper
    SOURCE_PREFIX = "rails-".freeze

    module_function

    # The source_id we stamp on records we push, so we can correlate them later.
    def source_id_for(record)
      "#{SOURCE_PREFIX}#{record.id}"
    end

    # Extract the originating local id from a source_id we emitted, or nil if the
    # record was not created by us (born on the external side, or foreign format).
    def local_id_from_source_id(source_id)
      return nil if source_id.blank?
      return nil unless source_id.to_s.start_with?(SOURCE_PREFIX)

      rest = source_id.to_s.delete_prefix(SOURCE_PREFIX)
      rest.match?(/\A\d+\z/) ? rest.to_i : nil
    end

    def parse_time(value)
      return nil if value.blank?
      return value.utc if value.is_a?(Time)

      Time.parse(value.to_s).utc
    rescue ArgumentError
      nil
    end

    def to_bool(value)
      ActiveModel::Type::Boolean.new.cast(value) || false
    end

    def normalize_snapshot(raw)
      Array(raw).map { |list| normalize_list(list) }
    end

    def normalize_list(list)
      ExternalList.new(
        external_id: list["id"]&.to_s,
        source_id: list["source_id"],
        name: list["name"],
        updated_at: parse_time(list["updated_at"]),
        items: Array(list["items"]).map { |item| normalize_item(item) }
      )
    end

    def normalize_item(item)
      ExternalItem.new(
        external_id: item["id"]&.to_s,
        source_id: item["source_id"],
        description: item["description"],
        completed: to_bool(item["completed"]),
        updated_at: parse_time(item["updated_at"])
      )
    end

    # Payload for POST /todolists item nesting.
    def item_create_payload(item)
      { source_id: source_id_for(item), description: item.title, completed: item.complete }
    end
  end
end
