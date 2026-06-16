module HostStats # rubocop:disable Metrics/ModuleLength
  Snapshot = Data.define(:cpu_percent, :cpu_cores, :ram_percent, :ram_free, :ram_total)

  # Placeholder used by the navbar's HostStats::Component on initial render
  # so a page render never pays for sampling. Real values are filled in by
  # the immediate poll the Stimulus controller fires on first connect
  # (when its polledAt value is still 0) and then every 5 s.
  EMPTY_SNAPSHOT = Snapshot.new(nil, nil, nil, nil, nil).freeze

  # Cache briefly so concurrent renders and the 5 s poller don't each pay the
  # cost (cheap on Linux, expensive on macOS dev — sysctl + vm_stat shell-outs).
  CACHE_TTL_SECONDS = 1.0

  # MemTotal/NCPU of the Docker host are effectively static; refetch at most
  # once a minute so the 5 s poll doesn't hit the Docker daemon every tick.
  HOST_LIMITS_TTL_SECONDS = 60.0

  # Linux process/memory pseudo-filesystem.
  PROC_ROOT = '/proc'.freeze

  @cache_mutex = Mutex.new

  def self.snapshot
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @cache_mutex.synchronize do
      if @cached_at.nil? || (now - @cached_at) > CACHE_TTL_SECONDS
        if @host_limits.nil? || (now - @host_limits_at) > HOST_LIMITS_TTL_SECONDS
          @host_limits = fetch_host_limits
          @host_limits_at = now
        end
        cpu = read_cpu_metrics(prev: @prev_cpu_sample, now: now, limits: @host_limits)
        @prev_cpu_sample = cpu[:sample] || @prev_cpu_sample
        ram = read_ram_metrics(limits: @host_limits)
        @cached_snapshot = Snapshot.new(cpu[:percent], cpu[:cores], ram[:percent], ram[:free], ram[:total])
        @cached_at = now
      end
      @cached_snapshot
    end
  end

  def self.reset_cache!
    @cache_mutex.synchronize do
      @cached_at = nil
      @cached_snapshot = nil
      @prev_cpu_sample = nil
      @host_limits = nil
      @host_limits_at = nil
    end
  end

  # Seam: specs override this to point /proc reads at a temp fixture directory.
  def self.proc_root
    PROC_ROOT
  end

  class << self
    private

    # `prev` is the previous return value's :sample, fed back so we can
    # compute the delta. nil on the first call → :percent is nil.
    def read_cpu_metrics(prev:, now:, limits:)
      cpu_from_host_cgroup(prev, now, limits) || cpu_from_proc_stat(prev) ||
        cpu_from_top || { percent: nil, cores: nil, sample: nil }
    end

    # CPU usage of the Docker host from its cgroup's cpu.stat. `usage_usec` is
    # cumulative; two reads give the busy time, divided by elapsed wall time
    # and the host's core count. Preferred over /proc/stat, which is not
    # namespaced for a container nested in an LXC and leaks the physical node.
    def cpu_from_host_cgroup(prev, now, limits)
      usage = HostCgroup.cpu_usage_usec
      return nil unless usage

      cores = limits[:ncpu]
      sample = { usage_usec: usage, at: now }
      return { percent: nil, cores: cores, sample: sample } unless prev&.key?(:usage_usec)

      elapsed = now - prev[:at]
      percent =
        if elapsed.positive? && cores&.positive?
          busy = (usage - prev[:usage_usec]) / 1_000_000.0
          ((busy / (elapsed * cores)) * 100).round.clamp(0, 100)
        end
      { percent: percent, cores: cores, sample: sample }
    end

    # Two /proc/stat reads give cumulative CPU jiffies; the delta is real CPU
    # usage (what /proc/loadavg only approximates). Numerator and denominator
    # come from the *same* file, so they stay consistent regardless of which
    # lxcfs/cgroup overlays are in play.
    def cpu_from_proc_stat(prev)
      sample = read_proc_stat
      return nil unless sample
      return { percent: nil, cores: sample[:cores], sample: sample } unless prev&.key?(:total)

      total_delta = sample[:total] - prev[:total]
      percent =
        if total_delta.positive?
          idle_delta = sample[:idle] - prev[:idle]
          (((total_delta - idle_delta).to_f / total_delta) * 100).round.clamp(0, 100)
        end
      { percent: percent, cores: sample[:cores], sample: sample }
    end

    # The `cpu` aggregate line is always first in /proc/stat — break after
    # parsing it instead of scanning the per-core lines that follow.
    def read_proc_stat
      File.foreach(File.join(proc_root, 'stat')) do |line|
        name, *rest = line.split
        return parse_cpu_totals(rest).merge(cores: Etc.nprocessors) if name == 'cpu'
      end
      nil
    rescue SystemCallError
      nil
    end

    # 'cpu' line columns: user nice system idle iowait irq softirq steal …
    # "Idle" = idle + iowait (top/htop convention).
    def parse_cpu_totals(nums)
      parsed = nums.map(&:to_i)
      { total: parsed.sum, idle: parsed[3].to_i + parsed[4].to_i }
    end

    # macOS dev fallback (no /proc/stat). `top -l 2` samples cumulative CPU
    # ticks twice and prints the busy/idle split of the second sample as a
    # percentage already normalised across all cores — matching the Linux
    # path's semantics. Replaces the old load-average proxy, which badly
    # overstated usage on many-core Macs (load 16 on 20 cores ≠ 80 % busy).
    # Blocks ~1 s on the shell-out, but only ever runs in dev.
    def cpu_from_top
      raw, status = Open3.capture2e('top', '-l', '2', '-n', '0', '-s', '0')
      return nil unless status.success?

      idle = raw.scan(/([\d.]+)%\s+idle/i).last&.first&.to_f
      cores = Etc.nprocessors
      return nil if idle.nil? || cores.zero?

      { percent: (100 - idle).round.clamp(0, 100), cores: cores, sample: nil }
    rescue SystemCallError
      nil
    end

    def read_ram_metrics(limits:)
      ram_from_host_cgroup(limits) || ram_from_proc || { percent: nil, free: nil, total: nil }
    end

    # RAM usage of the Docker host: bytes in use (HostCgroup.memory_used) over
    # the host's MemTotal. nil (→ /proc fallback) when the host cgroup is not
    # mounted, e.g. on bare-metal/VM hosts — where /proc/meminfo is accurate.
    def ram_from_host_cgroup(limits)
      used = HostCgroup.memory_used
      limit = limits[:mem_total]
      return nil unless used && limit&.positive?

      { percent: (used.to_f / limit * 100).round.clamp(0, 100), free: limit - used, total: limit }
    end

    def ram_from_proc
      total, available = mem_totals
      return nil if total.nil? || total.zero? || available.nil?

      { percent: ((total - available).to_f / total * 100).round, free: available, total: total }
    end

    def mem_totals
      mem_from_proc || mem_from_sysctl
    end

    def mem_from_proc
      total = available = nil
      File.foreach(File.join(proc_root, 'meminfo')) do |line|
        case line
        when /\AMemTotal:\s+(\d+)\s*kB/     then total = Regexp.last_match(1).to_i * 1024
        when /\AMemAvailable:\s+(\d+)\s*kB/ then available = Regexp.last_match(1).to_i * 1024
        end
        break if total && available
      end
      total ? [total, available] : nil
    rescue SystemCallError
      nil
    end

    # macOS dev fallback. "Available" = free + inactive + speculative pages —
    # closest equivalent to Linux's MemAvailable (reclaimable without swapping).
    def mem_from_sysctl
      total = capture_int('sysctl', '-n', 'hw.memsize')
      return nil if total.nil? || total.zero?

      available = sysctl_available_pages * Etc.sysconf(Etc::SC_PAGE_SIZE)
      available.zero? ? nil : [total, available]
    rescue SystemCallError
      nil
    end

    def sysctl_available_pages
      vm, status = Open3.capture2e('vm_stat')
      return 0 unless status.success?

      %w[free inactive speculative].sum do |kind|
        line = vm.lines.find { |l| l.match?(/\APages #{kind}:/i) }
        line.to_s[/\d+/].to_i
      end
    end

    def capture_int(*command)
      raw, status = Open3.capture2e(*command)
      status.success? && raw.strip.match?(/\A\d+\z/) ? raw.strip.to_i : nil
    rescue SystemCallError
      nil
    end

    # MemTotal and NCPU as the Docker daemon reports them — i.e. the Docker
    # host (Proxmox LXC, VM or bare metal), not the HELIOS container. These are
    # the denominators for the host cgroup's usage figures.
    def fetch_host_limits
      Orchestration::Connection.configure!
      info = Docker.info
      { mem_total: positive_int(info['MemTotal']), ncpu: positive_int(info['NCPU']) }
    rescue StandardError
      { mem_total: nil, ncpu: nil }
    end

    def positive_int(value)
      value.to_i if value.is_a?(Numeric) && value.positive?
    end
  end
end
