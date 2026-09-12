require 'tmpdir'

RSpec.describe HostStats do
  # Point /proc reads at a temp directory of real fixture files, so the tests
  # exercise real filesystem reads and parsing instead of stubbing File.
  let(:proc_root) { Dir.mktmpdir }

  before do
    described_class.reset_cache!
    allow(described_class).to receive(:proc_root).and_return(proc_root)
  end

  after { FileUtils.remove_entry(proc_root) }

  def write_proc_file(name, content)
    File.write(File.join(proc_root, name), content)
  end

  describe '.snapshot' do
    context 'when /proc/stat is available' do
      before do
        allow(Etc).to receive(:nprocessors).and_return(4)
        write_proc_file('stat', "cpu  1000 0 500 8000 100 0 0 0 0 0\n")
        write_proc_file('meminfo', <<~MEMINFO)
          MemTotal:       8000000 kB
          MemAvailable:   2000000 kB
        MEMINFO
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
        write_proc_file('stat', "cpu  1300 0 700 8400 200 0 0 0 0 0\n")
        expect(described_class.snapshot.cpu_percent).to eq(50)
      end

      it 'returns RAM usage as a rounded percentage' do
        # (8000000 - 2000000) / 8000000 * 100 = 75
        expect(described_class.snapshot.ram_percent).to eq(75)
      end

      it 'exposes free and total RAM in bytes' do
        snapshot = described_class.snapshot
        expect(snapshot.ram_free).to eq(2_000_000 * 1024)
        expect(snapshot.ram_total).to eq(8_000_000 * 1024)
      end
    end

    context 'when MemAvailable is missing from /proc/meminfo' do
      before do
        write_proc_file('stat', "cpu  1000 0 500 8000 100 0 0 0 0 0\n")
        write_proc_file('meminfo', "MemTotal:       8000000 kB\n")
      end

      it 'returns nil for ram_percent rather than crashing' do
        expect(described_class.snapshot.ram_percent).to be_nil
      end
    end

    context 'when the Docker host cgroup is mounted' do
      before do
        allow(Orchestration::Connection).to receive(:configure!)
        allow(Docker).to receive(:info).and_return('MemTotal' => 2_000_000_000, 'NCPU' => 2)
        # HostCgroup is exercised by its own spec; stub it at its public API.
        allow(HostCgroup).to receive_messages(memory_used: 400_000_000, cpu_usage_usec: 10_000_000)
      end

      it 'reports RAM usage of the host, not the HELIOS container' do
        # 400e6 bytes used of the 2e9 host limit → 20 %
        snapshot = described_class.snapshot
        expect(snapshot.ram_percent).to eq(20)
        expect(snapshot.ram_free).to eq(1_600_000_000)
        expect(snapshot.ram_total).to eq(2_000_000_000)
      end

      it 'reports the host core count from the Docker daemon' do
        expect(described_class.snapshot.cpu_cores).to eq(2)
      end

      it 'reports CPU usage from the cgroup usage_usec delta' do
        # usage_usec jumps 10s → 15s over 5s wall time, across 2 cores → 50 %.
        allow(HostCgroup).to receive(:cpu_usage_usec).and_return(10_000_000, 15_000_000)
        allow(Process).to receive(:clock_gettime)
          .with(Process::CLOCK_MONOTONIC).and_return(0, 5)
        described_class.snapshot

        expect(described_class.snapshot.cpu_percent).to eq(50)
      end

      it 'falls back to /proc when the Docker daemon is unreachable' do
        allow(Docker).to receive(:info).and_raise(StandardError)
        write_proc_file('meminfo', <<~MEMINFO)
          MemTotal:       8000000 kB
          MemAvailable:   2000000 kB
        MEMINFO

        expect(described_class.snapshot.ram_percent).to eq(75)
      end
    end

    context 'when only the macOS iostat fallback is available' do
      before do
        # No /proc fixtures (empty tmpdir) and the host cgroup is not mounted,
        # so CPU sampling falls through to `iostat`.
        allow(Etc).to receive(:nprocessors).and_return(20)
        allow(Open3).to receive(:capture2e).and_call_original
        allow(Open3).to receive(:capture2e).with(*described_class::IOSTAT_COMMAND)
                                           .and_return([<<~IOSTAT, instance_double(Process::Status, success?: true)])
                                                        disk0               disk4       cpu    load average
                                              KB/t  tps  MB/s     KB/t  tps  MB/s  us sy id   1m   5m   15m
                                             16.29 1414 22.49     4.01    8  0.03   3  2 95 3.69 4.12 4.86
                                             15.07  581  8.54     0.00    0  0.00  14  9 77 3.69 4.12 4.86
                                           IOSTAT
      end

      it 'reports busy CPU as 100 minus the idle percentage of the second sample' do
        # Second sample idle = 77 % → busy = 23 %. The first (since-boot)
        # sample is ignored.
        expect(described_class.snapshot.cpu_percent).to eq(23)
        expect(described_class.snapshot.cpu_cores).to eq(20)
      end
    end

    context 'when no metric source is available' do
      before do
        # /proc fixtures absent (empty tmpdir), host cgroup not mounted, and
        # the macOS sysctl/vm_stat fallbacks unavailable.
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
        write_proc_file('stat', "cpu  1000 0 500 8000 100 0 0 0 0 0\n")
        write_proc_file('meminfo', <<~MEMINFO)
          MemTotal:       8000000 kB
          MemAvailable:   2000000 kB
        MEMINFO
      end

      it 'reuses the snapshot within the TTL window instead of re-reading /proc' do
        first = described_class.snapshot

        # Change the underlying file; an uncached read would pick this up.
        write_proc_file('meminfo', <<~MEMINFO)
          MemTotal:       8000000 kB
          MemAvailable:   1000000 kB
        MEMINFO

        expect(described_class.snapshot).to equal(first)
      end
    end
  end

  # /proc/stat without the aggregate `cpu` line says nothing about CPU usage,
  # so the reader falls through to the next source instead of guessing.
  describe 'reading /proc/stat' do
    it 'reports nothing when the aggregate cpu line is missing' do
      write_proc_file('stat', "intr 12345\n")

      expect(described_class.send(:read_proc_stat)).to be_nil
    end
  end

  # macOS dev fallback: no /proc at all, so the numbers come from sysctl and
  # vm_stat. Both are stubbed, so the examples also run on Linux CI, where
  # these commands exist but answer nothing.
  describe 'the sysctl fallback' do
    it 'reports nothing when sysctl cannot be run' do
      allow(described_class).to receive(:capture_int).and_raise(Errno::ENOENT, 'sysctl')

      expect(described_class.send(:mem_from_sysctl)).to be_nil
    end

    it 'reports total RAM from sysctl and available RAM from the vm_stat pages' do
      page_size = Etc.sysconf(Etc::SC_PAGE_SIZE)
      stub_sysctl(total: '8589934592')
      stub_vm_stat(<<~VM_STAT)
        Mach Virtual Memory Statistics: (page size of #{page_size} bytes)
        Pages free:                               10000.
        Pages inactive:                           20000.
        Pages speculative:                         5000.
      VM_STAT

      expect(described_class.send(:mem_from_sysctl)).to eq([8_589_934_592, 35_000 * page_size])
    end

    it 'reports nothing when sysctl answers no memory size' do
      stub_sysctl(total: 'unknown')

      expect(described_class.send(:mem_from_sysctl)).to be_nil
    end

    it 'reports nothing when vm_stat fails' do
      stub_sysctl(total: '8589934592')
      stub_vm_stat('vm_stat: command not found', success: false)

      expect(described_class.send(:mem_from_sysctl)).to be_nil
    end

    def stub_sysctl(total:)
      allow(Open3).to receive(:capture2e).and_call_original
      allow(Open3).to receive(:capture2e).with('sysctl', '-n', 'hw.memsize')
                                         .and_return([total, instance_double(Process::Status, success?: true)])
    end

    def stub_vm_stat(output, success: true)
      allow(Open3).to receive(:capture2e).with('vm_stat')
                                         .and_return([output, instance_double(Process::Status, success?: success)])
    end
  end

  describe '.proc_root' do
    it 'points at /proc by default' do
      allow(described_class).to receive(:proc_root).and_call_original

      expect(described_class.proc_root).to eq('/proc')
    end
  end
end
