module HostStats
  Snapshot = Data.define(:cpu_percent, :cpu_cores, :ram_percent)

  # Cache briefly so concurrent renders and the 5 s poller don't each pay the
  # cost (cheap on Linux, expensive on macOS dev — sysctl + vm_stat shell-outs).
  CACHE_TTL_SECONDS = 1.0

  @cache_mutex = Mutex.new

  def self.snapshot
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @cache_mutex.synchronize do
      if @cached_at.nil? || (now - @cached_at) > CACHE_TTL_SECONDS
        cpu = read_cpu_metrics(prev: @prev_cpu_sample)
        @prev_cpu_sample = cpu[:sample] || @prev_cpu_sample
        @cached_snapshot = Snapshot.new(
          cpu_percent: cpu[:percent],
          cpu_cores: cpu[:cores],
          ram_percent: read_ram_percent,
        )
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
    end
  end

  class << self
    private

    # `prev` is the previous return value's :sample, fed back so we can
    # compute the jiffy delta. nil on the first call → :percent is nil.
    def read_cpu_metrics(prev:)
      cpu_from_proc_stat(prev) || cpu_from_sysctl || { percent: nil, cores: nil, sample: nil }
    end

    # Two /proc/stat reads give cumulative CPU jiffies; the delta is real CPU
    # usage (what /proc/loadavg only approximates). Numerator and denominator
    # come from the *same* file, so they stay consistent regardless of which
    # lxcfs/cgroup overlays are in play.
    def cpu_from_proc_stat(prev)
      sample = read_proc_stat
      return nil unless sample
      return { percent: nil, cores: sample[:cores], sample: sample } unless prev

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
      File.foreach('/proc/stat') do |line|
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

    # macOS dev fallback (no /proc/stat). Approximates with load/cores —
    # semantically looser than the Linux path, only used in dev.
    def cpu_from_sysctl
      raw, status = Open3.capture2e('sysctl', '-n', 'vm.loadavg')
      return nil unless status.success?

      load = raw.match(/[\d.]+/)&.then { |m| m[0].to_f }
      cores = Etc.nprocessors
      return nil if load.nil? || cores.zero?

      { percent: (load / cores * 100).round.clamp(0, 100), cores: cores, sample: nil }
    rescue SystemCallError
      nil
    end

    def read_ram_percent
      total, available = mem_totals
      return nil if total.nil? || total.zero? || available.nil?

      ((total - available).to_f / total * 100).round
    end

    def mem_totals
      mem_from_proc || mem_from_sysctl
    end

    def mem_from_proc
      total = available = nil
      File.foreach('/proc/meminfo') do |line|
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
  end
end
