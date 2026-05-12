RSpec.describe HostStats do
  before { described_class.reset_cache! }

  describe '.snapshot' do
    context 'when /proc/stat is available' do
      let(:proc_stat_first) { ["cpu  1000 0 500 8000 100 0 0 0 0 0\n"] }

      # delta vs first: user+sys += 500, idle+iowait += 500 → 50% busy
      let(:proc_stat_second) { ["cpu  1300 0 700 8400 200 0 0 0 0 0\n"] }

      before do
        allow(Etc).to receive(:nprocessors).and_return(4)
        stat_lines = [proc_stat_first, proc_stat_second]
        allow(File).to receive(:foreach).with('/proc/stat') do |&block|
          (stat_lines.shift || proc_stat_second).each(&block)
        end
        allow(File).to receive(:foreach).with('/proc/meminfo')
                                        .and_yield("MemTotal:       8000000 kB\n")
                                        .and_yield("MemAvailable:   2000000 kB\n")
      end

      it 'returns nil for cpu_percent on the first read (no delta yet) but exposes core count' do
        first = described_class.snapshot
        expect(first.cpu_percent).to be_nil
        expect(first.cpu_cores).to eq(4)
      end

      it 'returns CPU usage as a percentage of busy CPU time across the cores' do
        # First call seeds the previous sample (returns nil%), second call
        # computes the delta. Jump the monotonic clock past TTL so the second
        # call actually re-reads /proc/stat instead of returning the cache.
        allow(Process).to receive(:clock_gettime)
          .with(Process::CLOCK_MONOTONIC).and_return(0, 10)
        described_class.snapshot

        # busy delta = (1300-1000) + (700-500) = 500
        # total delta = busy + (8400-8000) + (200-100) = 500 + 500 = 1000
        # → 50 %
        expect(described_class.snapshot.cpu_percent).to eq(50)
      end

      it 'returns RAM usage as a rounded percentage' do
        # (8000000 - 2000000) / 8000000 * 100 = 75
        expect(described_class.snapshot.ram_percent).to eq(75)
      end
    end

    context 'when MemAvailable is missing from /proc/meminfo' do
      before do
        allow(File).to receive(:foreach).with('/proc/stat')
                                        .and_yield("cpu  1000 0 500 8000 100 0 0 0 0 0\n")
        allow(File).to receive(:foreach).with('/proc/meminfo')
                                        .and_yield("MemTotal:       8000000 kB\n")
      end

      it 'returns nil for ram_percent rather than crashing' do
        expect(described_class.snapshot.ram_percent).to be_nil
      end
    end

    context 'when no metric source is available' do
      before do
        allow(File).to receive(:foreach).with('/proc/stat').and_raise(Errno::ENOENT)
        allow(File).to receive(:foreach).with('/proc/meminfo').and_raise(Errno::ENOENT)
        allow(Open3).to receive(:capture2e).and_raise(Errno::ENOENT)
      end

      it 'returns a snapshot with nil values' do
        snapshot = described_class.snapshot
        expect(snapshot.cpu_percent).to be_nil
        expect(snapshot.cpu_cores).to be_nil
        expect(snapshot.ram_percent).to be_nil
      end
    end

    context 'with caching' do
      before do
        allow(File).to receive(:foreach).with('/proc/stat')
                                        .and_yield("cpu  1000 0 500 8000 100 0 0 0 0 0\n")
        allow(File).to receive(:foreach).with('/proc/meminfo')
                                        .and_yield("MemTotal:       8000000 kB\n")
                                        .and_yield("MemAvailable:   2000000 kB\n")
      end

      it 'reuses the snapshot within the TTL window' do
        2.times { described_class.snapshot }

        expect(File).to have_received(:foreach).with('/proc/stat').once
        expect(File).to have_received(:foreach).with('/proc/meminfo').once
      end
    end
  end
end
