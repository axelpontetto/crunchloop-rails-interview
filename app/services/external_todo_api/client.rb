require "faraday"

module ExternalTodoApi
  # Thin HTTP wrapper around the external Todo API. Every method maps 1:1 to an
  # endpoint; the rest of the app never touches HTTP directly. Retries are the
  # caller's responsibility (see Sync::Applier) so behaviour stays predictable
  # and easy to assert in tests.
  class Client
    def initialize(config = ExternalTodoApi.configuration)
      @config = config
    end

    # GET /todolists -> array of lists, each with nested items. The only read.
    def list_todolists
      request(:get, "/todolists")
    end

    # POST /todolists -> creates a list and all its items in a single call.
    def create_todolist(source_id:, name:, items: [])
      request(:post, "/todolists", { source_id: source_id, name: name, items: items })
    end

    def update_todolist(id:, name:)
      request(:patch, "/todolists/#{id}", { name: name })
    end

    def delete_todolist(id:)
      request(:delete, "/todolists/#{id}", nil, allow_not_found: true)
    end

    def update_todoitem(list_id:, id:, description:, completed:)
      request(:patch, "/todolists/#{list_id}/todoitems/#{id}",
              { description: description, completed: completed })
    end

    def delete_todoitem(list_id:, id:)
      request(:delete, "/todolists/#{list_id}/todoitems/#{id}", nil, allow_not_found: true)
    end

    private

    def connection
      @connection ||= Faraday.new(url: @config.base_url) do |f|
        f.request :json
        f.response :json, content_type: /\bjson$/
        f.options.open_timeout = @config.open_timeout
        f.options.timeout      = @config.timeout
      end
    end

    def request(verb, path, body = nil, allow_not_found: false)
      response = body.nil? ? connection.public_send(verb, path) : connection.public_send(verb, path, body)

      return response.body if response.success?
      return nil if allow_not_found && response.status == 404

      raise ResourceError.new(status: response.status, body: response.body)
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      raise ResourceError.new(e.message, status: nil)
    end
  end
end
