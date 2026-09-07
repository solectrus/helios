RSpec.describe Orchestration::DockerCli do
  describe '.inspect_container' do
    it 'returns the first entry of the inspect array' do
      stub_capture2e(JSON.dump([{ 'Id' => 'abc' }]))

      expect(described_class.inspect_container('helios')).to eq('Id' => 'abc')
    end

    it 'returns nil when docker reports a failure' do
      stub_capture2e('No such object: helios', success: false)

      expect(described_class.inspect_container('helios')).to be_nil
    end

    # A daemon that answers with something other than JSON (a warning banner,
    # a truncated reply) must read as "no container", not take the caller down.
    it 'returns nil when the output is not JSON' do
      stub_capture2e('not json at all')

      expect(described_class.inspect_container('helios')).to be_nil
    end
  end

  describe '.running_container' do
    it 'reports start time and args of a running container' do
      stub_capture2e(
        JSON.dump([{ 'State' => { 'Running' => true, 'StartedAt' => '2026-01-02T03:04:05Z' },
                     'Args' => %w[-c restore.sh] }]),
      )

      expect(described_class.running_container('helios-restore-runner')).to have_attributes(
        started_at: Time.utc(2026, 1, 2, 3, 4, 5),
        args: %w[-c restore.sh],
      )
    end

    it 'returns nil for a container that exists but has exited' do
      stub_capture2e(
        JSON.dump([{ 'State' => { 'Running' => false, 'Status' => 'exited', 'ExitCode' => 141, 'Error' => '' } }]),
      )

      expect(described_class.running_container('helios-restore-runner')).to be_nil
    end

    it 'returns nil for a container that does not exist' do
      stub_capture2e('No such object', success: false)

      expect(described_class.running_container('helios-restore-runner')).to be_nil
    end
  end

  describe '.log_tail' do
    it 'returns the requested number of lines, with timestamps on demand' do
      stub_capture2e("line\n")

      expect(described_class.log_tail('helios', lines: 10, timestamps: true)).to eq("line\n")
      expect(Open3).to have_received(:capture2e).with(
        'docker', 'logs', '--tail', '10', '--timestamps', 'helios'
      )
    end

    # Read from request threads on every poll: a hung daemon must not pile up
    # Puma workers, so an unreadable log is an empty log.
    it 'returns an empty string when the read times out' do
      allow(Open3).to receive(:capture2e).and_raise(Timeout::Error)

      expect(described_class.log_tail('helios', lines: 10)).to eq('')
    end
  end

  describe '.pull_image' do
    it 'reports success and output' do
      stub_capture2e("Status: Downloaded\n")

      expect(described_class.pull_image('influxdb:2-alpine')).to eq([true, "Status: Downloaded\n"])
      expect(Open3).to have_received(:capture2e).with('docker', 'pull', 'influxdb:2-alpine')
    end
  end

  describe '.force_remove_container' do
    it 'reports failure and output' do
      stub_capture2e("No such container\n", success: false)

      expect(described_class.force_remove_container('abc')).to eq([false, "No such container\n"])
      expect(Open3).to have_received(:capture2e).with('docker', 'rm', '--force', 'abc')
    end
  end
end
