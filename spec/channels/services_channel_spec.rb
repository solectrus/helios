require 'rails_helper'

RSpec.describe ServicesChannel do
  # Every service row listens on one shared stream; the broadcasts carry the
  # service name, so no per-service stream is needed.
  it 'streams the shared services channel' do
    subscribe

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from('services')
  end
end
