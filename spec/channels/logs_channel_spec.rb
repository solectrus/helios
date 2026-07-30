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
    # Truthy return simulates the process having exited so wait_for_exit's
    # loop ends on the first iteration instead of waiting out the timeout.
    allow(Process).to receive(:wait).and_return(fake_pid)
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

    # Regression: the invalid byte raised in the formatter, #read_log_stream
    # only rescues IOError and the future swallowed the rest — the live log
    # froze silently and never recovered.
    context 'with non-UTF-8 log output' do
      let(:fake_io) do
        StringIO.new(
          "influxdb-1  | 2024-03-23T14:30:05.000000000Z Gr\xFCn\n" \
          "influxdb-1  | 2024-03-23T14:30:06.000000000Z after\n",
        )
      end

      it 'repairs the line and keeps streaming' do
        subscribe(service: service_name)
        subscription.instance_variable_get(:@reader_future).wait(5)

        html = broadcasts(subscription.streams.first).map { |b| JSON.parse(b).fetch('html') }
        expect(html).to include(a_string_including('Grün'), a_string_including('after'))
      end
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
      subscription.instance_variable_get(:@cleanup_future)&.wait(5)

      expect(Process).to have_received(:kill).with('TERM', fake_pid)
    end

    # Regression: blocking #unsubscribed kept the previous subscription in the
    # connection's hash. Rails dropped the new subscribe with the same
    # identifier, no confirmation came back, and the UI hung on "Connecting…".
    it 'returns immediately even when process cleanup is slow' do
      allow(Process).to receive(:kill) { sleep 1 }

      subscribe(service: service_name)

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      subscription.unsubscribe_from_channel
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

      expect(elapsed).to be < 0.2
    end
  end
end
