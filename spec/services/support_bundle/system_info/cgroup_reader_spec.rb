RSpec.describe SupportBundle::SystemInfo::CgroupReader do
  describe '.parse_cpuset_count' do
    it 'counts a single cpu id' do
      expect(described_class.parse_cpuset_count('3')).to eq(1)
    end

    it 'counts a range inclusively' do
      expect(described_class.parse_cpuset_count('0-1')).to eq(2)
    end

    it 'sums ranges and singletons' do
      expect(described_class.parse_cpuset_count('0,2,4-5')).to eq(4)
    end

    it 'returns 0 for an empty cpuset' do
      expect(described_class.parse_cpuset_count('')).to eq(0)
    end

    it 'ignores a part that is neither a number nor a range' do
      expect(described_class.parse_cpuset_count('0,junk,2')).to eq(2)
    end
  end

  describe '.read_first_line' do
    let(:tmp_dir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(tmp_dir) }

    it 'returns the stripped first line' do
      path = File.join(tmp_dir, 'value')
      File.write(path, "42\n99\n")

      expect(described_class.read_first_line(path)).to eq('42')
    end

    it 'returns nil for a missing file' do
      expect(described_class.read_first_line(File.join(tmp_dir, 'nope'))).to be_nil
    end

    # An empty cgroup file makes readline raise EOFError; the reader must not
    # take the whole support bundle down with it.
    it 'returns nil when the file is empty' do
      path = File.join(tmp_dir, 'empty')
      File.write(path, '')

      expect(described_class.read_first_line(path)).to be_nil
    end
  end

  describe '.memory_limit' do
    context 'when cgroup v1 reports the sentinel "no limit" value' do
      before do
        stub_cgroup(
          v2: false,
          '/sys/fs/cgroup/memory/memory.limit_in_bytes' => '9223372036854771712',
        )
      end

      it 'treats it as unlimited and returns nil' do
        expect(described_class.memory_limit).to be_nil
      end
    end

    context 'when cgroup v2 reports "max"' do
      before { stub_cgroup(v2: true, '/sys/fs/cgroup/memory.max' => 'max') }

      it 'returns nil so the caller falls back to /proc/meminfo' do
        expect(described_class.memory_limit).to be_nil
      end
    end
  end

  describe '.v2?' do
    it 'is true when the unified hierarchy exposes cgroup.controllers' do
      stub_host_file('/sys/fs/cgroup/cgroup.controllers')

      expect(described_class).to be_v2
      expect(described_class.source).to eq('cgroup v2 (container limit)')
    end

    it 'is false without it, so the v1 paths are used' do
      stub_missing_host_file('/sys/fs/cgroup/cgroup.controllers')

      expect(described_class).not_to be_v2
      expect(described_class.source).to eq('cgroup v1 (container limit)')
    end
  end

  describe '.cpu_quota_cores' do
    it 'divides quota by period on cgroup v2' do
      stub_cgroup(v2: true, '/sys/fs/cgroup/cpu.max' => '150000 100000')

      expect(described_class.cpu_quota_cores).to eq(1.5)
    end

    it 'reads the two CFS files on cgroup v1' do
      stub_cgroup(
        v2: false,
        '/sys/fs/cgroup/cpu/cpu.cfs_quota_us' => '200000',
        '/sys/fs/cgroup/cpu/cpu.cfs_period_us' => '100000',
      )

      expect(described_class.cpu_quota_cores).to eq(2.0)
    end

    it 'is nil when cgroup v2 reports no quota' do
      stub_cgroup(v2: true, '/sys/fs/cgroup/cpu.max' => 'max 100000')

      expect(described_class.cpu_quota_cores).to be_nil
    end
  end

  describe '.cpuset_cores' do
    context 'when the cpuset covers every host CPU' do
      before do
        stub_cgroup(
          v2: true,
          '/sys/fs/cgroup/cpuset.cpus.effective' => '0-3',
        )
      end

      it 'treats it as no restriction and returns nil' do
        expect(described_class.cpuset_cores(host_cpu_count: 4)).to be_nil
      end
    end

    context 'when the cpuset is a strict subset of host CPUs' do
      before do
        stub_cgroup(
          v2: true,
          '/sys/fs/cgroup/cpuset.cpus.effective' => '0-1',
        )
      end

      it 'reports the restricted core count' do
        expect(described_class.cpuset_cores(host_cpu_count: 4)).to eq(2.0)
      end
    end
  end

  def stub_cgroup(v2:, **paths) # rubocop:disable Naming/MethodParameterName
    allow(described_class).to receive(:v2?).and_return(v2)
    allow(described_class).to receive(:read_first_line) { |path| paths[path] }
  end
end
