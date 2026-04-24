module SupportBundle
  # Collects a snapshot of the host environment (OS, CPU, memory, disk,
  # Docker) for inclusion in a support bundle. Each section is defensive:
  # if a command fails or a file is missing, its value degrades to a
  # short error line instead of aborting the whole report.
  module SystemInfo # rubocop:disable Metrics/ModuleLength
    module_function

    def collect
      sections.map { |title, body| format_section(title, body) }.join("\n")
    end

    def sections
      docker = fetch_docker_snapshot

      {
        'HELIOS' => helios,
        'Operating System' => operating_system(docker),
        'CPU' => cpu,
        'Memory' => memory,
        'Uptime' => capture('uptime'),
        'Disk' => disk,
        'Data Volumes' => data_volumes,
        'Docker Engine' => docker_engine(docker),
        'Docker Compose' => docker_compose,
        'Containers' => containers(docker),
      }
    end

    def helios
      {
        'Version' => Rails.configuration.x.git.commit_version,
        'Commit time' => Rails.configuration.x.git.commit_time,
        'Collected at' => Time.current.iso8601,
      }
    end

    # HELIOS usually runs inside a container itself, so `uname`/`/etc/os-release`
    # describe the HELIOS image, not the box the user actually administers.
    # Docker's /info endpoint reports the daemon host (the Proxmox LXC, a VM,
    # or bare metal), which is what support needs.
    def operating_system(docker)
      return local_os unless docker[:info]

      info = docker[:info]
      {
        'Operating system' => info['OperatingSystem'],
        'Kernel' => info['KernelVersion'],
        'Architecture' => info['Architecture'],
        'Hostname' => info['Name'],
      }
    end

    def local_os
      {
        'uname' => capture('uname', '-a'),
        'Release' => os_release,
        'Hostname' => Socket.gethostname,
        'Note' => 'Docker host unavailable; showing HELIOS container info',
      }
    end

    def cpu
      cpu_from_proc || cpu_from_sysctl || { 'Status' => 'unavailable' }
    end

    def cpu_from_proc
      return nil unless File.exist?('/proc/cpuinfo')

      cores = 0
      model = nil
      File.foreach('/proc/cpuinfo') do |line|
        cores += 1 if line.start_with?('processor')
        model ||= value_after(line, ':') if line.start_with?('model name')
      end

      { 'Model' => model || 'unknown', 'Cores' => cores }
    rescue StandardError => e
      { 'Status' => "unavailable: #{e.class}: #{e.message}" }
    end

    def cpu_from_sysctl
      return nil unless sysctl_available?

      model, cores = capture('sysctl', '-n', 'machdep.cpu.brand_string', 'hw.ncpu').split("\n", 2)
      { 'Model' => model || 'unknown', 'Cores' => cores || 'unknown' }
    end

    def memory
      memory_from_proc || memory_from_sysctl || { 'Status' => 'unavailable' }
    end

    def memory_from_proc
      return nil unless File.exist?('/proc/meminfo')

      entries = File.foreach('/proc/meminfo').each_with_object({}) do |line, acc|
        key, value = line.split(':', 2)
        acc[key] = value.strip if value
      end

      {
        'Total' => format_meminfo(entries['MemTotal']),
        'Available' => format_meminfo(entries['MemAvailable']),
        'Swap total' => format_meminfo(entries['SwapTotal']),
        'Swap free' => format_meminfo(entries['SwapFree']),
      }
    rescue StandardError => e
      { 'Status' => "unavailable: #{e.class}: #{e.message}" }
    end

    # /proc/meminfo reports values as "<kibibytes> kB"; convert to bytes
    # and reuse format_bytes so the unit auto-scales (e.g. "15.4 GB").
    def format_meminfo(raw)
      match = raw.to_s.match(/\A(\d+)\s*kB\z/)
      return 'unknown' unless match

      format_bytes((match[1].to_i * 1024).to_s)
    end

    def memory_from_sysctl
      return nil unless sysctl_available?

      memsize, pagesize = capture('sysctl', '-n', 'hw.memsize', 'hw.pagesize').split("\n", 2)

      {
        'Total' => format_bytes(memsize),
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

      format_bytes((pages * page_size.to_i).to_s)
    end

    def disk
      path = Rails.configuration.data_path.to_s
      # `-P` keeps the row on a single line even when the filesystem name
      # is long (e.g. `/dev/mapper/pve-vm--115--disk--0`), which otherwise
      # wraps and misaligns under `df -h` defaults.
      {
        'Data path' => path,
        'Usage' => capture('df', '-hP', path),
      }
    end

    # Per-subdirectory sizes of the HELIOS data path, so support can see
    # at a glance which service (influxdb, postgresql, redis, …) is
    # consuming the volume.
    def data_volumes
      path = Rails.configuration.data_path.to_s
      return { 'Status' => 'data path unavailable' } unless File.directory?(path)

      entries = Dir.children(path).select { |name| File.directory?(File.join(path, name)) }.sort
      return { 'Status' => 'no data directories found' } if entries.empty?

      entries.index_with { |name| directory_size(File.join(path, name)) }
    end

    def directory_size(path)
      # `-k` is POSIX and reports in 1024-byte blocks on both BSD and GNU
      # du, so we get a portable integer we can feed through format_bytes
      # for consistent units with the Memory section.
      output = capture('du', '-sk', path)
      return output if output.start_with?('failed', 'unavailable')

      blocks = output.split(/\s+/, 2).first
      return 'unknown' unless blocks.to_s.match?(/\A\d+\z/)

      format_bytes((blocks.to_i * 1024).to_s)
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

      [containers_summary(docker[:info]), '', render_container_table(list)].join("\n")
    end

    def render_container_table(list)
      rows =
        list
        .sort_by { |c| [c.info['State'] == 'running' ? 0 : 1, container_name(c)] }
        .map { |c| container_row(c) }
      render_table(%w[NAME STATE STATUS IMAGE], rows)
    end

    def container_name(container)
      container.info['Names']&.first&.delete_prefix('/') ||
        container.info['Id'].to_s[0, 12]
    end

    def container_row(container)
      info = container.info
      [container_name(container), info['State'], info['Status'], info['Image']]
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

    def containers_summary(info)
      "#{info['Containers']} total " \
        "(running: #{info['ContainersRunning']}, " \
        "stopped: #{info['ContainersStopped']})"
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

      # Multi-line values (e.g. df output) are indented under the key.
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

      line = File.read('/etc/os-release').lines.find { |l| l.start_with?('PRETTY_NAME=') }
      raw = value_after(line, '=')
      return nil unless raw

      raw.delete_prefix('"').delete_suffix('"')
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

    def format_bytes(raw)
      return raw unless raw.to_s.match?(/\A\d+\z/)

      bytes = raw.to_i
      %w[B KB MB GB TB].each do |unit|
        return "#{format('%.1f', bytes)} #{unit}" if bytes < 1024 || unit == 'TB'

        bytes = bytes.to_f / 1024
      end
    end

    def value_after(line, separator)
      return nil unless line

      parts = line.split(separator, 2)
      return nil if parts.length < 2

      parts.last.strip
    end
  end
end
