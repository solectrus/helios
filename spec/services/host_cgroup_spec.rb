require 'tmpdir'

RSpec.describe HostCgroup do
  # Point the service at a temp directory of real cgroup fixture files,
  # so the tests exercise real filesystem reads instead of stubbing File.
  let(:cgroup_root) { Dir.mktmpdir }

  before { allow(described_class).to receive(:root).and_return(cgroup_root) }
  after { FileUtils.remove_entry(cgroup_root) }

  def write_cgroup_file(name, content)
    File.write(File.join(cgroup_root, name), content)
  end

  describe '.memory_current' do
    it 'reads the byte count from the host cgroup' do
      write_cgroup_file('memory.current', "1221120000\n")

      expect(described_class.memory_current).to eq(1_221_120_000)
    end

    it 'returns nil when the host cgroup is not mounted' do
      expect(described_class.memory_current).to be_nil
    end
  end

  describe '.memory_reclaimable' do
    it 'sums the reclaimable memory.stat fields' do
      write_cgroup_file('memory.stat', <<~STAT)
        anon 300000000
        inactive_file 400000000
        active_file 150000000
        slab_reclaimable 50000000
      STAT

      expect(described_class.memory_reclaimable).to eq(600_000_000)
    end

    it 'returns nil when the host cgroup is not mounted' do
      expect(described_class.memory_reclaimable).to be_nil
    end
  end

  describe '.memory_used' do
    it 'returns memory.current minus the reclaimable bytes' do
      write_cgroup_file('memory.current', "1000000000\n")
      write_cgroup_file('memory.stat', <<~STAT)
        inactive_file 400000000
        active_file 150000000
        slab_reclaimable 50000000
      STAT

      expect(described_class.memory_used).to eq(400_000_000)
    end

    it 'returns nil when the host cgroup is not mounted' do
      expect(described_class.memory_used).to be_nil
    end
  end

  describe '.cpu_usage_usec' do
    it 'reads usage_usec from cpu.stat' do
      write_cgroup_file('cpu.stat', <<~STAT)
        usage_usec 15000000
        user_usec 9000000
        system_usec 6000000
      STAT

      expect(described_class.cpu_usage_usec).to eq(15_000_000)
    end

    it 'returns nil when the host cgroup is not mounted' do
      expect(described_class.cpu_usage_usec).to be_nil
    end
  end
end
