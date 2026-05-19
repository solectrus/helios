RSpec.describe SupportBundle::SystemInfo::HostMetrics do
  describe '.format_uptime' do
    it 'shows minutes only for short uptimes' do
      expect(described_class.format_uptime(728)).to eq('12min')
    end

    it 'shows hours and minutes' do
      expect(described_class.format_uptime((1 * 3600) + (5 * 60))).to eq('1h 5min')
    end

    it 'shows days, hours and minutes' do
      expect(described_class.format_uptime((2 * 86_400) + (3 * 3600) + (15 * 60)))
        .to eq('2d 3h 15min')
    end

    it 'omits zero hour/minute parts when days are present' do
      expect(described_class.format_uptime(2 * 86_400)).to eq('2d')
    end

    it 'returns 0min for zero seconds' do
      expect(described_class.format_uptime(0)).to eq('0min')
    end
  end

  describe '.format_cores' do
    it 'renders whole cores without decimals' do
      expect(described_class.format_cores(2.0)).to eq('2')
    end

    it 'renders fractional cores with two decimals' do
      expect(described_class.format_cores(1.5)).to eq('1.50')
    end

    it 'rounds tiny floating point error to a whole number' do
      expect(described_class.format_cores(2.04)).to eq('2')
    end
  end

  describe '.memory' do
    context 'when the Docker host cgroup is bind-mounted' do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with('/host/sys/fs/cgroup/memory.current').and_return(true)
        allow(File).to receive(:exist?).with('/host/sys/fs/cgroup/memory.stat').and_return(true)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with('/host/sys/fs/cgroup/memory.current')
                                     .and_return("1610612736\n")
        allow(File).to receive(:foreach).and_call_original
        allow(File).to receive(:foreach).with('/host/sys/fs/cgroup/memory.stat').and_return(
          ["anon 200000000\n", "inactive_file 268435456\n",
           "active_file 209715200\n", "slab_reclaimable 58720256\n"],
        )
      end

      it 'reports the host RAM (current minus reclaimable), not the HELIOS container' do
        result = described_class.memory(info: { 'MemTotal' => 2_147_483_648 })

        expect(result).to eq(
          'Total' => '2 GB',
          'Used' => '1 GB',
          'Available' => '1 GB',
          'Source' => 'host cgroup',
        )
      end
    end

    context 'when a cgroup v2 memory limit is set' do
      before do
        stub_cgroup(
          v2: true,
          '/sys/fs/cgroup/memory.max' => '1073741824',
          '/sys/fs/cgroup/memory.current' => '333447168',
        )
      end

      it 'reports the cgroup limit and usage instead of /proc/meminfo' do
        result = described_class.memory

        expect(result['Total']).to eq('1 GB')
        expect(result['Used']).to eq('318 MB')
        expect(result['Available']).to eq('706 MB')
        expect(result['Source']).to eq('cgroup v2 (container limit)')
      end
    end

    context 'when cgroup v2 reports no memory limit' do
      before { stub_cgroup(v2: true, '/sys/fs/cgroup/memory.max' => 'max') }

      it 'falls back to /proc/meminfo' do
        expect(described_class.memory).not_to have_key('Source')
      end
    end

    context 'when running on cgroup v1 with a real limit' do
      before do
        stub_cgroup(
          v2: false,
          '/sys/fs/cgroup/memory/memory.limit_in_bytes' => '1073741824',
          '/sys/fs/cgroup/memory/memory.usage_in_bytes' => '200000000',
        )
      end

      it 'reports the v1 limit' do
        result = described_class.memory

        expect(result['Total']).to eq('1 GB')
        expect(result['Source']).to eq('cgroup v1 (container limit)')
      end
    end

    # Docker on a Proxmox LXC: lxcfs overlays /proc/meminfo in the LXC but
    # not inside Docker containers, so /proc/meminfo leaks the Proxmox host
    # (e.g. 16 GB) while the Docker daemon's /info reports the LXC limit
    # (e.g. 1 GB). We trust the smaller daemon value.
    context 'when the Docker daemon reports less RAM than /proc/meminfo' do
      before do
        stub_cgroup(
          v2: true,
          '/sys/fs/cgroup/memory.max' => 'max',
          '/sys/fs/cgroup/memory.current' => '268435456',
        )
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with('/proc/meminfo').and_return(true)
        allow(File).to receive(:foreach).with('/proc/meminfo').and_return(
          ["MemTotal:       16110000 kB\n", "MemAvailable:    5000000 kB\n",
           "SwapTotal:       8000000 kB\n", "SwapFree:        6000000 kB\n"],
        )
      end

      it 'overrides /proc/meminfo with the daemon value plus cgroup usage' do
        result =
          described_class.memory(info: { 'MemTotal' => 1_073_741_824 })

        expect(result).to eq(
          'Total' => '1 GB',
          'Used' => '256 MB',
          'Available' => '768 MB',
          'Source' => 'docker daemon',
        )
      end
    end

    context 'when the daemon overrides but cgroup memory.current is missing' do
      before do
        stub_cgroup(v2: true, '/sys/fs/cgroup/memory.max' => 'max')
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with('/proc/meminfo').and_return(true)
        allow(File).to receive(:foreach).with('/proc/meminfo').and_return(
          ["MemTotal:       16110000 kB\n"],
        )
      end

      it 'still reports Total without Used/Available' do
        result = described_class.memory(info: { 'MemTotal' => 1_073_741_824 })

        expect(result).to eq('Total' => '1 GB', 'Source' => 'docker daemon')
      end
    end

    context 'when the Docker daemon reports the same RAM as /proc/meminfo' do
      before do
        stub_cgroup(v2: true, '/sys/fs/cgroup/memory.max' => 'max')
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with('/proc/meminfo').and_return(true)
        allow(File).to receive(:foreach).with('/proc/meminfo').and_return(
          ["MemTotal:       1048576 kB\n", "MemAvailable:    500000 kB\n",
           "SwapTotal:       1048576 kB\n", "SwapFree:        1000000 kB\n"],
        )
      end

      it 'keeps the /proc/meminfo values (no LXC leak suspected)' do
        result = described_class.memory(info: { 'MemTotal' => 1_073_741_824 })

        expect(result).not_to have_key('Source')
        expect(result['Total']).to eq('1 GB')
        expect(result['Swap total']).to eq('1 GB')
      end
    end
  end

  describe '.cpu' do
    context 'when cpuset restricts the container to two cores' do
      before do
        stub_cgroup(
          v2: true,
          '/sys/fs/cgroup/cpu.max' => 'max 100000',
          '/sys/fs/cgroup/cpuset.cpus.effective' => '0-1',
        )
        allow(described_class).to receive(:proc_cpuinfo)
          .and_return(count: 4, model: 'Intel(R) N150')
      end

      it 'reports two cores from the cpuset' do
        result = described_class.cpu

        expect(result['Cores']).to eq('2')
        expect(result['Model']).to eq('Intel(R) N150')
        expect(result['Source']).to eq('cgroup v2 (container limit)')
      end
    end

    context 'when CFS quota limits CPU to 1.5 cores' do
      before do
        stub_cgroup(v2: true, '/sys/fs/cgroup/cpu.max' => '150000 100000')
        allow(described_class).to receive(:proc_cpuinfo)
          .and_return(count: 4, model: 'Intel(R) N150')
      end

      it 'reports the fractional core count' do
        expect(described_class.cpu['Cores']).to eq('1.50')
      end
    end

    context 'when neither cpu.max nor cpuset constrain the container' do
      before { stub_cgroup(v2: true, '/sys/fs/cgroup/cpu.max' => 'max 100000') }

      it 'returns nil from cpu_from_cgroup so /proc/cpuinfo is used' do
        expect(described_class.cpu_from_cgroup).to be_nil
      end
    end
  end

  describe '.uptime' do
    it 'formats /proc/uptime instead of calling the uptime binary' do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with('/proc/uptime').and_return(true)
      allow(File).to receive(:exist?).with('/proc/loadavg').and_return(true)
      allow(File).to receive(:read).with('/proc/uptime').and_return("728.95 728.95\n")
      allow(File).to receive(:read).with('/proc/loadavg').and_return("0.29 0.58 0.76 1/123 4567\n")

      expect(described_class.uptime).to eq('up 12min, load average: 0.29, 0.58, 0.76')
    end

    it 'falls back to the uptime binary when /proc/uptime is missing' do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with('/proc/uptime').and_return(false)
      allow(SupportBundle::SystemInfo::OutputFormatter)
        .to receive(:capture).with('uptime').and_return('macOS uptime line')

      expect(described_class.uptime).to eq('macOS uptime line')
    end
  end

  describe '.operating_system' do
    let(:info) do
      {
        'OperatingSystem' => 'Debian GNU/Linux 13 (trixie)',
        'KernelVersion' => '6.17.13-3-pve',
        'Architecture' => 'x86_64',
        'Name' => 'helios-lxc',
      }
    end

    it 'returns the Docker host details when running inside a container' do
      allow(described_class).to receive(:containerized?).and_return(true)

      expect(described_class.operating_system(info: info)).to eq(
        'Operating system' => 'Debian GNU/Linux 13 (trixie)',
        'Kernel' => '6.17.13-3-pve',
        'Architecture' => 'x86_64',
        'Hostname' => 'helios-lxc',
      )
    end

    it 'returns the local OS when running natively, ignoring the Docker daemon' do
      allow(described_class).to receive_messages(
        containerized?: false,
        os_release: 'macOS 15.0 (24A335)',
      )
      allow(SupportBundle::SystemInfo::OutputFormatter)
        .to receive(:capture).with('uname', '-sm').and_return('Darwin arm64')
      allow(Socket).to receive(:gethostname).and_return('georgs-mac')

      expect(described_class.operating_system(info: info)).to eq(
        'Operating system' => 'macOS 15.0 (24A335)',
        'Kernel' => 'Darwin',
        'Architecture' => 'arm64',
        'Hostname' => 'georgs-mac',
      )
    end

    it 'falls back to the local OS when Docker info is unavailable' do
      allow(described_class).to receive_messages(
        containerized?: true,
        os_release: 'Ubuntu 24.04',
      )
      allow(SupportBundle::SystemInfo::OutputFormatter)
        .to receive(:capture).with('uname', '-sm').and_return('Linux x86_64')
      allow(Socket).to receive(:gethostname).and_return('ci-runner')

      expect(described_class.operating_system(error: 'unavailable: boom'))
        .to include('Operating system' => 'Ubuntu 24.04')
    end
  end

  describe '.parse_df' do
    it 'parses portable df output and converts blocks to human bytes' do
      output = <<~DF
        Filesystem        1024-blocks       Used Available Capacity Mounted on
        /dev/disk3s5       3902665360 1614637424 2265170460      42% /
      DF
      allow(SupportBundle::SystemInfo::OutputFormatter)
        .to receive(:capture).with('df', '-kP', '/x').and_return(output.strip)

      expect(described_class.parse_df('/x')).to eq(
        'Filesystem' => '/dev/disk3s5',
        'Total' => '3.63 TB',
        'Used' => '1.5 TB',
        'Available' => '2.11 TB',
        'Capacity' => '42%',
      )
    end

    it 'returns nil when df fails so the caller can fall back' do
      allow(SupportBundle::SystemInfo::OutputFormatter)
        .to receive(:capture).with('df', '-kP', '/x')
        .and_return('failed (exit 1): df: /x: No such file or directory')

      expect(described_class.parse_df('/x')).to be_nil
    end
  end

  # Single helper for the cgroup-stub pattern: pass `v2: true/false` plus a
  # path => content mapping. Files not in the mapping return nil.
  def stub_cgroup(v2:, **paths) # rubocop:disable Naming/MethodParameterName
    allow(SupportBundle::SystemInfo::CgroupReader).to receive(:v2?).and_return(v2)
    allow(SupportBundle::SystemInfo::CgroupReader).to receive(:read_first_line) { |path| paths[path] }
  end
end
