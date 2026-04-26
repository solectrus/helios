module SupportBundle
  # Collects a snapshot of the host environment (OS, CPU, memory, disk,
  # Docker) for inclusion in a support bundle. Each section is defensive:
  # if a command fails or a file is missing, its value degrades to a
  # short error line instead of aborting the whole report.
  module SystemInfo # rubocop:disable Metrics/ModuleLength
    module_function

    # /proc files are not namespaced on unprivileged LXC, so /proc/meminfo,
    # /proc/cpuinfo and the uptime binary leak the Proxmox host's view (e.g.
    # 15 GB RAM, 4 CPUs, multi-day uptime) instead of the LXC's enforced
    # limits. cgroup v2/v1 files are namespaced and report the real limits
    # the container actually runs against, so we prefer them when present.
    CGROUP_ROOT = '/sys/fs/cgroup'.freeze

    # cgroup v1 represents "no memory limit" as PAGE_COUNTER_MAX rounded to
    # page size — values close to 2**63. Anything beyond ~1 PiB is treated
    # as "unlimited" so we fall back to /proc/meminfo on hosts without a
    # real cap.
    CGROUP_V1_MEMORY_UNLIMITED = (1 << 50)

    def collect
      sections.map { |title, body| format_section(title, body) }.join("\n")
    end

    def sections
      docker = fetch_docker_snapshot

      {
        'HELIOS' => helios,
        'Operating System' => operating_system(docker),
        'CPU' => cpu,
        'Memory' => memory(docker),
        'Uptime' => uptime,
        'Disk' => disk,
        'Data Volumes' => data_volumes,
        'Docker Engine' => docker_engine(docker),
        'Docker Compose' => docker_compose,
        'Docker Containers' => containers(docker),
        'Docker Networks' => docker_networks(docker),
      }
    end

    def helios
      {
        'Version' => Rails.configuration.x.git.commit_version,
        'Commit time' => Rails.configuration.x.git.commit_time,
        'Collected at' => Time.current.iso8601,
      }
    end

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
        'Hostname' => info['Name'],
      }
    end

    def local_os
      kernel, arch = capture('uname', '-sm').split(/\s+/, 2)
      {
        'Operating system' => os_release,
        'Kernel' => kernel || 'unknown',
        'Architecture' => arch || 'unknown',
        'Hostname' => Socket.gethostname,
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
      cores = [cgroup_cpu_quota_cores, cgroup_cpuset_cores].compact.min
      return nil unless cores

      {
        'Model' => proc_cpuinfo&.dig(:model) || 'unknown',
        'Cores' => format_cores(cores),
        'Source' => cgroup_source,
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
        model ||= value_after(line, ':') if line.start_with?('model name')
      end
      count.positive? ? { count: count, model: model } : nil
    rescue StandardError
      nil
    end

    def cpu_from_sysctl
      return nil unless sysctl_available?

      model, cores = capture('sysctl', '-n', 'machdep.cpu.brand_string', 'hw.ncpu').split("\n", 2)
      { 'Model' => model || 'unknown', 'Cores' => cores || 'unknown' }
    end

    def memory(docker = nil)
      memory_from_cgroup || memory_from_proc(docker) || memory_from_sysctl ||
        { 'Status' => 'unavailable' }
    end

    def memory_from_cgroup
      limit = cgroup_memory_limit
      return nil unless limit

      current = cgroup_memory_current
      result = { 'Total' => human_bytes(limit) }
      if current
        result['Used'] = human_bytes(current)
        result['Available'] = human_bytes([limit - current, 0].max)
      end
      result['Source'] = cgroup_source
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

      result = { 'Total' => human_bytes(daemon_total) }
      current = cgroup_memory_current
      if current&.positive?
        result['Used'] = human_bytes(current)
        result['Available'] = human_bytes([daemon_total - current, 0].max)
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

      human_bytes(match[1].to_i * 1024)
    end

    def memory_from_sysctl
      return nil unless sysctl_available?

      memsize, pagesize = capture('sysctl', '-n', 'hw.memsize', 'hw.pagesize').split("\n", 2)

      {
        'Total' => human_bytes(memsize.to_i),
        'Available' => sysctl_free_memory(pagesize),
      }
    end

    # vm_stat reports memory in pages; "free + inactive + speculative" is
    # the closest macOS equivalent to Linux's MemAvailable — pages that
    # can be reclaimed for new allocations without swapping.
    def sysctl_free_memory(page_size)
      return 'unknown' unless page_size.to_s.match?(/\A\d+\z/)

      vm = capture('vm_stat')
      pages = %w[free inactive speculative].sum do |kind|
        line = vm.lines.find { |l| l.match?(/\APages #{kind}:/i) }
        line.to_s[/\d+/].to_i
      end

      human_bytes(pages * page_size.to_i)
    end

    def uptime
      uptime_from_proc || capture('uptime')
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
      return base.merge('Usage' => capture('df', '-kP', path)) unless parsed

      base.merge(parsed)
    end

    # `-kP` is portable: POSIX format (single line, no wrapping for long
    # device names like `/dev/mapper/pve-vm--115--disk--0`) and 1024-byte
    # blocks on both BSD (macOS) and GNU df. Parsing the values ourselves
    # avoids the BSD quirk where `df -hP` ignores `-h` and prints raw
    # 512-byte blocks.
    def parse_df(path)
      output = capture('df', '-kP', path)
      return nil if output.start_with?('failed', 'unavailable')

      filesystem, blocks, used, available, capacity = output.lines.last.to_s.split(/\s+/).first(5)
      return nil unless [blocks, used, available].all? { |v| v.to_s.match?(/\A\d+\z/) }

      {
        'Filesystem' => filesystem,
        'Total' => kb_to_human(blocks),
        'Used' => kb_to_human(used),
        'Available' => kb_to_human(available),
        'Capacity' => capacity,
      }
    end

    def kb_to_human(kibibytes)
      human_bytes(kibibytes.to_i * 1024)
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
      output = capture('du', '-sk', *paths)
      return {} if output.start_with?('failed', 'unavailable')

      output.lines.each_with_object({}) do |line, acc|
        blocks, dir = line.split(/\s+/, 2)
        next unless blocks&.match?(/\A\d+\z/) && dir

        acc[dir.strip] = human_bytes(blocks.to_i * 1024)
      end
    end

    def fetch_docker_snapshot
      Orchestration::Connection.configure!
      {
        info: Docker.info,
        version: Docker.version,
        containers: Docker::Container.all(all: true),
      }
    rescue StandardError => e
      { error: "unavailable: #{e.class}: #{e.message}" }
    end

    def docker_engine(docker)
      return { 'Status' => docker[:error] } if docker[:error]

      version = docker[:version]
      info = docker[:info]

      {
        'Version' => version['Version'],
        'API version' => version['ApiVersion'],
        'OS/Arch' => "#{version['Os']}/#{version['Arch']}",
        'Storage driver' => info['Driver'],
      }
    end

    def docker_compose
      { 'Version' => capture('docker', 'compose', 'version', '--short') }
    end

    def containers(docker)
      return docker[:error] if docker[:error]

      list = docker[:containers]
      return 'No containers found.' if list.empty?

      [containers_summary(list), '', render_container_table(list)].join("\n")
    end

    def render_container_table(list)
      rows =
        list
        .sort_by { |c| [c.info['State'] == 'running' ? 0 : 1, container_name(c)] }
        .map { |c| container_row(c) }
      render_table(%w[NAME STATE STATUS IMAGE NETWORKS], rows)
    end

    def container_name(container)
      container.info['Names']&.first&.delete_prefix('/') ||
        container.info['Id'].to_s[0, 12]
    end

    def container_row(container)
      info = container.info
      [container_name(container), info['State'], info['Status'], info['Image'],
       container_networks(container).presence || '-']
    end

    def container_networks(container)
      networks = container.info.dig('NetworkSettings', 'Networks') || {}
      networks.keys.sort.join(',')
    end

    # Service-name resolution between containers depends on every peer being
    # attached to the same Docker network. When that breaks (e.g. a container
    # was recreated outside the compose project, or networks were renamed),
    # peers fall back to host-only DNS, which fails. Listing membership here
    # makes the mismatch visible at a glance: the outlier sits in its own row.
    def docker_networks(docker)
      return docker[:error] if docker[:error]

      list = docker[:containers]
      return 'No networks found.' if list.blank?

      membership = network_membership(list)
      return 'No networks found.' if membership.empty?

      rows = membership.sort.map { |name, names| [name, names.size.to_s, names.sort.join(', ')] }
      render_table(%w[NAME CONTAINERS NAMES], rows)
    end

    def network_membership(containers)
      containers.each_with_object(Hash.new { |h, k| h[k] = [] }) do |c, acc|
        networks = c.info.dig('NetworkSettings', 'Networks') || {}
        networks.each_key { |name| acc[name] << container_name(c) }
      end
    end

    def render_table(headers, rows)
      widths = column_widths(headers, rows)
      [headers, *rows].map { |row| render_row(row, widths) }.join("\n")
    end

    def column_widths(headers, rows)
      headers.each_with_index.map do |header, i|
        ([header.length] + rows.map { |row| row[i].to_s.length }).max
      end
    end

    def render_row(row, widths)
      row.each_with_index.map { |cell, i| cell.to_s.ljust(widths[i]) }.join('  ').rstrip
    end

    # Counting from the actual list we just fetched keeps the summary
    # consistent with the table below. /info's container counters can drift
    # on Docker Desktop/LinuxKit and report numbers that contradict the
    # real list, so we derive everything from one source.
    def containers_summary(list)
      running = list.count { |c| c.info['State'] == 'running' }
      "#{list.size} total (running: #{running}, stopped: #{list.size - running})"
    end

    def format_section(title, body)
      ["=== #{title} ===", *format_body(body), ''].join("\n")
    end

    def format_body(body)
      return body.to_s.lines.map(&:chomp) if body.is_a?(String)

      width = body.keys.map(&:length).max || 0
      body.map { |key, value| "#{key.to_s.ljust(width)}  #{format_value(value)}" }
    end

    def format_value(value)
      return value.to_s unless value.is_a?(String) && value.include?("\n")

      "\n#{value.chomp.lines.map { |l| "  #{l}" }.join}"
    end

    def capture(*)
      output, status = Open3.capture2e(*)
      return "failed (exit #{status.exitstatus}): #{output.strip}" unless status.success?

      output.strip
    rescue StandardError => e
      "unavailable: #{e.class}: #{e.message}"
    end

    def os_release
      linux_os_release || macos_os_release || 'unavailable'
    end

    def linux_os_release
      return nil unless File.exist?('/etc/os-release')

      File.foreach('/etc/os-release') do |line|
        next unless line.start_with?('PRETTY_NAME=')

        return value_after(line, '=').to_s.delete_prefix('"').delete_suffix('"')
      end
      nil
    rescue StandardError
      nil
    end

    def macos_os_release
      return nil unless File.exist?('/usr/bin/sw_vers')

      fields = capture('sw_vers').lines.each_with_object({}) do |line, acc|
        key, value = line.split(':', 2)
        acc[key.strip] = value.strip if value
      end
      "#{fields['ProductName']} #{fields['ProductVersion']} (#{fields['BuildVersion']})"
    end

    def sysctl_available?
      %w[/usr/sbin/sysctl /sbin/sysctl].any? { |p| File.exist?(p) }
    end

    def cgroup_v2?
      File.exist?(File.join(CGROUP_ROOT, 'cgroup.controllers'))
    end

    def cgroup_path(*segments)
      File.join(CGROUP_ROOT, *segments)
    end

    def cgroup_source
      "cgroup #{cgroup_v2? ? 'v2' : 'v1'} (container limit)"
    end

    def cgroup_memory_limit
      v2 = cgroup_v2?
      raw = read_first_line(v2 ? cgroup_path('memory.max') : cgroup_path('memory', 'memory.limit_in_bytes'))
      return nil unless raw
      return nil if v2 && raw == 'max'
      return nil unless raw.match?(/\A\d+\z/)

      value = raw.to_i
      v2 || value < CGROUP_V1_MEMORY_UNLIMITED ? value : nil
    end

    def cgroup_memory_current
      raw = read_first_line(
        cgroup_v2? ? cgroup_path('memory.current') : cgroup_path('memory', 'memory.usage_in_bytes'),
      )
      raw.to_i if raw&.match?(/\A\d+\z/)
    end

    def cgroup_cpu_quota_cores
      quota, period = cgroup_cpu_quota_period
      return nil unless quota && period && quota.positive? && period.positive?

      quota.to_f / period
    end

    def cgroup_cpu_quota_period
      if cgroup_v2?
        raw = read_first_line(cgroup_path('cpu.max'))
        quota, period = raw&.split
        quota == 'max' ? [nil, nil] : [int_or_nil(quota), int_or_nil(period)]
      else
        [int_or_nil(read_first_line(cgroup_path('cpu', 'cpu.cfs_quota_us'))),
         int_or_nil(read_first_line(cgroup_path('cpu', 'cpu.cfs_period_us')))]
      end
    end

    def cgroup_cpuset_cores
      raw = read_cpuset
      return nil unless raw

      count = parse_cpuset_count(raw)
      # A cpuset that covers every host CPU is not a real container
      # restriction; fall back to /proc/cpuinfo in that case.
      host = proc_cpuinfo&.dig(:count)
      return nil if !count.positive? || (host && count >= host)

      count.to_f
    end

    def read_cpuset
      paths =
        cgroup_v2? ? %w[cpuset.cpus.effective cpuset.cpus] : %w[cpuset/cpuset.effective_cpus cpuset/cpuset.cpus]
      paths.filter_map { |p| read_first_line(cgroup_path(p)) }.find(&:present?)
    end

    # cpuset format is a comma-separated list of CPU ids and ranges, e.g.
    # "0-1", "0,2,4-5". Empty string means "no CPUs", which we treat as
    # "no restriction known" rather than zero cores.
    def parse_cpuset_count(raw)
      raw.split(',').sum do |part|
        if part.include?('-')
          from, to = part.split('-', 2).map(&:to_i)
          [to - from + 1, 0].max
        elsif part.match?(/\A\d+\z/)
          1
        else
          0
        end
      end
    end

    def format_cores(cores)
      whole = cores.round
      (cores - whole).abs < 0.05 ? whole.to_s : format('%.2f', cores)
    end

    def read_first_line(path)
      return nil unless File.exist?(path)

      File.open(path, &:readline).strip
    rescue StandardError
      nil
    end

    def int_or_nil(raw)
      raw.to_s.match?(/\A-?\d+\z/) ? raw.to_i : nil
    end

    def human_bytes(bytes)
      return 'unknown' unless bytes.is_a?(Numeric)

      ActiveSupport::NumberHelper.number_to_human_size(bytes)
    end

    def value_after(line, separator)
      return nil unless line

      parts = line.split(separator, 2)
      return nil if parts.length < 2

      parts.last.strip
    end
  end
end
