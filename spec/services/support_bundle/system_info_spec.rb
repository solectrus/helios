RSpec.describe SupportBundle::SystemInfo do
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

    context 'when cgroup v1 reports the sentinel "no limit" value' do
      before do
        stub_cgroup(
          v2: false,
          '/sys/fs/cgroup/memory/memory.limit_in_bytes' => '9223372036854771712',
        )
      end

      it 'treats it as unlimited and skips the cgroup section' do
        expect(described_class.memory_from_cgroup).to be_nil
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

    context 'when cpuset covers every host CPU' do
      before do
        stub_cgroup(
          v2: true,
          '/sys/fs/cgroup/cpu.max' => 'max 100000',
          '/sys/fs/cgroup/cpuset.cpus.effective' => '0-3',
        )
        allow(described_class).to receive(:proc_cpuinfo).and_return(count: 4, model: nil)
      end

      it 'treats it as no restriction and skips the cgroup section' do
        expect(described_class.cpu_from_cgroup).to be_nil
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
      allow(described_class).to receive(:capture).with('uptime').and_return('macOS uptime line')

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
      allow(described_class).to receive(:capture).with('uname', '-sm').and_return('Darwin arm64')
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
      allow(described_class).to receive(:capture).with('uname', '-sm').and_return('Linux x86_64')
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
      allow(described_class).to receive(:capture).with('df', '-kP', '/x').and_return(output.strip)

      expect(described_class.parse_df('/x')).to eq(
        'Filesystem' => '/dev/disk3s5',
        'Total' => '3.63 TB',
        'Used' => '1.5 TB',
        'Available' => '2.11 TB',
        'Capacity' => '42%',
      )
    end

    it 'returns nil when df fails so the caller can fall back' do
      allow(described_class).to receive(:capture).with('df', '-kP', '/x').and_return(
        'failed (exit 1): df: /x: No such file or directory',
      )

      expect(described_class.parse_df('/x')).to be_nil
    end
  end

  # Sanity check: every section must produce a value on the host that is
  # actually running the suite (Linux CI, macOS dev). No method should raise
  # because /proc, /sys, sysctl or a binary is missing.
  describe '.collect on the live host' do
    before do
      allow(described_class).to receive(:fetch_docker_snapshot).and_return(
        { error: 'unavailable: stubbed' },
      )
      allow(Rails.configuration).to receive(:data_path).and_return(Dir.tmpdir)
    end

    it 'renders without raising' do
      expect { described_class.collect }.not_to raise_error
    end

    it 'includes a CPU section with cores' do
      report = described_class.collect
      cpu_section = report[/=== CPU ===\n.*?(?=\n===|\z)/m]

      expect(cpu_section).to match(/Cores\s+\S+/)
    end

    it 'includes a Memory section with a total value' do
      report = described_class.collect
      mem_section = report[/=== Memory ===\n.*?(?=\n===|\z)/m]

      expect(mem_section).to match(/Total\s+\S+/)
    end

    it 'includes a non-empty Uptime line' do
      report = described_class.collect
      uptime_section = report[/=== Uptime ===\n.*?(?=\n===|\z)/m]

      expect(uptime_section.to_s.strip).not_to be_empty
    end

    it 'includes a Disk section with parsed totals' do
      report = described_class.collect
      disk_section = report[/=== Disk ===\n.*?(?=\n===|\z)/m]

      expect(disk_section).to match(/Total\s+\S+/)
      expect(disk_section).to match(/Available\s+\S+/)
    end
  end

  # Single helper for the cgroup-stub pattern: pass `v2: true/false` plus a
  # path => content mapping. Files not in the mapping return nil.
  def stub_cgroup(v2:, **paths) # rubocop:disable Naming/MethodParameterName
    allow(described_class).to receive(:cgroup_v2?).and_return(v2)
    allow(described_class).to receive(:read_first_line) { |path| paths[path] }
  end
end
