# Reads the Docker host's own cgroup, bind-mounted read-only at
# /host/sys/fs/cgroup by the helios service (see Export::Services::Helios).
# A HELIOS container nested in a Proxmox LXC otherwise sees a fresh,
# un-namespaced /proc reporting the physical node rather than the LXC.
#
# cgroup v2 only — every method returns nil when the mount or a file is
# absent, so callers fall back to /proc on cgroup v1 and on bare-metal/VM
# hosts, where /proc is already accurate.
module HostCgroup
  module_function

  ROOT = '/host/sys/fs/cgroup'.freeze

  # Seam: specs override this to point at a temp directory of real fixtures.
  def root
    ROOT
  end

  # memory.stat fields the kernel can reclaim under pressure — subtracted from
  # memory.current for the "really used" figure, mirroring how /proc/meminfo's
  # MemAvailable accounts for reclaimable page cache and slab.
  RECLAIMABLE_MEM_STAT_KEYS = %w[inactive_file active_file slab_reclaimable].freeze

  # Total bytes charged to the host cgroup (anon + cache + kernel).
  def memory_current
    read_int('memory.current')
  end

  # Reclaimable bytes from memory.stat, or nil when none of the keys appear.
  def memory_reclaimable
    sum_stat_keys('memory.stat', RECLAIMABLE_MEM_STAT_KEYS)
  end

  # Bytes really in use: memory.current minus what the kernel can reclaim.
  # nil when either input is unavailable.
  def memory_used
    current = memory_current
    reclaimable = memory_reclaimable
    return nil unless current && reclaimable

    [current - reclaimable, 0].max
  end

  # Cumulative CPU time of the host cgroup, in microseconds.
  def cpu_usage_usec
    sum_stat_keys('cpu.stat', %w[usage_usec])
  end

  def read_int(name)
    path = File.join(root, name)
    return nil unless File.exist?(path)

    raw = File.read(path).strip
    raw.match?(/\A\d+\z/) ? raw.to_i : nil
  rescue SystemCallError
    nil
  end

  # Sums the values of `keys` in a flat "<key> <value>" stat file.
  def sum_stat_keys(name, keys)
    path = File.join(root, name)
    return nil unless File.exist?(path)

    values = File.foreach(path).filter_map do |line|
      key, value = line.split
      value.to_i if keys.include?(key) && value.to_s.match?(/\A\d+\z/)
    end
    values.empty? ? nil : values.sum
  rescue SystemCallError
    nil
  end
end
