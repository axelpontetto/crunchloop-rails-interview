module ExternalTodoApi
  # Raised for any non-successful interaction with the external API. Carries the
  # HTTP status and body, and knows whether the failure is worth retrying.
  #
  # A nil status means a transport-level failure (timeout / connection reset),
  # which is always retryable.
  class ResourceError < StandardError
    RETRYABLE_STATUSES = [429, 500, 502, 503, 504].freeze

    attr_reader :status, :body

    def initialize(message = nil, status: nil, body: nil)
      @status = status
      @body   = body
      super(message || "External Todo API error (status=#{status || 'transport'})")
    end

    def retryable?
      status.nil? || RETRYABLE_STATUSES.include?(status)
    end
  end
end
