RSpec.describe SupportBundle::ContainerLogs do
  describe '.filename_for' do
    it 'uses the compose service name when available' do
      container = instance_double(
        Orchestration::Container,
        service_name: 'dashboard',
        name: 'solectrus-dashboard-1',
        id: 'abc123def456',
      )

      expect(described_class.filename_for(container)).to eq('logs/dashboard.log')
    end

    it 'falls back to the container name when service label is missing' do
      container = instance_double(
        Orchestration::Container,
        service_name: nil,
        name: 'standalone-app',
        id: 'abc123def456',
      )

      expect(described_class.filename_for(container)).to eq('logs/standalone-app.log')
    end

    it 'falls back to the short container id as last resort' do
      container = instance_double(
        Orchestration::Container,
        service_name: nil,
        name: nil,
        id: 'abc123def456789',
      )

      expect(described_class.filename_for(container)).to eq('logs/abc123def456.log')
    end

    it 'sanitizes unsafe characters in the filename' do
      container = instance_double(
        Orchestration::Container,
        service_name: 'weird/name with space',
        name: nil,
        id: 'abc',
      )

      expect(described_class.filename_for(container)).to eq('logs/weird_name_with_space.log')
    end
  end

  # Real commands, real pipes, real exit statuses: what this method has to get
  # right is the reading itself.
  describe '.capture_tail' do
    def tail(*command)
      described_class.capture_tail(*command)
    end

    it 'returns the whole output of a command that fits' do
      text, status = tail('printf', 'one\ntwo\n')

      expect(text).to eq("one\ntwo\n")
      expect(status).to be_success
    end

    it 'reads the error output as well' do
      text, = tail('sh', '-c', 'printf "out\n"; printf "err\n" >&2')

      expect(text).to include('out').and include('err')
    end

    it 'reports the exit code of a failing command' do
      _text, status = tail('sh', '-c', 'exit 3')

      expect(status).not_to be_success
      expect(status.exitstatus).to eq(3)
    end

    it 'repairs output that is not UTF-8' do
      text, = tail('printf', 'Gr\374n\n')

      expect(text).to eq("Grün\n")
    end

    context 'with a cap of 20 bytes' do
      before { stub_const("#{described_class}::MAX_BYTES", 20) }

      it 'keeps the newest lines and names how many are gone' do
        text, = tail('sh', '-c', 'for i in 1 2 3 4 5 6 7 8 9 10; do echo "line $i"; done')

        expect(text).to eq("[8 older lines removed to keep the bundle small]\nline 9\nline 10\n")
      end

      it 'keeps the newest line even when it alone exceeds the cap' do
        text, = tail('sh', '-c', 'echo old; printf "%50s\n" "" | tr " " "x"')

        expect(text).to eq("[1 older line removed to keep the bundle small]\n#{'x' * 50}\n")
      end
    end
  end

  describe '.fetch_log' do
    it 'passes the output of a successful docker logs call through' do
      allow(described_class).to receive(:capture_tail).and_return(["booted\n", process_status])

      expect(described_class.fetch_log('abc123def456')).to eq("booted\n")
    end

    it 'keeps the output of a failing docker logs call, with its exit code' do
      allow(described_class).to receive(:capture_tail).and_return(
        ["No such container\n", process_status(success: false)],
      )

      expect(described_class.fetch_log('abc123def456')).to eq("failed (exit 1):\nNo such container\n")
    end

    it 'reports a missing docker binary instead of raising' do
      allow(described_class).to receive(:capture_tail).and_raise(Errno::ENOENT, 'docker')

      expect(described_class.fetch_log('abc123def456')).to start_with('unavailable: Errno::ENOENT')
    end
  end

  describe '.each_log' do
    it 'yields one log per container in the project' do
      container = instance_double(
        Orchestration::Container, service_name: 'dashboard', name: 'solectrus-dashboard-1', id: 'abc123def456'
      )
      allow(Orchestration::Container).to receive(:all).and_return([container])
      allow(described_class).to receive(:capture_tail).and_return(["booted\n", process_status])

      expect { |block| described_class.each_log(&block) }.to yield_with_args('logs/dashboard.log', "booted\n")
    end

    it 'yields an error entry when Docker is not reachable' do
      allow(Orchestration::Container).to receive(:all).and_raise(
        Orchestration::ConnectionError.new('Cannot connect to Docker'),
      )

      entries = {}
      described_class.each_log { |name, content| entries[name] = content }

      expect(entries.keys).to eq(['logs/_error.txt'])
      expect(entries['logs/_error.txt']).to include('Docker unavailable')
    end
  end
end
