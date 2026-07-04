require "webmock/rspec"

# No spec is allowed to hit the network; the external Todo API is always stubbed.
WebMock.disable_net_connect!(allow_localhost: false)
