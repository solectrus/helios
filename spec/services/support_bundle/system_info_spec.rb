RSpec.describe SupportBundle::SystemInfo do
  # Sanity check: every section must produce a value on the host that is
  # actually running the suite (Linux CI, macOS dev). No method should raise
  # because /proc, /sys, sysctl or a binary is missing.
  describe '.collect on the live host' do
    before do
      allow(SupportBundle::SystemInfo::DockerReport).to receive(:fetch_snapshot).and_return(
        { error: 'unavailable: stubbed' },
      )
      allow(Rails.configuration).to receive(:data_path).and_return(Dir.tmpdir)
    end

    # Each `collect` call shells out (df, free, uptime, …) — one example with
    # aggregate_failures keeps every section assertion independent while only
    # paying the cost once.
    it 'reports every section', :aggregate_failures do
      report = described_class.collect

      cpu_section = report[/=== CPU ===\n.*?(?=\n===|\z)/m]
      mem_section = report[/=== Memory ===\n.*?(?=\n===|\z)/m]
      uptime_section = report[/=== Uptime ===\n.*?(?=\n===|\z)/m]
      disk_section = report[/=== Disk ===\n.*?(?=\n===|\z)/m]

      expect(cpu_section).to match(/Cores\s+\S+/)
      expect(mem_section).to match(/Total\s+\S+/)
      expect(uptime_section.to_s.strip).not_to be_empty
      expect(disk_section).to match(/Total\s+\S+/)
      expect(disk_section).to match(/Available\s+\S+/)
    end
  end
end
