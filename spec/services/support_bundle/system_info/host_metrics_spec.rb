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

  # A locked-down host still has to produce a bundle: every reader answers
  # with no value, and only the memory section carries the reason.
  describe 'a host file that is there but cannot be read' do
    {
      '/proc/cpuinfo' => :proc_cpuinfo,
      '/proc/uptime' => :uptime_from_proc,
      '/proc/loadavg' => :read_loadavg,
      '/etc/os-release' => :linux_os_release,
    }.each do |path, reader|
      it "makes .#{reader} answer with nothing" do
        stub_host_file(path, error: Errno::EACCES)

        expect(described_class.public_send(reader)).to be_nil
      end
    end

    it 'reports it in the memory section instead of raising' do
      stub_host_file('/proc/meminfo', error: Errno::EACCES)

      expect(described_class.memory_from_proc['Status']).to start_with('unavailable: Errno::EACCES')
    end
  end

  describe '.containerized?' do
    it 'is true when the Docker marker file is present' do
      stub_host_file('/.dockerenv')

      expect(described_class).to be_containerized
    end

    # Without the marker, the container runtime shows up in PID 1's cgroup.
    { "0::/docker/abc\n" => true, "0::/init.scope\n" => false }.each do |cgroup, containerized|
      it "is #{containerized} for #{cgroup.strip}" do
        stub_missing_host_file('/.dockerenv')
        stub_host_file('/proc/1/cgroup', content: cgroup)

        expect(described_class.containerized?).to be(containerized)
      end
    end

    it 'is false when the cgroup file cannot be read' do
      stub_missing_host_file('/.dockerenv')
      stub_host_file('/proc/1/cgroup', error: Errno::EACCES)

      expect(described_class).not_to be_containerized
    end
  end

  describe '.proc_cpuinfo' do
    it 'counts the processors and reads the model name' do
      stub_host_file('/proc/cpuinfo',
                     lines: ["processor\t: 0\n", "model name\t: Intel(R) N150\n", "processor\t: 1\n"])

      expect(described_class.proc_cpuinfo).to eq(count: 2, model: 'Intel(R) N150')
      expect(described_class.cpu_from_proc).to include('Model' => 'Intel(R) N150', 'Cores' => 2)
    end

    it 'falls back to "unknown" when the file names no model' do
      stub_host_file('/proc/cpuinfo', lines: ["processor\t: 0\n"])

      expect(described_class.cpu_from_proc).to include('Model' => 'unknown')
    end

    it 'is nil when the file lists no processor at all' do
      stub_host_file('/proc/cpuinfo', lines: ["flags\t: none\n"])

      expect(described_class.proc_cpuinfo).to be_nil
    end
  end

  describe '.linux_os_release' do
    it 'reads the pretty name, unquoted' do
      stub_host_file('/etc/os-release',
                     lines: ["ID=debian\n", %(PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"\n)])

      expect(described_class.linux_os_release).to eq('Debian GNU/Linux 12 (bookworm)')
    end

    it 'is nil when the file names no pretty name' do
      stub_host_file('/etc/os-release', lines: ["ID=debian\n"])

      expect(described_class.linux_os_release).to be_nil
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

    it 'returns the Docker host details when running inside a container, hostname masked' do
      allow(described_class).to receive(:containerized?).and_return(true)

      result = described_class.operating_system(info: info)

      expect(result).to include(
        'Operating system' => 'Debian GNU/Linux 13 (trixie)',
        'Kernel' => '6.17.13-3-pve',
        'Architecture' => 'x86_64',
      )
      expect(result['Hostname']).to match(/\A[A-Z]{5}\z/)
    end

    it 'returns the local OS when running natively, hostname masked' do
      allow(described_class).to receive_messages(
        containerized?: false,
        os_release: 'macOS 15.0 (24A335)',
      )
      allow(SupportBundle::SystemInfo::OutputFormatter)
        .to receive(:capture).with('uname', '-sm').and_return('Darwin arm64')
      allow(Socket).to receive(:gethostname).and_return('georgs-mac')

      result = described_class.operating_system(info: info)

      expect(result).to include(
        'Operating system' => 'macOS 15.0 (24A335)',
        'Kernel' => 'Darwin',
        'Architecture' => 'arm64',
      )
      expect(result['Hostname']).to match(/\A[A-Z]{5}\z/)
    end

    it 'falls back to the local OS when Docker info is unavailable' do
      allow(described_class).to receive_messages(
        containerized?: true,
        os_release: 'Ubuntu 24.04',
      )
      allow(SupportBundle::SystemInfo::OutputFormatter)
        .to receive(:capture).with('uname', '-sm').and_return('Linux x86_64')

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

  # macOS dev boxes have no /proc and no cgroup filesystem; every value comes
  # from sysctl and vm_stat there. The stubs keep these examples deterministic
  # on Linux CI, where those binaries answer nothing useful.
  describe 'the macOS fallbacks' do
    before do
      stub_missing_host_file('/usr/sbin/sysctl')
      stub_host_file('/sbin/sysctl')
    end

    it 'reads model and core count from sysctl' do
      stub_capture(%w[sysctl -n machdep.cpu.brand_string hw.ncpu], "Apple M4 Pro\n14")

      expect(described_class.cpu_from_sysctl).to eq('Model' => 'Apple M4 Pro', 'Cores' => '14')
    end

    it 'falls back to "unknown" when sysctl answers nothing' do
      stub_capture(%w[sysctl -n machdep.cpu.brand_string hw.ncpu], '')

      expect(described_class.cpu_from_sysctl).to eq('Model' => 'unknown', 'Cores' => 'unknown')
    end

    it 'reports total RAM from sysctl and available RAM from vm_stat' do
      stub_capture(%w[sysctl -n hw.memsize hw.pagesize], "2147483648\n16384")
      stub_capture(['vm_stat'], <<~VM_STAT)
        Mach Virtual Memory Statistics: (page size of 16384 bytes)
        Pages free:                               10000.
        Pages inactive:                           20000.
        Pages speculative:                         2536.
      VM_STAT

      expect(described_class.memory_from_sysctl).to eq('Total' => '2 GB', 'Available' => '508 MB')
    end

    it 'reports unknown available RAM when sysctl gives no page size' do
      stub_capture(%w[sysctl -n hw.memsize hw.pagesize], '2147483648')

      expect(described_class.memory_from_sysctl).to eq('Total' => '2 GB', 'Available' => 'unknown')
    end

    it 'reads the product name, version and build from sw_vers' do
      stub_missing_host_file('/etc/os-release')
      stub_host_file('/usr/bin/sw_vers')
      stub_capture(['sw_vers'], <<~SW_VERS)
        ProductName:\t\tmacOS
        ProductVersion:\t\t15.0
        BuildVersion:\t\t24A335
      SW_VERS

      expect(described_class.macos_os_release).to eq('macOS 15.0 (24A335)')
      expect(described_class.os_release).to eq('macOS 15.0 (24A335)')
    end
  end

  describe '.os_release' do
    it 'is unavailable when neither os-release nor sw_vers exist' do
      stub_missing_host_file('/etc/os-release')
      stub_missing_host_file('/usr/bin/sw_vers')

      expect(described_class.os_release).to eq('unavailable')
    end
  end

  describe '.disk' do
    before { allow(Rails.configuration).to receive(:data_path).and_return('/data') }

    it 'reports the parsed df values next to the data path' do
      allow(described_class).to receive(:parse_df).with('/data').and_return('Total' => '1 TB')

      expect(described_class.disk).to eq('Data path' => '/data', 'Total' => '1 TB')
    end

    it 'falls back to the raw df output when parsing fails' do
      allow(described_class).to receive(:parse_df).with('/data').and_return(nil)
      stub_capture(%w[df -kP /data], 'df: /data: No such file or directory')

      expect(described_class.disk).to eq(
        'Data path' => '/data',
        'Usage' => 'df: /data: No such file or directory',
      )
    end
  end

  describe '.data_volumes' do
    let(:data_path) { Dir.mktmpdir }

    before { allow(Rails.configuration).to receive(:data_path).and_return(data_path) }

    after { FileUtils.remove_entry(data_path) }

    it 'reports the size of every subdirectory of the data path' do
      FileUtils.mkdir_p(File.join(data_path, 'influxdb'))
      FileUtils.mkdir_p(File.join(data_path, 'postgresql'))
      File.write(File.join(data_path, 'compose.yaml'), "services:\n")

      result = described_class.data_volumes

      expect(result.keys).to eq(%w[influxdb postgresql])
      expect(result.values).to all(match(/\A\d+(\.\d+)? (Bytes|[KMGT]B)\z/))
    end

    it 'reports an empty data path' do
      expect(described_class.data_volumes).to eq('Status' => 'no data directories found')
    end

    it 'reports a data path that does not exist' do
      allow(Rails.configuration).to receive(:data_path).and_return(File.join(data_path, 'gone'))

      expect(described_class.data_volumes).to eq('Status' => 'data path unavailable')
    end

    it 'reports unknown sizes when du fails' do
      FileUtils.mkdir_p(File.join(data_path, 'influxdb'))
      allow(described_class).to receive(:directory_sizes).and_call_original
      stub_capture(['du', '-sk', File.join(data_path, 'influxdb')], 'failed (exit 1): du: cannot read')

      expect(described_class.data_volumes).to eq('influxdb' => 'unknown')
    end
  end

  # Single helper for the cgroup-stub pattern: pass `v2: true/false` plus a
  # path => content mapping. Files not in the mapping return nil.
  def stub_cgroup(v2:, **paths) # rubocop:disable Naming/MethodParameterName
    allow(SupportBundle::SystemInfo::CgroupReader).to receive(:v2?).and_return(v2)
    allow(SupportBundle::SystemInfo::CgroupReader).to receive(:read_first_line) { |path| paths[path] }
  end

  def stub_capture(command, output)
    allow(SupportBundle::SystemInfo::OutputFormatter)
      .to receive(:capture).with(*command).and_return(output)
  end
end
