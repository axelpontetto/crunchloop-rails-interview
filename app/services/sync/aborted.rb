module Sync
  # Raised when a run cannot safely proceed (e.g. the snapshot could not be
  # fetched, or a mass-delete guard tripped). Nothing is applied.
  class Aborted < StandardError; end
end
