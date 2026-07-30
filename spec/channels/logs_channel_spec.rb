require 'rails_helper'

RSpec.describe LogsChannel do
  let(:service_name) { 'influxdb' }
  # A real pipe, like the one IO.popen hands back in production. StringIO has no
  # wait_readable, which is what the reader uses to tell a burst from a service
  # that has gone quiet.
  let(:pipe) { IO.pipe }
  let(:fake_io) { pipe.first }
  let(:writer) { pipe.last }
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

  # Ends the reader thread of examples that leave the pipe open.
  after { writer.close unless writer.closed? }

  # Lines are broadcast in batches, so one payload holds an array of HTML.
  def streamed_lines
    broadcasts(subscription.streams.first).flat_map { |b| JSON.parse(b).fetch('html') }
  end

  # Spin until the block turns truthy (or we give up), so assertions never race
  # the reader thread without resorting to a fixed sleep.
  def wait_for(timeout: 2)
    (timeout / 0.02).to_i.times do
      break if yield

      sleep 0.02
    end
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
      before do
        writer.write(
          "influxdb-1  | 2024-03-23T14:30:05.000000000Z Gr\xFCn\n" \
          "influxdb-1  | 2024-03-23T14:30:06.000000000Z after\n",
        )
        writer.close
      end

      it 'repairs the line and keeps streaming' do
        subscribe(service: service_name)
        subscription.instance_variable_get(:@reader_future).wait(5)

        expect(streamed_lines).to include(a_string_including('Grün'), a_string_including('after'))
      end
    end

    # Solid Cable polls at 0.1s, so a broadcast per line would only multiply the
    # writes it hands out in a single cycle anyway.
    context 'with a burst of lines' do
      before do
        writer.write(
          Array.new(20) { |i| "influxdb-1  | 2024-03-23T14:30:#{format('%02d', i)}.000000000Z line #{i}\n" }.join,
        )
        writer.close
      end

      it 'broadcasts them as one batch instead of one message per line' do
        subscribe(service: service_name)
        subscription.instance_variable_get(:@reader_future).wait(5)

        expect(broadcasts(subscription.streams.first).size).to eq(1)
        expect(streamed_lines.size).to eq(20)
      end
    end

    # Batching must not add latency: a service that writes one line and pauses
    # has to show up immediately, not once some buffer fills.
    it 'broadcasts a single line as soon as the service goes quiet' do
      subscribe(service: service_name)
      writer.write("influxdb-1  | 2024-03-23T14:30:05.000000000Z alone\n")

      wait_for { streamed_lines.any? }

      expect(streamed_lines).to contain_exactly(a_string_including('alone'))
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
