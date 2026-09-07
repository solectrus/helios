RSpec.describe ServiceRow::Component, type: :component do
  subject(:rendered) { render_inline(described_class.new(compose_service:, container:, lazy: false)) }

  let(:service_name) { 'dashboard' }
  let(:compose_service) { Compose::Service.new(service_name, 'image' => image) }
  let(:container) { build_container(state: 'running', health: 'healthy') }
  let(:image) { 'ghcr.io/solectrus/solectrus:latest' }

  before do
    Orchestration::PendingOperations.clear_all
    allow(Orchestration::AffectedServices).to receive(:compute).and_return([])
  end

  after { Orchestration::PendingOperations.clear_all }

  def build_container(state:, health:)
    orchestration_container(service: service_name, state:, health:, image:)
  end

  it 'marks a healthy container green' do
    expect(rendered.css('.bg-success')).to be_present
  end

  # Docker states HELIOS has no dedicated color for (dead, restarting) are an
  # error, not a neutral "not running".
  context 'with a container in an unexpected state' do
    let(:container) { build_container(state: 'dead', health: nil) }

    it 'marks it as an error' do
      expect(rendered.css('.bg-error')).to be_present
    end
  end

  # HELIOS manages itself last and sits visually apart from the stack it runs.
  context 'with the HELIOS row itself' do
    let(:service_name) { 'helios' }
    let(:image) { 'ghcr.io/solectrus/helios:latest' }

    it 'renders on its own background' do
      expect(rendered.to_html).to include('bg-base-300/60')
    end
  end

  # The update button does the same thing either way, but the reason tells the
  # user whether the image moved or only the configuration did.
  context 'when only the configuration changed' do
    before { allow(Orchestration::AffectedServices).to receive(:compute).and_return([service_name]) }

    it 'explains the pending recreate as a configuration change' do
      expect(rendered.to_html).to include('Configuration changed')
    end
  end
end
