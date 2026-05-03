module SupportBundle
  module SystemInfo
    # Reads container limits from the cgroup filesystem (memory and CPU).
    # Prefer this over /proc/* on containers running in unprivileged LXCs:
    # /proc files are not namespaced there and leak the host's view, while
    # /sys/fs/cgroup is namespaced and reports the real limits the container
    # runs against.
    module CgroupReader
      module_function

      ROOT = '/sys/fs/cgroup'.freeze

      # cgroup v1 represents "no memory limit" as PAGE_COUNTER_MAX rounded to
      # page size — values close to 2**63. Anything beyond ~1 PiB is treated
      # as "unlimited" so the caller can fall back to /proc/meminfo on hosts
      # without a real cap.
      V1_MEMORY_UNLIMITED = (1 << 50)

      def v2?
        File.exist?(File.join(ROOT, 'cgroup.controllers'))
      end

      def source
        "cgroup #{v2? ? 'v2' : 'v1'} (container limit)"
      end

      def memory_limit
        v2 = v2?
        raw = read_first_line(v2 ? path('memory.max') : path('memory', 'memory.limit_in_bytes'))
        return nil unless raw
        return nil if v2 && raw == 'max'
        return nil unless raw.match?(/\A\d+\z/)

        value = raw.to_i
        v2 || value < V1_MEMORY_UNLIMITED ? value : nil
      end

      def memory_current
        raw = read_first_line(
          v2? ? path('memory.current') : path('memory', 'memory.usage_in_bytes'),
        )
        raw.to_i if raw&.match?(/\A\d+\z/)
      end

      def cpu_quota_cores
        quota, period = cpu_quota_period
        return nil unless quota && period && quota.positive? && period.positive?

        quota.to_f / period
      end

      def cpu_quota_period
        if v2?
          raw = read_first_line(path('cpu.max'))
          quota, period = raw&.split
          quota == 'max' ? [nil, nil] : [OutputFormatter.int_or_nil(quota), OutputFormatter.int_or_nil(period)]
        else
          [OutputFormatter.int_or_nil(read_first_line(path('cpu', 'cpu.cfs_quota_us'))),
           OutputFormatter.int_or_nil(read_first_line(path('cpu', 'cpu.cfs_period_us')))]
        end
      end

      # cpuset count clamped against host total: a cpuset that covers every
      # host CPU is not a real container restriction, so the caller should
      # fall back to /proc/cpuinfo. `host_cpu_count` is passed in to make
      # that decision visible at the call site.
      def cpuset_cores(host_cpu_count: nil)
        raw = read_cpuset
        return nil unless raw

        count = parse_cpuset_count(raw)
        return nil if !count.positive? || (host_cpu_count && count >= host_cpu_count)

        count.to_f
      end

      def read_cpuset
        paths =
          v2? ? %w[cpuset.cpus.effective cpuset.cpus] : %w[cpuset/cpuset.effective_cpus cpuset/cpuset.cpus]
        paths.filter_map { |p| read_first_line(path(p)) }.find(&:present?)
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

      def path(*segments)
        File.join(ROOT, *segments)
      end

      def read_first_line(path)
        return nil unless File.exist?(path)

        File.open(path, &:readline).strip
      rescue StandardError
        nil
      end
    end
  end
end
