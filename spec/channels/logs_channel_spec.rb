require 'rails_helper'

RSpec.describe LogsChannel do
  let(:service_name) { 'influxdb' }
  let(:fake_io) { StringIO.new }
  let(:fake_pid) { 99_999 }

  before do
    compose_file = instance_double(Compose::File)
    instance_double(Compose::Service, name: service_name)
    allow(compose_file).to receive(:services).and_return(
      instance_double(Compose::ServiceCollection).tap do |collection|
        allow(collection).to receive(:any?).and_return(true)
      end,
    )
    allow(Compose).to receive(:load).and_return(compose_file)
    allow(Orchestration::Runner).to receive(:stream_logs).and_return([fake_io, fake_pid])
    allow(Process).to receive(:wait)
    allow(Process).to receive(:kill)
  end

  describe '#subscribed' do
    it 'streams for a valid service' do
      subscribe(service: service_name)

      expect(subscription).to be_confirmed
      expect(subscription.streams.first).to start_with("logs:#{service_name}:")
    end

    it 'starts streaming logs from Docker Compose' do
      subscribe(service: service_name)

      expect(Orchestration::Runner).to have_received(:stream_logs).with(service: service_name, tail: 0)
    end

    it 'rejects subscription for blank service' do
      subscribe(service: '')

      expect(subscription).to be_rejected
    end

    it 'rejects subscription for unknown service' do
      compose_file = instance_double(Compose::File)
      allow(compose_file).to receive(:services).and_return(
        instance_double(Compose::ServiceCollection).tap do |collection|
          allow(collection).to receive(:any?).and_return(false)
        end,
      )
      allow(Compose).to receive(:load).and_return(compose_file)

      subscribe(service: 'nonexistent')

      expect(subscription).to be_rejected
    end

    it 'rejects subscription when limit is reached' do
      identifiers = Array.new(described_class::MAX_SUBSCRIPTIONS) do
        { channel: 'LogsChannel' }.to_json
      end
      stub_connection(
        subscriptions: instance_double(
          ActionCable::Connection::Subscriptions,
          identifiers:,
          remove_subscription: nil,
          add: nil,
        ),
      )

      subscribe(service: service_name)

      expect(subscription).to be_rejected
    end
  end

  describe '#unsubscribed' do
    it 'stops the streaming process' do
      subscribe(service: service_name)
      subscription.unsubscribe_from_channel

      expect(Process).to have_received(:kill).with('TERM', fake_pid)
    end
  end
end
