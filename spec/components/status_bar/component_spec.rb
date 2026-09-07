RSpec.describe StatusBar::Component, type: :component do
  before do
    allow(RestoreRunner).to receive(:in_progress).and_return(nil)
    allow(BackupRunner).to receive(:in_progress).and_return(nil)
    allow(Orchestration::StackStatus).to receive(:service_counts).and_return(running: 2, total: 3)
  end

  # The bar names the services a restart would cover, so the user can tell
  # whether the pending change touches what they just edited.
  it 'lists the services waiting for a restart' do
    allow(Orchestration::StackStatus).to receive(:pending_restart_services).and_return(%w[dashboard influxdb])

    rendered = render_inline(described_class.new(status: :restart_required))

    expect(rendered.to_html).to include('Dashboard, InfluxDB')
  end

  it 'falls back to the plain status text when nothing is pending' do
    allow(Orchestration::StackStatus).to receive(:pending_restart_services).and_return([])

    rendered = render_inline(described_class.new(status: :restart_required))

    expect(rendered.to_html).not_to include('Dashboard, InfluxDB')
  end
end
