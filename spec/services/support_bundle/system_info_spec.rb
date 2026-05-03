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
end
