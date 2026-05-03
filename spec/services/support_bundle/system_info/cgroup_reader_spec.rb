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
