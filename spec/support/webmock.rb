require 'webmock/rspec'

WebMock.disable_net_connect!(
  allow_localhost: true,
  allow: [
    /unix/, # Docker API via Unix socket
  ],
)
