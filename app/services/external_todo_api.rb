# Namespace + configuration entry point for the external Todo API client.
module ExternalTodoApi
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    # Mostly for tests: drop the memoized config so ENV changes take effect.
    def reset_configuration!
      @configuration = nil
    end
  end
end
