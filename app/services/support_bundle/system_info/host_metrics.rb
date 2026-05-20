module SupportBundle
  module SystemInfo
    # Host-side metrics for the support bundle: OS identification, CPU,
    # memory, uptime, disk and per-volume sizes. Each method is defensive
    # and falls back across cgroup → /proc → sysctl so the report stays
    # useful on Linux containers, bare-metal Linux and macOS dev boxes.
    module HostMetrics # rubocop:disable Metrics/ModuleLength
      module_function

      # When HELIOS runs inside a Docker container, `uname`/`/etc/os-release`
      # describe the image, not the box the user administers; Docker's /info
      # endpoint reports the daemon host (Proxmox LXC, VM, bare metal), which
      # is what support needs. When HELIOS runs natively (e.g. development on
      # macOS), the Docker daemon may be a local VM (Docker Desktop's LinuxKit)
      # that has nothing to do with the user's actual host — so we read local
      # /etc/os-release or sw_vers instead and show Docker host details only
      # in the Docker Engine section.
      def operating_system(docker)
        return docker_host_os(docker[:info]) if containerized? && docker[:info]

        local_os
      end

      def docker_host_os(info)
        {
          'Operating system' => info['OperatingSystem'],
          'Kernel' => info['KernelVersion'],
          'Architecture' => info['Architecture'],
          'Hostname' => Anonymizer.mask(info['Name']),
        }
      end

      def local_os
        kernel, arch = OutputFormatter.capture('uname', '-sm').split(/\s+/, 2)
        {
          'Operating system' => os_release,
          'Kernel' => kernel || 'unknown',
          'Architecture' => arch || 'unknown',
          'Hostname' => Anonymizer.mask(Socket.gethostname),
        }
      end

      # /.dockerenv is dropped into every Docker container by the daemon;
      # /proc/1/cgroup leaks the container runtime in PID 1's cgroup path on
      # most setups. Either signal alone is enough — we are containerized
      # whenever one of them matches.
      def containerized?
        return true if File.exist?('/.dockerenv')
        return false unless File.exist?('/proc/1/cgroup')

        File.read('/proc/1/cgroup').match?(/docker|containerd|kubepods|libpod/)
      rescue StandardError
        false
      end

      def cpu
        cpu_from_cgroup || cpu_from_proc || cpu_from_sysctl || { 'Status' => 'unavailable' }
      end

      def cpu_from_cgroup
        cores = [CgroupReader.cpu_quota_cores,
                 CgroupReader.cpuset_cores(host_cpu_count: proc_cpuinfo&.dig(:count))].compact.min
        return nil unless cores

        {
          'Model' => proc_cpuinfo&.dig(:model) || 'unknown',
          'Cores' => format_cores(cores),
          'Source' => CgroupReader.source,
        }
      end

      def cpu_from_proc
        info = proc_cpuinfo
        return nil unless info

        { 'Model' => info[:model] || 'unknown', 'Cores' => info[:count] }
      end

      def proc_cpuinfo
        return nil unless File.exist?('/proc/cpuinfo')

        count = 0
        model = nil
        File.foreach('/proc/cpuinfo') do |line|
          count += 1 if line.start_with?('processor')
          model ||= OutputFormatter.value_after(line, ':') if line.start_with?('model name')
        end
        count.positive? ? { count: count, model: model } : nil
      rescue StandardError
        nil
      end

      def cpu_from_sysctl
        return nil unless sysctl_available?

        model, cores =
          OutputFormatter.capture('sysctl', '-n', 'machdep.cpu.brand_string', 'hw.ncpu').split("\n", 2)
        { 'Model' => model || 'unknown', 'Cores' => cores || 'unknown' }
      end

      def memory(docker = nil)
        memory_from_host_cgroup(docker) || memory_from_cgroup ||
          memory_from_proc(docker) || memory_from_sysctl || { 'Status' => 'unavailable' }
      end

      # RAM of the Docker host from its bind-mounted cgroup (HostCgroup),
      # against the daemon's MemTotal. Mirrors HostStats so the header and
      # this report agree. nil when the host cgroup is not mounted — e.g.
      # bare-metal/VM hosts, where the /proc-based paths below are accurate.
      def memory_from_host_cgroup(docker)
        used = HostCgroup.memory_used
        total = docker_info_mem_total(docker)
        return nil unless used && total

        {
          'Total' => OutputFormatter.human_bytes(total),
          'Used' => OutputFormatter.human_bytes(used),
          'Available' => OutputFormatter.human_bytes([total - used, 0].max),
          'Source' => 'host cgroup',
        }
      end

      def memory_from_cgroup
        limit = CgroupReader.memory_limit
        return nil unless limit

        current = CgroupReader.memory_current
        result = { 'Total' => OutputFormatter.human_bytes(limit) }
        if current
          result['Used'] = OutputFormatter.human_bytes(current)
          result['Available'] = OutputFormatter.human_bytes([limit - current, 0].max)
        end
        result['Source'] = CgroupReader.source
        result
      end

      def memory_from_proc(docker = nil)
        return nil unless File.exist?('/proc/meminfo')

        entries = File.foreach('/proc/meminfo').each_with_object({}) do |line, acc|
          key, value = line.split(':', 2)
          acc[key] = value.strip if value
        end

        docker_daemon_meminfo_override(docker, entries) || {
          'Total' => format_meminfo(entries['MemTotal']),
          'Available' => format_meminfo(entries['MemAvailable']),
          'Swap total' => format_meminfo(entries['SwapTotal']),
          'Swap free' => format_meminfo(entries['SwapFree']),
        }
      rescue StandardError => e
        { 'Status' => "unavailable: #{e.class}: #{e.message}" }
      end

      # When HELIOS runs in a container whose /proc/meminfo is not namespaced
      # — e.g. Docker on a Proxmox LXC, where lxcfs overlays the LXC's /proc
      # but not the inner container's, or some Kubernetes nodes — MemTotal
      # reflects the physical host instead of the container's real limit.
      # The Docker daemon sits one layer above the container and reports its
      # own cgroup view, so when it sees a smaller MemTotal, /proc/meminfo
      # (and its MemAvailable/Swap fields) are leaking host numbers and we
      # surface only the daemon value rather than mixing the two.
      def docker_daemon_meminfo_override(docker, entries)
        daemon_total = docker_info_mem_total(docker)
        return nil unless daemon_total

        proc_total = entries['MemTotal'].to_i * 1024
        return nil unless proc_total.positive? && daemon_total < proc_total

        result = { 'Total' => OutputFormatter.human_bytes(daemon_total) }
        current = CgroupReader.memory_current
        if current&.positive?
          result['Used'] = OutputFormatter.human_bytes(current)
          result['Available'] = OutputFormatter.human_bytes([daemon_total - current, 0].max)
        end
        result['Source'] = 'docker daemon'
        result
      end

      def docker_info_mem_total(docker)
        return nil unless docker.is_a?(Hash)

        info = docker[:info]
        total = info.is_a?(Hash) ? info['MemTotal'] : nil
        total if total.is_a?(Numeric) && total.positive?
      end

      # /proc/meminfo reports values as "<kibibytes> kB"; convert to bytes
      # so the unit auto-scales like every other size in the report.
      def format_meminfo(raw)
        match = raw.to_s.match(/\A(\d+)\s*kB\z/)
        return 'unknown' unless match

        OutputFormatter.human_bytes(match[1].to_i * 1024)
      end

      def memory_from_sysctl
        return nil unless sysctl_available?

        memsize, pagesize = OutputFormatter.capture('sysctl', '-n', 'hw.memsize', 'hw.pagesize').split("\n", 2)

        {
          'Total' => OutputFormatter.human_bytes(memsize.to_i),
          'Available' => sysctl_free_memory(pagesize),
        }
      end

      # vm_stat reports memory in pages; "free + inactive + speculative" is
      # the closest macOS equivalent to Linux's MemAvailable — pages that
      # can be reclaimed for new allocations without swapping.
      def sysctl_free_memory(page_size)
        return 'unknown' unless page_size.to_s.match?(/\A\d+\z/)

        vm = OutputFormatter.capture('vm_stat')
        pages = %w[free inactive speculative].sum do |kind|
          line = vm.lines.find { |l| l.match?(/\APages #{kind}:/i) }
          line.to_s[/\d+/].to_i
        end

        OutputFormatter.human_bytes(pages * page_size.to_i)
      end

      def uptime
        uptime_from_proc || OutputFormatter.capture('uptime')
      end

      # Reading /proc/uptime directly avoids the uptime(1) binary, which on some
      # distributions parses /var/run/utmp and reports the host boot time when
      # run inside a Docker container on an unprivileged LXC. /proc/uptime is
      # namespaced for the container and gives the value the user expects.
      def uptime_from_proc
        return nil unless File.exist?('/proc/uptime')

        seconds = File.read('/proc/uptime').split.first.to_f
        return nil if seconds <= 0

        load_avg = read_loadavg
        base = "up #{format_uptime(seconds)}"
        load_avg ? "#{base}, load average: #{load_avg}" : base
      rescue StandardError
        nil
      end

      def read_loadavg
        return nil unless File.exist?('/proc/loadavg')

        File.read('/proc/loadavg').split[0, 3].join(', ')
      rescue StandardError
        nil
      end

      def format_uptime(seconds)
        total = seconds.to_i
        days = total / 86_400
        hours = (total % 86_400) / 3600
        minutes = (total % 3600) / 60

        parts = []
        parts << "#{days}d" if days.positive?
        parts << "#{hours}h" if hours.positive?
        parts << "#{minutes}min" if minutes.positive? || parts.empty?
        parts.join(' ')
      end

      def disk
        path = Rails.configuration.data_path.to_s
        base = { 'Data path' => path }
        parsed = parse_df(path)
        return base.merge('Usage' => OutputFormatter.capture('df', '-kP', path)) unless parsed

        base.merge(parsed)
      end

      # `-kP` is portable: POSIX format (single line, no wrapping for long
      # device names like `/dev/mapper/pve-vm--115--disk--0`) and 1024-byte
      # blocks on both BSD (macOS) and GNU df. Parsing the values ourselves
      # avoids the BSD quirk where `df -hP` ignores `-h` and prints raw
      # 512-byte blocks.
      def parse_df(path)
        output = OutputFormatter.capture('df', '-kP', path)
        return nil if output.start_with?('failed', 'unavailable')

        filesystem, blocks, used, available, capacity = output.lines.last.to_s.split(/\s+/).first(5)
        return nil unless [blocks, used, available].all? { |v| v.to_s.match?(/\A\d+\z/) }

        {
          'Filesystem' => filesystem,
          'Total' => OutputFormatter.kb_to_human(blocks),
          'Used' => OutputFormatter.kb_to_human(used),
          'Available' => OutputFormatter.kb_to_human(available),
          'Capacity' => capacity,
        }
      end

      # Per-subdirectory sizes of the HELIOS data path, so support can see
      # at a glance which service (influxdb, postgresql, redis, …) is
      # consuming the volume. A single du call is much faster than one per
      # directory when the volumes contain many files.
      def data_volumes
        path = Rails.configuration.data_path.to_s
        return { 'Status' => 'data path unavailable' } unless File.directory?(path)

        entries = Dir.children(path).select { |name| File.directory?(File.join(path, name)) }.sort
        return { 'Status' => 'no data directories found' } if entries.empty?

        sizes = directory_sizes(entries.map { |name| File.join(path, name) })
        entries.index_with { |name| sizes[File.join(path, name)] || 'unknown' }
      end

      # `-k` is POSIX and reports in 1024-byte blocks on both BSD and GNU du.
      def directory_sizes(paths)
        output = OutputFormatter.capture('du', '-sk', *paths)
        return {} if output.start_with?('failed', 'unavailable')

        output.lines.each_with_object({}) do |line, acc|
          blocks, dir = line.split(/\s+/, 2)
          next unless blocks&.match?(/\A\d+\z/) && dir

          acc[dir.strip] = OutputFormatter.human_bytes(blocks.to_i * 1024)
        end
      end

      def os_release
        linux_os_release || macos_os_release || 'unavailable'
      end

      def linux_os_release
        return nil unless File.exist?('/etc/os-release')

        File.foreach('/etc/os-release') do |line|
          next unless line.start_with?('PRETTY_NAME=')

          return OutputFormatter.value_after(line, '=').to_s.delete_prefix('"').delete_suffix('"')
        end
        nil
      rescue StandardError
        nil
      end

      def macos_os_release
        return nil unless File.exist?('/usr/bin/sw_vers')

        fields = OutputFormatter.capture('sw_vers').lines.each_with_object({}) do |line, acc|
          key, value = line.split(':', 2)
          acc[key.strip] = value.strip if value
        end
        "#{fields['ProductName']} #{fields['ProductVersion']} (#{fields['BuildVersion']})"
      end

      def sysctl_available?
        %w[/usr/sbin/sysctl /sbin/sysctl].any? { |p| File.exist?(p) }
      end

      def format_cores(cores)
        whole = cores.round
        (cores - whole).abs < 0.05 ? whole.to_s : format('%.2f', cores)
      end
    end
  end
end
