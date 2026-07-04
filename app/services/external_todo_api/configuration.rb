module ExternalTodoApi
  # Connection settings for the external Todo API, read from the environment so
  # the same code points at a real service (POC), a stub (tests), or a dev
  # container without changes.
  class Configuration
    attr_accessor :base_url, :open_timeout, :timeout

    def initialize
      @base_url     = ENV.fetch("EXTERNAL_TODO_API_URL", "http://localhost:3001")
      @open_timeout = Integer(ENV.fetch("EXTERNAL_TODO_API_OPEN_TIMEOUT", 5))
      @timeout      = Integer(ENV.fetch("EXTERNAL_TODO_API_TIMEOUT", 10))
    end
  end
end
